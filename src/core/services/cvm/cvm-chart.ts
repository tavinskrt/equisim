/**
 * Leitura do plano de contas padronizado da CVM.
 *
 * **Por que este arquivo existe.** A CVM publica DFP e ITR com um plano de
 * contas que parece padronizado — `1 = Ativo Total`, `3.01 = Receita` — e
 * **não é um só**. A conferência de 11/09/2026 encontrou quatro layouts no
 * universo, e o lucro líquido mora em código diferente em cada um:
 *
 * | layout | consolidado | individual |
 * |---|---|---|
 * | Não financeira (513 cias) | 3.11 | 3.11 |
 * | Banco "**de** Intermediação" (18) | 3.11 | 3.11 |
 * | Banco "**da** Intermediação" (7) | **3.09** | **3.13** |
 * | Seguradora (4) | 3.13 | 3.13 |
 *
 * Os dois de banco se distinguem por **uma preposição** num rótulo em
 * português. Ler `3.11` como lucro no individual do Itaú devolve *"Reversão
 * dos Juros sobre Capital Próprio"*; ler `3.05` como EBIT num banco devolve
 * "Resultado Antes dos Tributos" — R$ 47,6 bi contra R$ 42,1 bi de lucro.
 *
 * **Por isso a resolução é por evidência, não por tabela de códigos.** Cada
 * conta semântica é procurada por padrão de descrição entre as linhas de
 * nível raso, e o código serve de desempate e de conferência. Onde o layout
 * não tem o conceito — EBIT de banco não existe —, a resposta é `null`, nunca
 * um número plausível.
 *
 * Ver `docs/validacao/cvm_conferencia.md`.
 */

import { DartEnum, type WireKeyed } from '../../lang/dart-enum';
import { round, tryParseInt } from '../../lang/num';

const DIGITS = /^\d+$/;
const INT64_MAX = 9223372036854775807n;

/**
 * Texto decimal para centavos, com a escala aplicada, em aritmética inteira.
 *
 * **A escala entra antes do arredondamento**, e a ordem importa: com
 * `ESCALA_MOEDA` igual a MIL, um valor de `1.0005` são R$ 1.000,50 —
 * 100.050 centavos exatos. Arredondar para centavos primeiro daria R$ 1,00
 * e depois R$ 1.000,00, perdendo cinquenta centavos por multiplicar o
 * resíduo descartado.
 *
 * Usa `bigint` no caminho: o ativo total de uma companhia grande em
 * centavos passa de 1e14, e a escala MIL o multiplica de novo. O resultado
 * é recusado se não couber em inteiro de 64 bits, em vez de estourar em
 * silêncio.
 */
function textToCents(raw: string, scale: number): number | null {
  let s = raw.trim();
  if (s.length === 0 || scale <= 0) return null;
  let negative = false;
  if (s.startsWith('-')) {
    negative = true;
    s = s.substring(1);
  } else if (s.startsWith('+')) {
    s = s.substring(1);
  }
  const parts = s.split('.');
  if (parts.length > 2) return null;
  const whole = parts[0]!.length === 0 ? '0' : parts[0]!;
  const decimals = parts.length === 2 ? parts[1]! : '';
  if (!DIGITS.test(whole)) return null;
  if (decimals.length > 0 && !DIGITS.test(decimals)) {
    return null;
  }

  // `bruto` = mantissa / 10^casas. Os centavos são
  // `mantissa × escala × 100 / 10^casas`, arredondados meio para cima —
  // tudo em inteiro, sem passar por ponto flutuante.
  const mantissa = BigInt(`${whole}${decimals}`);
  const divisor = 10n ** BigInt(decimals.length);
  const numerator = mantissa * BigInt(scale) * 100n;
  let v = numerator / divisor;
  const remainder = numerator % divisor;
  if (remainder * 2n >= divisor) v += 1n;
  if (negative) v = -v;

  if (v > INT64_MAX || v < -INT64_MAX) return null;
  return Number(v);
}

/**
 * Uma linha de demonstração, como a CVM a publica.
 *
 * **O valor é guardado em centavos inteiros**, e não em ponto flutuante. O
 * CSV traz `VL_CONTA` como texto — `265438605.0000000000` — e uma escala em
 * `ESCALA_MOEDA`, quase sempre MIL. Converter o texto para ponto flutuante e
 * depois de volta para centavos presume que o número esteja limpo, o que é
 * presunção desnecessária quando a origem é texto. [CvmAccountLine.fromText]
 * vai do texto ao inteiro sem passar por ponto flutuante.
 */
export class CvmAccountLine {
  /** `CD_CONTA` — o código do plano, com níveis separados por ponto. */
  readonly code: string;

  /** `DS_CONTA` — a descrição. Padronizada no nível raso, texto livre abaixo. */
  readonly label: string;

  /** Valor em **centavos**, já com a escala aplicada. É a forma canônica. */
  readonly cents: number;

  private constructor(code: string, label: string, cents: number) {
    this.code = code;
    this.label = label;
    this.cents = cents;
  }

  /** Declara a linha a partir dos centavos. */
  static inCents(args: { code: string; label: string; cents: number }): CvmAccountLine {
    return new CvmAccountLine(args.code, args.label, args.cents);
  }

  /**
   * Declara a linha a partir de um valor em reais, **arredondando**.
   *
   * O nome diz o que ela é: ponto flutuante não representa exatamente toda
   * quantia decimal, e converter de volta para centavos arredonda. Serve para
   * teste e para quem já tem o número pronto de outra fonte.
   *
   * **A ingestão da CVM não usa isto** — usa [CvmAccountLine.fromText], que
   * vai do texto do CSV ao inteiro sem ponto flutuante no caminho.
   */
  static approximate(args: { code: string; label: string; value: number }): CvmAccountLine {
    return new CvmAccountLine(args.code, args.label, round(args.value * 100));
  }

  /**
   * Declara a linha a partir do texto do CSV, **sem ponto flutuante**.
   *
   * - [value]: `VL_CONTA` como veio, com ou sem sinal e casas decimais.
   * - [scale]: 1000 para `ESCALA_MOEDA` igual a MIL, 1 caso contrário.
   *
   * Devolve `null` para texto que não seja número — o que é resposta, e não
   * falha: linha ilegível não entra na demonstração.
   */
  static fromText(args: { code: string; label: string; value: string; scale?: number }): CvmAccountLine | null {
    const c = textToCents(args.value, args.scale ?? 1);
    return c === null ? null : new CvmAccountLine(args.code, args.label, c);
  }

  /** Valor em reais. **Vista derivada** — a fonte da verdade é [cents]. */
  get value(): number {
    return this.cents / 100.0;
  }

  /** Profundidade do código: `3` é 1, `3.01` é 2, `3.01.01` é 3. */
  get depth(): number {
    return this.code.split('.').length;
  }
}

/**
 * Qual dos planos de contas a companhia usa.
 *
 * **Não é setor** — é a forma da demonstração que a companhia entregou. Uma
 * mesma empresa pode mudar de layout entre exercícios, e por isso a detecção
 * é feita por documento e não guardada por CNPJ.
 */
export class CvmLayout extends DartEnum implements WireKeyed {
  readonly wireKeyed = true as const;

  /** Plano padrão: `3.01 = Receita de Venda de Bens e/ou Serviços`. */
  static readonly corporate = new CvmLayout('corporate', 0, 'corporativo');

  /**
   * Intermediação financeira. **Não tem EBIT** — a estrutura não separa
   * resultado operacional de resultado financeiro, porque o financeiro *é* a
   * operação.
   */
  static readonly financialIntermediation = new CvmLayout('financialIntermediation', 1, 'intermediacaoFinanceira');

  /** Atividades seguradoras e resseguradoras. Também sem EBIT. */
  static readonly insurer = new CvmLayout('insurer', 2, 'seguradora');

  /** Nenhum padrão reconhecido. Tudo que dependa de layout devolve `null`. */
  static readonly unknown = new CvmLayout('unknown', 3, 'desconhecido');

  static readonly values: readonly CvmLayout[] = [
    CvmLayout.corporate,
    CvmLayout.financialIntermediation,
    CvmLayout.insurer,
    CvmLayout.unknown,
  ];

  /**
   * Chave gravada nas saídas — pacote de dados, rastro de auditoria,
   * relatório. É dado, e não nome de código: renomear o valor não a muda.
   */
  readonly key: string;

  private constructor(name: string, index: number, key: string) {
    super(name, index);
    this.key = key;
  }

  protected get typeName(): string {
    return 'CvmLayout';
  }

  /**
   * `true` quando a estrutura separa resultado operacional do financeiro.
   *
   * É a condição para que exista EBIT. Banco e seguradora não a satisfazem, e
   * [CvmChart.ebit] devolve `null` para eles — o que é o certo: a via da
   * firma já os recusa pela Porta 1.
   */
  get hasOperatingResult(): boolean {
    return this === CvmLayout.corporate;
  }
}

const ACCENTED = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
const PLAIN = 'aaaaaeeeeiiiiooooouuuucn';

const RE_PROFIT = /(lucro|prejuizo)/;
const RE_PER_SHARE = /por acao/;
const RE_CONTINUED = /(des)?continuada/;
const RE_BEFORE_TAXES = /antes.*(tributa|tributos|imposto)/;
const RE_TAXES = /(imposto de renda|provisao para ir|tributos sobre o lucro)/;
const RE_EBIT = /antes do resultado financeiro/;
const RE_NET_INCOME_EXCLUDED = new RegExp(`${RE_PER_SHARE.source}|${RE_CONTINUED.source}|reversao|juros sobre`);
const RE_EQUITY = /patrimonio liquido/;
const RE_CONTROLLING = /controlador/;
const RE_NON_CONTROLLING = /nao controlador/;

/**
 * `true` quando [a] vem depois de [b] na ordem do plano de contas.
 *
 * Comparação **segmento a segmento como número**, e não como texto: `3.9`
 * contra `3.11` daria a resposta errada em ordem lexicográfica, e o plano
 * da CVM chega a dois dígitos por nível.
 */
function isGreater(a: string, b: string): boolean {
  const partsA = a.split('.');
  const partsB = b.split('.');
  for (let i = 0; i < partsA.length && i < partsB.length; i++) {
    const numA = tryParseInt(partsA[i]!) ?? -1;
    const numB = tryParseInt(partsB[i]!) ?? -1;
    if (numA !== numB) return numA > numB;
  }
  return partsA.length > partsB.length;
}

/**
 * Um documento de demonstração já lido, com as contas resolvidas por
 * significado.
 *
 * Construa por [CvmChart.of], que detecta o layout a partir das próprias
 * linhas.
 */
export class CvmChart {
  /** Linhas do documento, como vieram. */
  readonly lines: readonly CvmAccountLine[];

  /** Layout detectado. */
  readonly layout: CvmLayout;

  private constructor(lines: readonly CvmAccountLine[], layout: CvmLayout) {
    this.lines = lines;
    this.layout = layout;
  }

  /**
   * Lê um documento e detecta o layout.
   *
   * - [lines]: linhas de **uma** demonstração de **um** exercício, já
   *   filtradas por `ORDEM_EXERC`. Misturar exercícios aqui produz resolução
   *   silenciosamente errada, porque a busca é por descrição.
   */
  static of(lines: readonly CvmAccountLine[]): CvmChart {
    return new CvmChart(Object.freeze([...lines]), CvmChart.detect(lines));
  }

  // ----------------------------------------------------------- normalização

  /**
   * Minúsculas sem acento, para comparar descrição da fonte.
   *
   * Os CSVs da CVM vêm em `latin-1` e as descrições carregam acentuação
   * inconsistente entre companhias. Comparar sem normalizar faz o mesmo
   * rótulo casar num documento e não casar no seguinte.
   */
  static normalize(s: string): string {
    let b = '';
    for (const ch of s.toLowerCase()) {
      const i = ACCENTED.indexOf(ch);
      b += i >= 0 ? PLAIN[i]! : ch;
    }
    return b.replace(/\s+/g, ' ').trim();
  }

  private static detect(lines: readonly CvmAccountLine[]): CvmLayout {
    for (const l of lines) {
      if (l.code !== '3.01') continue;
      const d = CvmChart.normalize(l.label);
      if (d.includes('intermediacao financeira')) {
        return CvmLayout.financialIntermediation;
      }
      if (d.includes('segurador') || d.includes('ressegurador')) {
        return CvmLayout.insurer;
      }
      if (d.includes('receita')) return CvmLayout.corporate;
    }
    // Sem DRE no documento — é balanço puro. O ativo e o passivo não dependem
    // de layout, então isto não impede a leitura deles.
    const hasBalanceSheet = lines.some((l) => l.code === '1' || l.code === '2');
    return hasBalanceSheet ? CvmLayout.corporate : CvmLayout.unknown;
  }

  // -------------------------------------------------------------- resolução

  /**
   * Linhas de nível até [upToLevel], que é onde o plano é padronizado.
   *
   * Abaixo do nível 2 a descrição é texto livre da companhia — a conferência
   * encontrou 26 grafias distintas de "Caixa e Equivalentes" no nível 4 — e
   * nada aqui deve descer até lá.
   */
  shallow(upToLevel = 2): CvmAccountLine[] {
    return this.lines.filter((l) => l.depth <= upToLevel);
  }

  /** A linha de código exatamente [code], se existir. */
  byCode(code: string): CvmAccountLine | null {
    for (const l of this.lines) {
      if (l.code === code) return l;
    }
    return null;
  }

  /**
   * Procura entre as linhas rasas a que casa [pattern], preferindo o **maior**
   * código.
   *
   * O maior código é o mais abaixo na demonstração, e a linha de resultado
   * que interessa é sempre a última — no layout de banco "de Intermediação",
   * tanto `3.07` ("Operações Continuadas") quanto `3.11` ("Líquido
   * Consolidado do Período") casam com "lucro", e o certo é o segundo.
   */
  private find(pattern: RegExp, options: { excluding?: RegExp; upToLevel?: number } = {}): CvmAccountLine | null {
    let best: CvmAccountLine | null = null;
    for (const l of this.shallow(options.upToLevel ?? 2)) {
      const d = CvmChart.normalize(l.label);
      if (!pattern.test(d)) continue;
      if (options.excluding !== undefined && options.excluding.test(d)) continue;
      if (best === null || isGreater(l.code, best.code)) best = l;
    }
    return best;
  }

  // ------------------------------------------------------ contas semânticas

  /** Receita do período. `3.01` em todos os layouts conferidos. */
  get revenue(): number | null {
    return this.byCode('3.01')?.value ?? null;
  }

  /**
   * Resultado antes do resultado financeiro e dos tributos — o **EBIT**.
   *
   * **`null` fora do layout corporativo, por decisão.** Banco e seguradora
   * não separam operação de financeiro, e o `3.05` deles é "Resultado Antes
   * dos Tributos" — devolvê-lo como EBIT erraria 13% no Itaú e daria à via da
   * firma um número que ela não deve receber.
   */
  get ebit(): number | null {
    if (!this.layout.hasOperatingResult) return null;
    const byDescription = this.find(RE_EBIT);
    if (byDescription !== null) return byDescription.value;
    // Recuo pelo código, conferindo que a descrição não desminta.
    const l = this.byCode('3.05');
    if (l === null) return null;
    const d = CvmChart.normalize(l.label);
    if (RE_BEFORE_TAXES.test(d) && !RE_EBIT.test(d)) return null;
    return l.value;
  }

  /** Resultado antes dos tributos sobre o lucro. */
  get incomeBeforeTaxes(): number | null {
    return this.find(RE_BEFORE_TAXES, { excluding: RE_PER_SHARE })?.value ?? null;
  }

  /**
   * Imposto de renda e contribuição social.
   *
   * O sinal é o que a CVM publica — despesa vem **negativa** —, e quem
   * consome deve preservá-lo. A `effectiveTaxRate` do motor já nega em vez de
   * modular, pela correção de 10/09/2026 registrada na §2.1-b.
   */
  get taxes(): number | null {
    return this.find(RE_TAXES, { excluding: RE_PER_SHARE })?.value ?? null;
  }

  /**
   * Lucro líquido do período.
   *
   * Procurado por descrição e não por código, e **excluindo** as linhas de
   * operações continuadas e descontinuadas, que casam com "lucro" e não são o
   * resultado final. Entre as que sobram vence o maior código, que é o fundo
   * da demonstração.
   */
  get netIncome(): number | null {
    return this.find(RE_PROFIT, { excluding: RE_NET_INCOME_EXCLUDED })?.value ?? null;
  }

  /** Lucro por ação, quando publicado. `3.99` nos quatro layouts. */
  get earningsPerShare(): number | null {
    const l = this.byCode('3.99');
    if (l === null) return null;
    return RE_PER_SHARE.test(CvmChart.normalize(l.label)) ? l.value : null;
  }

  // --- Balanço: não depende de layout, os códigos de topo são universais ---

  /**
   * Ativo total — `1`. **Existe em 100% do universo conferido**, e é o que
   * torna possível a conferência analítica que a §2.17 dizia não haver.
   */
  get totalAssets(): number | null {
    return this.byCode('1')?.value ?? null;
  }

  /** Ativo circulante — `1.01`. */
  get currentAssets(): number | null {
    return this.byCode('1.01')?.value ?? null;
  }

  /** Passivo total — `2`. */
  get totalLiabilities(): number | null {
    return this.byCode('2')?.value ?? null;
  }

  /** Passivo circulante — `2.01`. */
  get currentLiabilities(): number | null {
    return this.byCode('2.01')?.value ?? null;
  }

  /**
   * Patrimônio líquido consolidado.
   *
   * `2.03` no layout corporativo e `2.07` ou `2.08` no de banco — por isso a
   * busca é por descrição entre os três.
   */
  get equity(): number | null {
    return this.find(RE_EQUITY, { excluding: RE_CONTROLLING })?.value ?? null;
  }

  /**
   * Participação dos não controladores no patrimônio.
   *
   * `2.03.09` no layout corporativo, `2.07.02` no de banco — nível 3, que é a
   * única exceção ao limite de nível 2, e ela é segura porque a descrição
   * "não controladores" é padronizada.
   */
  get nonControllingInterests(): number | null {
    const l = this.find(RE_NON_CONTROLLING, { upToLevel: 3 });
    if (l === null) return null;
    // "Patrimônio Líquido Atribuído aos Não Controladores" e "Participação dos
    // Acionistas Não Controladores" descrevem a mesma coisa; ambas servem.
    return l.value;
  }

  // --- Nível 3 do balanço: padronizado, e conferido ------------------------
  //
  // Abaixo do nível 2 a regra geral é texto livre, e o nível 3 é a exceção
  // **medida**: sobre os 293 CNPJs do universo em 2023, cada código abaixo
  // aparece em 246 a 260 companhias com **duas ou três grafias apenas**. As
  // que faltam são banco e seguradora, cujo balanço tem outra estrutura — e
  // para elas estes campos devolvem `null`, que é o certo.

  /** Caixa e equivalentes — `1.01.01`. */
  get cash(): number | null {
    return this.level3('1.01.01', /caixa/);
  }

  /** Aplicações financeiras de curto prazo — `1.01.02`. */
  get financialInvestments(): number | null {
    return this.level3('1.01.02', /aplicaco(es|ns) financeira/);
  }

  /** Imobilizado — `1.02.03`. */
  get propertyPlantEquipment(): number | null {
    return this.level3('1.02.03', /imobilizado/);
  }

  /** Intangível — `1.02.04`. */
  get intangibleAssets(): number | null {
    return this.level3('1.02.04', /intangivel/);
  }

  /** Empréstimos e financiamentos no circulante — `2.01.04`. */
  get shortTermDebt(): number | null {
    return this.level3('2.01.04', /emprestimos e financiamentos/);
  }

  /** Empréstimos e financiamentos no não circulante — `2.02.01`. */
  get longTermDebt(): number | null {
    return this.level3('2.02.01', /emprestimos e financiamentos/);
  }

  /**
   * Lê um código de nível 3 **conferindo a descrição**.
   *
   * O código sozinho não basta: `2.01.04` é "Empréstimos e Financiamentos" na
   * estrutura corporativa e outra coisa na de banco. Discordando o rótulo, a
   * resposta é `null` — a mesma disciplina do [ebit].
   */
  private level3(code: string, expected: RegExp): number | null {
    const l = this.byCode(code);
    if (l === null) return null;
    return expected.test(CvmChart.normalize(l.label)) ? l.value : null;
  }

  // --- Fluxo de caixa: códigos de topo universais no método indireto ---

  /** Caixa líquido das atividades operacionais — `6.01`. */
  get operatingCashFlow(): number | null {
    return this.byCode('6.01')?.value ?? null;
  }

  /** Caixa líquido das atividades de investimento — `6.02`. */
  get investingCashFlow(): number | null {
    return this.byCode('6.02')?.value ?? null;
  }

  /**
   * Depreciação e amortização, da reconciliação do fluxo operacional.
   *
   * `6.01.01.*` traz os ajustes que reconciliam lucro e caixa, e a
   * depreciação está entre eles — em texto livre, como o CapEx. Soma todas as
   * linhas que a mencionem, em centavos inteiros.
   *
   * Devolve `null` quando nenhuma casa: o motor deriva D&A de
   * `EBITDA − EBIT` quando isto falta, e um zero aqui apagaria essa rota.
   */
  get depreciationAndAmortization(): number | null {
    let cents = 0;
    let found = false;
    for (const l of this.lines) {
      if (!l.code.startsWith('6.01.')) continue;
      const d = CvmChart.normalize(l.label);
      if (!d.includes('deprecia') && !d.includes('amortiza')) continue;
      cents += l.cents;
      found = true;
    }
    // A reconciliação soma a despesa de volta ao lucro, então ela vem
    // **positiva**. O domínio a quer positiva também.
    return found ? Math.abs(cents) / 100.0 : null;
  }

  /**
   * Aquisição de imobilizado e intangível, somada — o **CapEx**.
   *
   * **Aproximação declarada, e é a única parte desta classe que depende de
   * texto livre.** A conferência achou a linha em 86% das companhias, com
   * mais de oito grafias ("Aquisição de intangível", "Adições ao imobilizado
   * e intangível", "Aquisição de ativo imobilizado"...). Soma todas as linhas
   * de nível 3 sob `6.02` que mencionem imobilizado ou intangível.
   *
   * Devolve `null` — e não zero — quando nenhuma linha casa: ausência de
   * linha não é ausência de investimento, é ausência de dado.
   */
  get capex(): number | null {
    // **Soma os centavos inteiros da própria linha**, sem passar por reais:
    // acumular ponto flutuante deixaria resíduo que reaparece na taxa de
    // reinvestimento, e a linha já guarda o inteiro exato vindo do texto.
    let cents = 0;
    let found = false;
    for (const l of this.lines) {
      if (!l.code.startsWith('6.02.') || l.depth !== 3) continue;
      const d = CvmChart.normalize(l.label);
      if (!d.includes('imobiliz') && !d.includes('intangivel')) continue;
      cents += l.cents;
      found = true;
    }
    return found ? cents / 100.0 : null;
  }
}
