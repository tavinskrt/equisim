import {
  type AuditEvent,
  AuditRecorder,
  type CalculationTrace,
  CapmInputs,
  compareNum,
  compareStr,
  DateTime,
  ExpectedReturn,
  MarketAnchors,
  PrepareValuationInputs,
  ResolveMarketAnchors,
  round,
  Ticker,
  ValuationCascade,
  ValuationParameters,
} from '../../src/core';
import { DomainCopy } from '../../src/copy/domain-copy';
import { errln, outln } from '../lib/files';
import { num2, pct, type ValidationContext, writeReport } from './context';

/** O que o log de avaliação registrou sobre as guardas de um ativo. */
interface Diagnostics {
  /**
   * Condições que barraram a vantagem competitiva residual, pelo nome do
   * `MoatBlock`. Vazia quando comprovada; nula quando o passo não rodou.
   */
  readonly moatBlocks: string[] | null;
  /** ROIC ou ROE mediano do ciclo, em fração. */
  readonly cycleReturn: number | null;
  /** Custo de capital de equilíbrio, em fração. */
  readonly terminalDiscount: number | null;
  /** Φ — capital externo em múltiplos da base inicial da janela. */
  readonly phi: number | null;
  /** Fator aplicado ao lucro-base: 1,0 quando a base ficou como observada. */
  readonly normalizationFactor: number | null;
  /** Veredito da Guarda 1: `domina`, `não domina` ou `não avaliável`. */
  readonly trendVerdict: string | null;
  /** Veredito da Guarda 3: `destoa` ou `dentro da banda e do desvio robusto`. */
  readonly deviationVerdict: string | null;
  /** Retorno do exercício corrente, em fração. */
  readonly latestReturn: number | null;
  /** Mediana do ciclo na série da via escolhida, em fração. */
  readonly cycleReturnOfBase: number | null;
  /**
   * `true` quando o ativo é de setor cíclico pesado e a Guarda 3 teve
   * precedência sobre a Guarda 1.
   */
  readonly cyclePrecedence: boolean;
  /** Fator antes da saturação em `[0,33; 3,00]`. */
  readonly rawFactor: number | null;
  /** `true` quando a saturação do fator foi acionada. */
  readonly saturated: boolean;
  /**
   * `true` quando o teto do fator caiu para 1,00 por reprovação na saúde
   * operacional, impedindo normalizar a base para cima.
   */
  readonly healthCapped: boolean;
  /**
   * `true` quando o ativo reprovou na saúde operacional mas é de setor cíclico,
   * e por isso ficou isento da trava na Porta 2a.
   */
  readonly healthExempt: boolean;
  /** Queda de lucro ou EBITDA no triênio recente, em fração. */
  readonly operationalDecline: number | null;
}

const emptyDiagnostics: Diagnostics = {
  moatBlocks: null,
  cycleReturn: null,
  terminalDiscount: null,
  phi: null,
  normalizationFactor: null,
  trendVerdict: null,
  deviationVerdict: null,
  latestReturn: null,
  cycleReturnOfBase: null,
  cyclePrecedence: false,
  rawFactor: null,
  saturated: false,
  healthCapped: false,
  healthExempt: false,
  operationalDecline: null,
};

/**
 * `true` quando a base foi normalizada apesar de inorgânica — o caso que a
 * correção de precedência da Guarda 2 destravou.
 */
const normalizedInorganicBase = (d: Diagnostics) =>
  d.phi !== null && d.phi > 1.0 && d.normalizationFactor !== null && Math.abs(d.normalizationFactor - 1.0) > 1e-6;

/** `true` quando só a rentabilidade barrou a vantagem residual. */
const moatBlockedOnlyByReturn = (d: Diagnostics) =>
  d.moatBlocks !== null && d.moatBlocks.length === 1 && d.moatBlocks[0] === 'rentabilidadeInsuficiente';

const numOrNull = (v: unknown) => (typeof v === 'number' ? v : null);

/**
 * Extrai os campos do evento de auditoria da avaliação.
 *
 * Lido do rastro de cálculo, não dos avisos: as chaves são estáveis, e os
 * avisos são texto para o usuário — mudam de redação sem aviso, e um relatório
 * que dependesse deles mediria a redação.
 */
function diagnosticsFrom(event: AuditEvent | null): Diagnostics {
  if (event === null) return emptyDiagnostics;

  // A **última** ocorrência, não a primeira: quando a via da firma reprova na
  // pós-condição da ponte de equity, a cascata reavalia pela via do
  // acionista e o mesmo passo aparece duas vezes. Quem produziu o preço
  // justo é o segundo, e ler o primeiro descreveria uma avaliação
  // descartada.
  const trace = (name: string): CalculationTrace | null => {
    let found: CalculationTrace | null = null;
    for (const c of event.calculations) if (c.formulaName === name) found = c;
    return found;
  };

  /** Percentual gravado no rastro, de volta a fração. `null` para 'n/d'. */
  const fraction = (v: unknown) => {
    const n = numOrNull(v);
    return n === null ? null : n / 100.0;
  };

  const moat = trace('Vantagem competitiva residual na perpetuidade')?.mappedVariables;
  const baseTrace = trace('Base do fluxo: normalização pelo ciclo');
  const base = baseTrace?.mappedVariables;
  const blockers = moat?.['condições que barraram'];

  return {
    moatBlocks: Array.isArray(blockers) ? blockers.map((b) => `${b}`) : null,
    cycleReturn: fraction(moat?.['ROIC do ciclo (% a.a.)']),
    terminalDiscount: fraction(moat?.['WACC de equilíbrio (% a.a.)']),
    phi: numOrNull(base?.['capital externo / base (Φ)']),
    normalizationFactor: baseTrace?.finalValue ?? null,
    trendVerdict: (base?.['guarda 1 — tendência'] as string | undefined) ?? null,
    deviationVerdict: (base?.['guarda 3 — desvio do ciclo'] as string | undefined) ?? null,
    latestReturn: fraction(base?.['retorno atual (% a.a.)']),
    cycleReturnOfBase: fraction(base?.['mediana do ciclo (% a.a.)']),
    cyclePrecedence: base?.['precedência do ciclo (setor cíclico)'] === true,
    rawFactor: numOrNull(base?.['fator bruto']),
    saturated: base?.['fator saturado'] === true,
    healthCapped: base?.['teto travado pela saúde'] === true,
    healthExempt: base?.['isento da trava por setor cíclico'] === true,
    operationalDecline: fraction(base?.['queda no triênio (%)']) ?? fraction(moat?.['queda no triênio (%)']),
  };
}

interface Row {
  readonly ticker: string;
  readonly outcome: string;
  readonly lane?: string;
  readonly sector?: string;
  readonly detail?: string;
  readonly growthOrigin?: string;
  readonly fairValue?: number;
  readonly price?: number;
  readonly upside?: number;
  readonly warnings?: number;
  /** Vantagem competitiva residual preservada na perpetuidade. */
  readonly moat?: boolean;
  /** O que as guardas registraram no log de avaliação. */
  readonly diagnostics?: Diagnostics;
}

const diagOf = (l: Row) => l.diagnostics ?? emptyDiagnostics;

function rowToJson(l: Row): Record<string, unknown> {
  const d = diagOf(l);
  const out: Record<string, unknown> = { ticker: l.ticker, saida: l.outcome };
  if (l.lane !== undefined) out['via'] = l.lane;
  if (l.sector !== undefined) out['setor'] = l.sector;
  if (l.growthOrigin !== undefined) out['crescimento'] = l.growthOrigin;
  if (l.fairValue !== undefined) out['justo'] = l.fairValue;
  if (l.price !== undefined) out['preco'] = l.price;
  if (l.upside !== undefined) out['potencial'] = l.upside;
  out['avisos'] = l.warnings ?? 0;
  out['moat'] = l.moat ?? false;
  if (d.moatBlocks !== null) out['moatBarradoPor'] = d.moatBlocks;
  if (d.cycleReturn !== null) out['retornoDoCiclo'] = d.cycleReturn;
  if (d.terminalDiscount !== null) out['custoDeCapitalTerminal'] = d.terminalDiscount;
  if (d.phi !== null) out['phi'] = d.phi;
  if (d.normalizationFactor !== null) out['fatorDeNormalizacao'] = d.normalizationFactor;
  if (d.trendVerdict !== null) out['guarda1'] = d.trendVerdict;
  if (d.deviationVerdict !== null) out['guarda3'] = d.deviationVerdict;
  if (d.latestReturn !== null) out['retornoCorrente'] = d.latestReturn;
  if (d.cycleReturnOfBase !== null) out['retornoDoCicloDaBase'] = d.cycleReturnOfBase;
  out['precedenciaDoCiclo'] = d.cyclePrecedence;
  if (d.rawFactor !== null) out['fatorBruto'] = d.rawFactor;
  out['fatorSaturado'] = d.saturated;
  out['tetoTravadoPelaSaude'] = d.healthCapped;
  out['isentoPorSetorCiclico'] = d.healthExempt;
  if (d.operationalDecline !== null) out['quedaNoTrienio'] = d.operationalDecline;
  if (l.detail !== undefined) out['detalhe'] = l.detail;
  return out;
}

const increment = <K>(map: Map<K, number>, key: K) => map.set(key, (map.get(key) ?? 0) + 1);

/** Ordem decrescente de contagem, estável no empate — a ordem de inserção. */
const byCountDesc = (entries: Iterable<[string, number]>) => [...entries].sort((a, b) => compareNum(b[1], a[1]));

/** Percentil por posição arredondada, como o relatório sempre leu. */
const quantile = (sorted: readonly number[], p: number) => sorted[round(p * (sorted.length - 1))]!;

/**
 * Validação fora da amostra da arquitetura de portas.
 *
 * **Por que existe.** Os treze parâmetros da decisão 25 foram calibrados sobre
 * dezoito ativos cujo volume financeiro diário mediano vai de R$ 36,6 mi a
 * R$ 1.541,9 mi — a amostra inteira está no decil superior de liquidez do
 * mercado, cuja mediana é de R$ 9,2 mi. Aplicar essas regras ao universo sem
 * medir o que acontece seria extrapolar a calibragem em silêncio.
 *
 * O que este relatório responde: qual a **distribuição de saídas por porta** no
 * universo elegível, e se as proporções fazem sentido setorialmente. Um
 * parâmetro que separa bem dezoito ativos e classifica 90% do universo na mesma
 * gaveta não está separando nada.
 */
export const OutOfSampleValidation = {
  /**
   * Executa a validação e escreve o relatório.
   *
   * - [ctx]: contexto com os repositórios de produção.
   * - [limit]: teto de ativos a avaliar, para execução parcial.
   * - [outputDir]: destino do relatório.
   */
  async run(ctx: ValidationContext, args: { outputDir: string; limit?: number }): Promise<void> {
    const today = DateTime.local(2026, 9, 4);

    outln('Levantando o universo negociável...');
    const universe = await ctx.fundamentals.universe();
    if (universe.isErr) {
      errln(`Universo indisponível: ${universe.failureOrNull!.message}`);
      return;
    }
    const tickers = universe.unwrap().slice(0, args.limit ?? 200);
    outln(`  ${tickers.length} ativos a avaliar\n`);

    const anchors = (await ResolveMarketAnchors.call({ macro: ctx.macro, benchmark: ctx.benchmark, asOf: today })).getOrElse(
      MarketAnchors.fallback2026,
    );

    outln(
      `Âncoras: CDI corrente ${pct(anchors.currentRiskFreeRate)} · IPCA ${pct(anchors.inflationCagr)} · ` +
        `PIB real ${pct(anchors.realEconomyGrowth)} · teto nominal ${pct(anchors.nominalEconomyGrowth)}\n`,
    );

    // O log de avaliação é a fonte do diagnóstico por ativo. Sem ele, a única
    // leitura possível de "dois passaram no critério de vantagem" seria análise
    // de texto dos avisos — e a pergunta aqui é metodológica: qual condição
    // barrou cada um, e quantos estavam a que distância dela.
    let last: AuditEvent | null = null;
    AuditRecorder.attach((e) => {
      last = e;
    });

    const rows: Row[] = [];
    let i = 0;
    for (const ticker of tickers) {
      i++;
      last = null;
      if (i % 10 === 0) process.stdout.write(`  ${i}/${tickers.length}\r`);

      const prepared = await PrepareValuationInputs.call({
        ticker,
        prices: ctx.prices,
        fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: today,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
      });
      if (prepared.isErr) {
        // Classificado pelo mesmo caminho das recusas da cascata: sem isso, os
        // motivos de "ativo inexistente" e "sem cotação na janela" existiam no
        // classificador sem que nada os alcançasse, e cinco ativos ficavam num
        // balde genérico tendo motivo perfeitamente nomeável.
        const reason = prepared.failureOrNull!.message;
        rows.push({ ticker: ticker.value, outcome: classifyRefusal(reason), detail: reason });
        continue;
      }

      const inputs = prepared.unwrap();
      const result = ValuationCascade.evaluate(inputs);
      if (result.isErr) {
        rows.push({
          ticker: ticker.value,
          outcome: classifyRefusal(result.failureOrNull!.message),
          detail: result.failureOrNull!.message,
          ...(inputs.sectorKey === null ? {} : { sector: inputs.sectorKey }),
        });
        continue;
      }

      const v = result.unwrap();
      rows.push({
        ticker: ticker.value,
        outcome: 'avaliado',
        lane: DomainCopy.model(v.model),
        ...(inputs.sectorKey === null ? {} : { sector: inputs.sectorKey }),
        fairValue: v.fairValue.reais,
        price: v.marketPrice.reais,
        upside: v.upside,
        warnings: v.warnings.length,
        growthOrigin: growthOriginOf(v.warnings),
        moat: hasMoat(v.warnings),
        diagnostics: diagnosticsFrom(last),
      });
    }
    AuditRecorder.detach();
    outln('\n');

    report(rows, anchors, args.outputDir);
  },
};

/**
 * Classifica a recusa pela mensagem, para agrupar no relatório.
 *
 * Vale tanto para a recusa da cascata quanto para a falha de preparação dos
 * insumos: a condição de encerramento da decisão 25 exige que **toda** saída
 * seja nomeada, e um balde genérico não é um nome.
 */
function classifyRefusal(message: string): string {
  if (message.includes('liquidez insuficiente')) return 'Porta 0 · liquidez';
  if (message.includes('histórico curto')) return 'Porta 0 · histórico';
  if (message.includes('patrimônio líquido não positivo')) return 'Porta 0 · solvência';
  if (message.includes('recuperação judicial')) return 'Porta 0 · continuidade';
  // A mensagem é "Nenhum exercício de X havia sido divulgado" — sem o "não"
  // que este teste procurava. O balde nunca disparava, e nove ativos caíam em
  // "outra recusa" tendo motivo perfeitamente nomeável.
  if (message.includes('havia sido divulgado')) return 'sem exercício';
  if (message.includes('não sustentam nenhuma')) return 'sem via aplicável';
  if (message.includes('não encontrado na fonte')) return 'ativo inexistente';
  if (message.includes('Sem cotações')) return 'sem cotação na janela';
  return 'insumos indisponíveis';
}

/** `true` quando a cascata declarou vantagem competitiva residual. */
const hasMoat = (warnings: readonly string[]) => warnings.some((w) => w.includes('Vantagem competitiva comprovada'));

/** Lê a origem do crescimento nos avisos, que é onde a cascata a declara. */
function growthOriginOf(warnings: readonly string[]): string {
  for (const w of warnings) {
    if (w.includes('Adotada a inflação')) return 'âncora';
    if (w.includes('sem crescimento')) return 'g = 0';
  }
  return 'fundamental';
}

function report(rows: readonly Row[], anchors: MarketAnchors, outputDir: string): void {
  const buf: string[] = [
    '# Validação fora da amostra — arquitetura de portas',
    '',
    `Executada em ${DateTime.now().toIso8601String().split('T')[0]} sobre ${rows.length} ativos do universo negociável.`,
    '',
  ];

  const byOutput = new Map<string, number>();
  for (const l of rows) increment(byOutput, l.outcome);
  buf.push('## Distribuição de saídas', '', '| Saída | Ativos | Fração |', '|---|---:|---:|');
  for (const [k, v] of byCountDesc(byOutput)) buf.push(`| ${k} | ${v} | ${pct(v / rows.length, 1)} |`);

  const evaluated = rows.filter((l) => l.outcome === 'avaliado');
  if (evaluated.length > 0) {
    const byLane = new Map<string, number>();
    const byOrigin = new Map<string, number>();
    for (const l of evaluated) {
      increment(byLane, l.lane ?? '?');
      increment(byOrigin, l.growthOrigin ?? '?');
    }
    buf.push('', '## Entre os avaliados', '', '| Via | Ativos |', '|---|---:|');
    for (const [k, v] of byLane) buf.push(`| ${k} | ${v} |`);
    buf.push('', '| Origem do crescimento | Ativos |', '|---|---:|');
    for (const [k, v] of byOrigin) buf.push(`| ${k} | ${v} |`);

    const withMoat = evaluated.filter((l) => l.moat === true);
    buf.push(
      '',
      '| Terminal | Ativos |',
      '|---|---:|',
      `| estado estacionário (ROIC_inf = WACC_inf) | ${evaluated.length - withMoat.length} |`,
      `| vantagem competitiva residual | ${withMoat.length} |`,
    );
    if (withMoat.length > 0) {
      buf.push('', `Com vantagem residual: ${withMoat.map((l) => l.ticker).sort(compareStr).join(', ')}.`);
    }

    moatSection(buf, evaluated);
    normalizationSection(buf, evaluated);

    const upsides = evaluated.map((l) => l.upside!).sort(compareNum);
    const q = (p: number) => quantile(upsides, p);
    buf.push(
      '',
      '## Dispersão do potencial de valorização',
      '',
      '| Percentil | Potencial |',
      '|---|---:|',
      `| mínimo | ${pct(upsides[0]!, 1)} |`,
      `| p10 | ${pct(q(0.1), 1)} |`,
      `| p25 | ${pct(q(0.25), 1)} |`,
      `| mediana | ${pct(q(0.5), 1)} |`,
      `| p75 | ${pct(q(0.75), 1)} |`,
      `| p90 | ${pct(q(0.9), 1)} |`,
      `| máximo | ${pct(upsides[upsides.length - 1]!, 1)} |`,
    );

    expectedReturnSection(buf, evaluated, anchors);
  }

  buf.push('', '## Ativo a ativo', '', '| Ativo | Setor | Saída | Via | Crescimento | Justo | Preço | Potencial |', '|---|---|---|---|---|---:|---:|---:|');
  for (const l of [...rows].sort((a, b) => compareStr(a.ticker, b.ticker))) {
    buf.push(
      `| ${l.ticker} | ${l.sector ?? '—'} | ${l.outcome} | ${l.lane ?? '—'} | ${l.growthOrigin ?? '—'} | ` +
        `${l.fairValue === undefined ? '—' : num2(l.fairValue, 2)} | ${l.price === undefined ? '—' : num2(l.price, 2)} | ` +
        `${l.upside === undefined ? '—' : pct(l.upside, 1)} |`,
    );
  }

  writeReport(`${outputDir}/validacao_fora_da_amostra.md`, `${buf.join('\n')}\n`);
  writeReport(`${outputDir}/validacao_fora_da_amostra.json`, JSON.stringify(rows.map(rowToJson), null, '  '));
}

/**
 * Distribuição das condições que barraram a vantagem competitiva residual.
 *
 * **É o instrumento de calibragem.** Saber que dois de cento e vinte passaram
 * não diz se o critério está apertado ou se o universo é comum; saber quantos
 * reprovaram só pela rentabilidade, e a que distância do corte, diz — e é o
 * que permite mover o parâmetro por medição em vez de por impressão.
 */
function moatSection(buf: string[], evaluated: readonly Row[]): void {
  const withDiagnostic = evaluated.filter((l) => diagOf(l).moatBlocks !== null);
  if (withDiagnostic.length === 0) return;

  const byCondition = new Map<string, number>();
  const first = new Map<string, number>();
  for (const l of withDiagnostic) {
    const blocks = diagOf(l).moatBlocks!;
    if (blocks.length === 0) continue;
    increment(first, blocks[0]!);
    for (const b of blocks) increment(byCondition, b);
  }

  buf.push(
    '',
    '### Por que a vantagem residual foi barrada',
    '',
    'Uma linha por condição, contando **todas** as que barraram cada ativo — os totais somam mais que o número de reprovados, e é essa a ' +
      'informação: quem reprova por duas condições continuaria reprovado se só uma fosse afrouxada.',
    '',
    '| Condição | Barrou | Foi a primeira |',
    '|---|---:|---:|',
  );
  for (const [k, v] of byCountDesc(byCondition)) buf.push(`| ${moatLabel(k)} | ${v} | ${first.get(k) ?? 0} |`);

  const byHealth = withDiagnostic
    .filter((l) => diagOf(l).moatBlocks!.includes('saudeOperacional') && diagOf(l).operationalDecline !== null)
    .sort((a, b) => compareNum(diagOf(b).operationalDecline!, diagOf(a).operationalDecline!));
  if (byHealth.length > 0) {
    buf.push(
      '',
      `Os ${byHealth.length} barrados pelo filtro de saúde operacional — resultado em queda no triênio, por mais alta que a ` +
        'mediana do ciclo ainda esteja:',
      '',
      '| Ativo | Queda no triênio | ROIC do ciclo |',
      '|---|---:|---:|',
    );
    for (const l of byHealth.slice(0, 10)) {
      const d = diagOf(l);
      buf.push(`| ${l.ticker} | ${pct(d.operationalDecline!, 1)} | ${d.cycleReturn === null ? '—' : pct(d.cycleReturn, 1)} |`);
    }
  }

  // **Seção inerte desde a decisão 36.** O bloco `rentabilidadeInsuficiente`
  // deixou de existir quando o degrau da vantagem competitiva virou decaimento
  // medido, de modo que `moatBlockedOnlyByReturn` nunca mais é verdadeiro e o
  // retorno antecipado abaixo sempre dispara. Fica como registro do regime
  // anterior; removê-la é limpeza para outra rodada.
  const profitabilityOnly = withDiagnostic.filter((l) => moatBlockedOnlyByReturn(diagOf(l)));
  if (profitabilityOnly.length === 0) return;

  const distances = profitabilityOnly
    .map(diagOf)
    .filter((d) => d.cycleReturn !== null && d.terminalDiscount !== null)
    .map((d) => d.cycleReturn! - d.terminalDiscount!)
    .sort(compareNum);
  if (distances.length === 0) return;

  const q = (p: number) => quantile(distances, p);
  buf.push(
    '',
    `Dos reprovados, ${profitabilityOnly.length} ${profitabilityOnly.length === 1 ? 'falhou' : 'falharam'} **apenas** na ` +
      'rentabilidade — cumprem crescimento orgânico e histórico. O excedente do ciclo sobre o custo de capital de equilíbrio nesses casos:',
    '',
    '| Percentil | Excedente |',
    '|---|---:|',
    `| p25 | ${pct(q(0.25), 1)} |`,
    `| mediana | ${pct(q(0.5), 1)} |`,
    `| p75 | ${pct(q(0.75), 1)} |`,
    `| p90 | ${pct(q(0.9), 1)} |`,
    `| máximo | ${pct(distances[distances.length - 1]!, 1)} |`,
  );
}

/** Rótulo legível para o nome do `MoatBlock`. */
function moatLabel(name: string): string {
  switch (name) {
    case 'semRetornoDoCiclo':
      return 'retorno do ciclo não medido';
    case 'semCustoDeCapital':
      return 'custo de capital não positivo';
    case 'historicoCurto':
      return 'histórico curto';
    case 'capitalExternoNaoMedido':
      return 'capital externo não medido';
    case 'crescimentoInorganico':
      return 'crescimento inorgânico';
    case 'rentabilidadeInsuficiente':
      return 'rentabilidade insuficiente';
    case 'saudeOperacional':
      return 'resultado em queda no triênio';
    case 'excedenteDegenerado':
      return 'excedente degenerado';
    default:
      return name;
  }
}

/**
 * Efeito da correção de precedência da Guarda 2.
 *
 * Conta quantos ativos tiveram a base normalizada **apesar** de Φ acima do
 * limiar — o conjunto que, sob a precedência anterior, levava o exercício de
 * pico à perpetuidade como se fosse patamar.
 */
function normalizationSection(buf: string[], evaluated: readonly Row[]): void {
  const wasNormalized = (l: Row) => {
    const f = diagOf(l).normalizationFactor;
    return f !== null && Math.abs(f - 1.0) > 1e-6;
  };
  const byTicker = (a: Row, b: Row) => compareStr(a.ticker, b.ticker);
  const byRawFactorDesc = (a: Row, b: Row) => compareNum(diagOf(b).rawFactor ?? 0, diagOf(a).rawFactor ?? 0);

  const unlocked = evaluated.filter((l) => normalizedInorganicBase(diagOf(l))).sort(byTicker);
  const normalizedCount = evaluated.filter(wasNormalized).length;

  buf.push(
    '',
    '### Normalização da base',
    '',
    '| Base | Ativos |',
    '|---|---:|',
    `| mantida como observada | ${evaluated.length - normalizedCount} |`,
    `| convergindo ao ciclo | ${normalizedCount} |`,
    `| das quais, com Φ acima do limiar | ${unlocked.length} |`,
  );
  const cyclicalOnes = evaluated.filter((l) => diagOf(l).cyclePrecedence);
  const unlockedByCycle = cyclicalOnes.filter((l) => wasNormalized(l) && diagOf(l).trendVerdict === 'domina').sort(byTicker);
  const saturatedOnes = evaluated.filter((l) => diagOf(l).saturated && !diagOf(l).healthCapped).sort(byRawFactorDesc);

  const exempt = evaluated.filter((l) => diagOf(l).healthExempt).sort(byTicker);
  const healthLockedOnes = evaluated.filter((l) => diagOf(l).healthCapped).sort(byRawFactorDesc);

  buf.push(
    '',
    '| Trava | Ativos |',
    '|---|---:|',
    `| em setor cíclico (Guarda 3 com precedência) | ${cyclicalOnes.length} |`,
    `| normalizados **por** essa precedência | ${unlockedByCycle.length} |`,
    `| com o fator saturado em [0,33; 3,00] | ${saturatedOnes.length} |`,
    `| com o teto travado em 1,00 pela saúde operacional | ${healthLockedOnes.length} |`,
    `| reprovados na saúde mas isentos por setor cíclico | ${exempt.length} |`,
  );

  const decline = (d: Diagnostics) => (d.operationalDecline === null ? '—' : pct(d.operationalDecline, 1));

  if (exempt.length > 0) {
    buf.push(
      '',
      'Isentos da trava por serem de setor cíclico. A queda entre o pico e o vale é oscilação do preço do insumo, e a convergência ao ' +
        'ciclo opera nos dois sentidos — limitada pela saturação, que vale igual. A vantagem residual não tem trava de saúde desde a decisão ' +
        '36: para eles também, quem decide é a persistência medida do excedente.',
      '',
      '| Ativo | Setor | Queda no triênio | Fator | Potencial |',
      '|---|---|---:|---:|---:|',
    );
    for (const l of exempt) {
      const d = diagOf(l);
      buf.push(`| ${l.ticker} | ${l.sector ?? '—'} | ${decline(d)} | ${num2(d.normalizationFactor!, 2)} | ${pct(l.upside!, 1)} |`);
    }
  }

  if (healthLockedOnes.length > 0) {
    buf.push(
      '',
      'Onde a saúde operacional proibiu normalizar para cima. **Não é a mesma coisa que a saturação**: ali o limite é de política sobre ' +
        `quanta autoridade um exercício tem; aqui a afirmação é que a mediana de ${ValuationParameters.cycleWindow} exercícios deixou de descrever ` +
        'a empresa.',
      '',
      '| Ativo | Queda no triênio | Fator bruto | Aplicado | Potencial |',
      '|---|---:|---:|---:|---:|',
    );
    for (const l of healthLockedOnes) {
      const d = diagOf(l);
      buf.push(`| ${l.ticker} | ${decline(d)} | ${num2(d.rawFactor!, 2)} | ${num2(d.normalizationFactor!, 2)} | ${pct(l.upside!, 1)} |`);
    }
  }

  if (unlockedByCycle.length > 0) {
    buf.push(
      '',
      'Em setor cíclico, a tendência deixou de segurar a base nestes — a perna de alta do ciclo tem a forma de uma tendência, e lê-la ' +
        'como patamar estrutural era o erro:',
      '',
      '| Ativo | Setor | Retorno corrente | Ciclo | Fator | Potencial |',
      '|---|---|---:|---:|---:|---:|',
    );
    for (const l of unlockedByCycle) {
      const d = diagOf(l);
      buf.push(
        `| ${l.ticker} | ${l.sector ?? '—'} | ${d.latestReturn === null ? '—' : pct(d.latestReturn, 1)} | ` +
          `${d.cycleReturnOfBase === null ? '—' : pct(d.cycleReturnOfBase, 1)} | ${num2(d.normalizationFactor!, 2)} | ${pct(l.upside!, 1)} |`,
      );
    }
  }

  if (saturatedOnes.length > 0) {
    buf.push(
      '',
      'Onde a saturação prendeu, com o fator que teria sido aplicado sem ela. **O preço justo destes é conservador por política**, e o ' +
        'resultado o declara:',
      '',
      '| Ativo | Fator bruto | Aplicado | Potencial |',
      '|---|---:|---:|---:|',
    );
    for (const l of saturatedOnes) {
      const d = diagOf(l);
      buf.push(`| ${l.ticker} | ${num2(d.rawFactor!, 2)} | ${num2(d.normalizationFactor!, 2)} | ${pct(l.upside!, 1)} |`);
    }
  }

  const notNormalized = evaluated.filter((l) => !wasNormalized(l));
  const byGuard = new Map<string, number>();
  for (const l of notNormalized) {
    const g1 = diagOf(l).trendVerdict;
    const g3 = diagOf(l).deviationVerdict;
    if (g1 === null || g3 === null) continue;
    const reason =
      g3 !== 'destoa'
        ? 'Guarda 3: o exercício não destoa do ciclo'
        : g1 === 'domina'
          ? 'Guarda 1: a tendência domina a reversão'
          : 'outro impedimento (retorno corrente não positivo ou não medido)';
    increment(byGuard, reason);
  }
  if (byGuard.size > 0) {
    buf.push('', 'Por que a base **não** foi normalizada, nos que ficaram como observados:', '', '| Guarda que decidiu | Ativos |', '|---|---:|');
    for (const [k, v] of byCountDesc(byGuard)) buf.push(`| ${k} | ${v} |`);
  }

  // A classe da SUZB3: destoa do ciclo, mas a tendência domina e a base fica
  // como observada. É a guarda que efetivamente decide esses casos — e não a de
  // comparabilidade, que a §12.5 do refinamento apontava como suspeita.
  const heldByTrend = notNormalized
    .filter((l) => {
      const d = diagOf(l);
      return d.deviationVerdict === 'destoa' && d.trendVerdict === 'domina' && d.latestReturn !== null && d.cycleReturnOfBase !== null;
    })
    .sort((a, b) => compareNum(b.upside ?? 0, a.upside ?? 0));
  if (heldByTrend.length > 0) {
    buf.push(
      '',
      `Os ${heldByTrend.length} que **destoam do ciclo e ainda assim ficam como observados** são segurados pela Guarda 1: a ` +
        'tendência do retorno domina a reversão à média, e o modelo lê o nível corrente como estrutural em vez de cíclico. Os dez de maior ' +
        'potencial:',
      '',
      '| Ativo | Retorno corrente | Ciclo | Φ | Potencial |',
      '|---|---:|---:|---:|---:|',
    );
    for (const l of heldByTrend.slice(0, 10)) {
      const d = diagOf(l);
      buf.push(
        `| ${l.ticker} | ${pct(d.latestReturn!, 1)} | ${pct(d.cycleReturnOfBase!, 1)} | ${d.phi === null ? '—' : num2(d.phi, 2)} | ${pct(l.upside!, 1)} |`,
      );
    }
  }

  // A tabela dos maiores fatores saiu daqui: com a saturação em [0,33; 3,00],
  // o topo é o próprio teto por construção, e listar dez linhas de "3,00" não
  // informa nada. Quem carrega a informação agora é a tabela de saturação
  // acima, que mostra o fator **bruto** que teria sido aplicado sem o limite.

  if (unlocked.length === 0) return;

  buf.push(
    '',
    unlocked.length === 1
      ? 'O único de base inorgânica normalizada é o que a precedência anterior deixava passar com o exercício corrente como patamar ' +
          'perene. Fator aplicado sobre o lucro observado:'
      : `Os ${unlocked.length} de base inorgânica normalizada são os que a precedência anterior deixava passar com o exercício corrente ` +
          'como patamar perene. Fator aplicado sobre o lucro observado:',
    '',
    '| Ativo | Φ | Fator |',
    '|---|---:|---:|',
  );
  for (const l of unlocked) {
    const d = diagOf(l);
    buf.push(`| ${l.ticker} | ${num2(d.phi!, 2)} | ${num2(d.normalizationFactor!, 3)} |`);
  }
}

/**
 * Retorno esperado transversal sobre o universo avaliado.
 *
 * **A seção mais larga que o trabalho tem.** É aqui que o estimador faz
 * sentido: medir uma carteira de cinco ativos contra ela mesma a centra no CDI
 * por construção, e a distribuição sobre os avaliados é a referência contra a
 * qual qualquer carteira passa a ser lida.
 */
function expectedReturnSection(buf: string[], evaluated: readonly Row[], anchors: MarketAnchors): void {
  const upsides = new Map(evaluated.map((l) => [Ticker.parse(l.ticker), l.upside!] as const));
  const estimated = ExpectedReturn.crossSection({ upsides, spotRiskFree: anchors.currentRiskFreeRate });

  const rates = [...estimated.values()].map((r) => r.expected).sort(compareNum);
  const q = (p: number) => quantile(rates, p);
  const atFloor = [...estimated.values()].filter((r) => r.floored).length;

  // A comparação que justifica a troca: o mesmo conjunto, pelo caminho antigo.
  const annualReturns = evaluated.map((l) => ExpectedReturn.annualizedFromUpside(l.upside!)).sort(compareNum);
  const qa = (p: number) => quantile(annualReturns, p);
  const negatives = annualReturns.filter((r) => r < 0).length;

  buf.push(
    '',
    '## Retorno esperado para otimização',
    '',
    `\`E[R_i] = CDI_spot + z(potencial) x prêmio\`, com CDI à vista de ${pct(anchors.currentRiskFreeRate)}, prêmio de ` +
      `${pct(CapmInputs.defaultMarketPremium)} e escore robusto confinado a ${num2(ExpectedReturn.defaultZCap, 1)} desvios sobre a ` +
      `seção dos ${evaluated.length} avaliados.`,
    '',
    '| Percentil | Transversal | Anualização do potencial |',
    '|---|---:|---:|',
    `| mínimo | ${pct(rates[0]!, 1)} | ${pct(annualReturns[0]!, 1)} |`,
    `| p10 | ${pct(q(0.1), 1)} | ${pct(qa(0.1), 1)} |`,
    `| p25 | ${pct(q(0.25), 1)} | ${pct(qa(0.25), 1)} |`,
    `| mediana | ${pct(q(0.5), 1)} | ${pct(qa(0.5), 1)} |`,
    `| p75 | ${pct(q(0.75), 1)} | ${pct(qa(0.75), 1)} |`,
    `| p90 | ${pct(q(0.9), 1)} | ${pct(qa(0.9), 1)} |`,
    `| máximo | ${pct(rates[rates.length - 1]!, 1)} | ${pct(annualReturns[annualReturns.length - 1]!, 1)} |`,
    '',
    `Pela anualização do potencial, ${negatives} dos ${annualReturns.length} avaliados entrariam num otimizador de média-variância com retorno ` +
      'esperado **negativo** — o que não é ordenação ruim, é ausência de alocação. Pelo estimador transversal, ' +
      `${atFloor === 0 ? 'nenhum tocou' : `${atFloor} tocaram`} o piso de zero, e a ordenação por potencial é preservada em toda a faixa.`,
  );
}
