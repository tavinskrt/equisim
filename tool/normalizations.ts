// Por que o lucro de partida de cada ativo foi normalizado, e em que direção.
//
// **O pedido.** O orientador refez os valuations por Gordon e chegou aos preços
// do motor por centavos; pediu, em 14/10/2026, que se detalhasse o motivo das
// normalizações — por que acontecem, e por que para cima ou para baixo —, sem
// retirá-las. Esta ferramenta lista a decisão de cada ativo avaliado, com os
// números que a tomaram: o retorno do último exercício, o típico (a mediana dos
// oito anteriores), o teste de destoar, as travas e o fator.
//
// Roda sobre a entrada congelada de 14/09/2026, na montagem do aplicativo — a
// mesma do gabarito —, e lê o registro `BaseNormalization` que a cascata deixa
// nos diagnósticos: nada aqui recalcula a guarda.
//
// Uso:
//   npm run tool -- normalizations
//
// Grava docs/validacao/normalizacoes.md.

import {
  type BaseNormalization,
  BaseNormalizationOutcome,
  compareNum,
  type Ticker,
  ValuationCascade,
  ValuationLane,
  ValuationParameters,
} from '../src/core';
import { outln, writeText } from './lib/files';
import { Frozen } from './validation/frozen';

const output = 'docs/validacao/normalizacoes.md';

const pct = (v: number | null): string => (v === null ? '—' : `${(v * 100).toFixed(1).replaceAll('.', ',')}%`);

const num = (v: number | null, decimals = 2): string => (v === null ? '—' : v.toFixed(decimals).replaceAll('.', ','));

function result(o: BaseNormalizationOutcome): string {
  if (o === BaseNormalizationOutcome.upward) return 'para cima';
  if (o === BaseNormalizationOutcome.downward) return 'para baixo';
  if (o === BaseNormalizationOutcome.withinNormal) return 'dentro do normal';
  if (o === BaseNormalizationOutcome.trend) return 'novo patamar (tendência)';
  if (o === BaseNormalizationOutcome.healthLocked) return 'travada pela queda';
  if (o === BaseNormalizationOutcome.rebuilt) return 'reconstruída do ciclo';
  if (o === BaseNormalizationOutcome.noCycle) return 'sem ciclo medível';
  return 'imposta';
}

/** Por que destoou: pela razão, pela distância ou pelos dois. */
function criterion(n: BaseNormalization): string {
  const r = n.ratio;
  const z = n.robustZ;
  if (r === null || z === null) return '—';
  const byRatio = r < ValuationParameters.bandLow || r > ValuationParameters.bandHigh;
  const byDistance = z > ValuationParameters.robustZ;
  if (!n.deviates) return 'não destoou';
  if (byRatio && byDistance) return 'razão e distância';
  return byRatio ? 'razão' : 'distância';
}

function observation(n: BaseNormalization): string {
  const parts: string[] = [];
  if (n.saturated) parts.push(`fator limitado (pedia ${num(n.rawFactor)}×)`);
  if (
    n.cyclicalPrecedence &&
    n.trendDominates &&
    (n.outcome === BaseNormalizationOutcome.upward || n.outcome === BaseNormalizationOutcome.downward)
  ) {
    parts.push('commodity: ciclo antes da tendência');
  }
  if (n.healthCapped) parts.push(`queda de ${pct(n.operationalDecline)} em 3 anos (pedia ${num(n.rawFactor)}×)`);
  if (n.healthExempt && n.factor > 1) parts.push(`queda de ${pct(n.operationalDecline)}, isenta por ser commodity`);
  if (n.rebuilt) parts.push(`${pct(n.rebuiltPositiveShare)} da janela no lucro`);
  return parts.join('; ');
}

export async function main(_args: string[]): Promise<void> {
  const c = await Frozen.build();
  const rows: { t: Ticker; n: BaseNormalization }[] = [];
  for (const t of c.universe) {
    const prep = await c.prepare(t);
    if (prep.isErr) continue;
    const r = ValuationCascade.evaluate(prep.unwrap());
    if (r.isErr) continue;
    const n = r.unwrap().diagnostics?.baseNormalization ?? null;
    if (n !== null) rows.push({ t, n });
  }

  const order = BaseNormalizationOutcome.values;
  rows.sort((a, b) => {
    const o = compareNum(order.indexOf(a.n.outcome), order.indexOf(b.n.outcome));
    if (o !== 0) return o;
    return compareNum(b.n.factor, a.n.factor);
  });
  const count = new Map(order.map((o) => [o, rows.filter((l) => l.n.outcome === o).length] as const));

  const md: string[] = [
    '# Por que o lucro de partida foi normalizado',
    '',
    'Gerado por `npm run tool -- normalizations` sobre a entrada congelada de 14/09/2026, na montagem do aplicativo. ' +
      'Pedido do orientador em 14/10/2026: o porquê de cada normalização e a direção dela. **Não edite à mão.**',
    '',
    '## A regra, em uma frase',
    '',
    'Um ano só pode ter sido um pico ou um vale, e o preço justo é proporcional ao lucro de partida. O motor compara ' +
      'o retorno sobre o capital do último exercício com o **retorno típico** da empresa — a mediana dos 8 exercícios ' +
      'anteriores — e, quando os dois destoam, parte do lucro que a empresa de hoje teria rendendo o típico:',
    '',
    '```',
    `fator = típico ÷ último   (limitado entre ${num(ValuationParameters.baseFactorFloor)} e ${num(ValuationParameters.baseFactorCeiling)})`,
    'lucro de partida = lucro publicado × fator',
    '```',
    '',
    '- **Para cima** quando o último ano rendeu abaixo do típico (um vale); **para baixo** quando rendeu acima (um pico).',
    `- **Destoa** quando o último ano dividido pelo típico sai de ${num(ValuationParameters.bandLow)} a ` +
      `${num(ValuationParameters.bandHigh)} (*razão*), ou quando a distância entre os dois passa de ` +
      `${num(ValuationParameters.robustZ, 1)} desvios típicos da janela (*distância*).`,
    '- **Não normaliza** quando o retorno tem tendência que domina a volta ao típico (o último ano é o novo patamar) — ' +
      'exceto em commodity, onde a alta do ciclo tem cara de tendência —, nem para cima quando o lucro ou o EBITDA caiu ' +
      `mais de ${pct(ValuationParameters.maxOperationalDecline)} em 3 anos.`,
    '- **Reconstrói** quando o último ano deu prejuízo: o típico sobre o capital de hoje, se ele é positivo e ao menos ' +
      `${pct(ValuationParameters.minPositiveFlow)} da janela deu lucro.`,
    '',
    'O porquê de cada ativo também está no painel de logs, no passo "Base do fluxo", e na tela Editar valuation, no ' +
      'cartão do lucro de partida.',
    '',
    `## Quantos, de ${rows.length} avaliados`,
    '',
    '| Resultado | Ativos |',
    '|---|---|',
  ];
  for (const o of order) {
    if (count.get(o)! > 0) md.push(`| ${result(o)} | ${count.get(o)} |`);
  }
  md.push(
    '',
    '## Ativo a ativo',
    '',
    '"Último" é o retorno sobre o capital (via da firma) ou sobre o patrimônio (via do acionista) do exercício mais ' +
      'recente; "típico" é a mediana dos anteriores. "Destoou por" diz qual critério decidiu.',
    '',
    '| Ativo | Via | Resultado | Último | Típico (anos) | Razão | Desvios | Destoou por | Fator | Observação |',
    '|---|---|---|---|---|---|---|---|---|---|',
  );
  for (const { t, n } of rows) {
    const years = n.windowYears;
    md.push(
      `| ${t.value} ` +
        `| ${n.lane === ValuationLane.firm ? 'firma' : 'acionista'} ` +
        `| ${result(n.outcome)} ` +
        `| ${pct(n.latestReturn)} (${n.latestYear ?? '—'}) ` +
        `| ${pct(n.cycleReturn)} (${years === null ? '—' : `${years.first}–${years.last}`}) ` +
        `| ${num(n.ratio)} ` +
        `| ${num(n.robustZ, 1)} ` +
        `| ${criterion(n)} ` +
        `| ${num(n.factor)}× ` +
        `| ${observation(n)} |`,
    );
  }
  writeText(output, `${md.join('\n')}\n`);

  outln(`avaliados: ${rows.length}`);
  for (const o of order) {
    if (count.get(o)! > 0) outln(`  ${result(o)}: ${count.get(o)}`);
  }
  outln(`gravado ${output}`);
}
