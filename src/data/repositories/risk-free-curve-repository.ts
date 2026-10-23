import { DateTime, TreasuryCurve, type TreasuryQuote, TreasuryQuotesCodec, type YieldCurve } from '../../core';
import type { TreasuryDatasource } from '../datasources/treasury-datasource';
import { formatDay } from './cvm-fundamentals-repository';
import { memoizedPackage, type PackageLoader } from './package-loader';

/**
 * O que a avaliação recebe da curva: ela, ou a razão de não haver.
 *
 * [note] só existe quando [curve] é `null`: com curva, a própria avaliação já
 * declara a data-base que usou.
 */
export interface CurveReading {
  readonly curve: YieldCurve | null;
  readonly note: string | null;
}

/**
 * A curva de juros da avaliação de hoje (item A2.1, decisões 84 e 86).
 *
 * **A curva é o padrão do aplicativo**, por decisão do usuário: com ela, a
 * taxa de cada ano da projeção é o forward da curva dos prefixados, e a da
 * perpetuidade é o forward depois da projeção. Sem ela, a cascata recua para
 * os dois pontos do CDI e diz isso no aviso.
 *
 * **De onde vem, em ordem:** nas ferramentas do Node, o Tesouro lido no dia;
 * e, sem ele, o pacote gerado no build. **Na web, só o pacote** — o navegador
 * não lê o arquivo do Tesouro. Nos dois casos a regra de data é a de
 * `TreasuryCurve.at`: data-base de até sete dias antes da avaliação, e nunca
 * depois dela. Um pacote velho **não** vira curva — vira recuo declarado.
 */
export class RiskFreeCurveRepository {
  /** Fonte do dia, ou `null` onde ela não alcança o Tesouro: a web. */
  readonly remote: TreasuryDatasource | null;

  private readonly packaged: () => Promise<TreasuryQuote[]>;
  private dailyQuotes: Promise<TreasuryQuote[]> | null = null;
  private fetchDay: DateTime | null = null;

  constructor(args: { remote: TreasuryDatasource | null; loadPackage: PackageLoader }) {
    this.remote = args.remote;
    this.packaged = memoizedPackage(args.loadPackage, (json) => TreasuryQuotesCodec.decode(json), []);
  }

  /**
   * Curva para [asOf] e, quando não há, a ressalva que diz por quê.
   *
   * A busca do dia vale **pelo dia da avaliação**: o aplicativo aberto de
   * um dia para o outro busca de novo, em vez de envelhecer a curva até o
   * recuo.
   */
  async readAt(asOf: DateTime): Promise<CurveReading> {
    const source = this.remote;
    if (source !== null) {
      const day = DateTime.utc(asOf.year, asOf.month, asOf.day);
      if (this.fetchDay === null || !this.fetchDay.equals(day)) {
        this.fetchDay = day;
        this.dailyQuotes = null;
      }
      const remoteReading = TreasuryCurve.at(await (this.dailyQuotes ??= this.fetchToday(source)), asOf);
      if (remoteReading !== null) return { curve: remoteReading, note: null };
    }
    const pkg = await this.packaged();
    const packagedCurve = TreasuryCurve.at(pkg, asOf);
    if (packagedCurve !== null) return { curve: packagedCurve, note: null };
    return { curve: null, note: RiskFreeCurveRepository.caveat(pkg, { noDailySource: source === null }) };
  }

  private async fetchToday(source: TreasuryDatasource): Promise<TreasuryQuote[]> {
    const r = await source.latest();
    // Falha da busca não é guardada para a sessão inteira: a próxima avaliação
    // tenta de novo. Só o sucesso fica.
    if (r.isErr) {
      this.dailyQuotes = null;
      return [];
    }
    return r.unwrap();
  }

  static caveat(pkg: readonly TreasuryQuote[], options: { noDailySource: boolean }): string {
    const origin = options.noDailySource
      ? 'Na web, a curva do Tesouro vem só do pacote do build'
      : `O Tesouro não trouxe hoje curva de até ${TreasuryCurve.fallbackDays} dias, e o recuo é o pacote do build`;
    const latest =
      pkg.length === 0
        ? null
        : pkg.map((q) => q.baseDate).reduce((a, b) => (a.isAfter(b) ? a : b));
    const status =
      latest === null
        ? 'que este build não trouxe ou não pôde ser lido'
        : `cuja data-base mais recente, ${formatDay(latest)}, está fora dos ` +
          `${TreasuryCurve.fallbackDays} dias que a curva aceita`;
    const remedy = options.noDailySource ? ' Um build novo, com o pacote regerado, traz a curva de volta.' : '';
    return `${origin}, ${status}. A taxa livre de risco recuou para os dois pontos do CDI.${remedy}`;
  }
}
