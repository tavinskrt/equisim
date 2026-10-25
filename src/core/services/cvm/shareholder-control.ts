/** A espécie do controle acionário, do Formulário Cadastral da CVM (item B46). */

import { DartEnum } from '../../lang/dart-enum';
import { DateTime } from '../../lang/date-time';
import { asString, isJsonObject, type JsonObject } from '../../lang/json';
import { compareStr } from '../../lang/num';

/**
 * Quem controla a companhia, como ela declara no Formulário Cadastral.
 *
 * O FCA traz, todo ano, a coluna `Especie_Controle_Acionario`: "Estatal",
 * "Estatal Holding", "Privado", "Privado Holding", "Estrangeiro" ou
 * "Estrangeiro Holding". A holding é a mesma espécie de controle, exercida por
 * meio de outra companhia — a Petrobras declara "Estatal Holding" —, e por isso
 * não muda a classe.
 */
export class ShareholderControl extends DartEnum {
  /** Controle de um ente público: União, estado ou município. */
  static readonly state = new ShareholderControl('state', 0);

  /** Controle privado nacional. */
  static readonly private = new ShareholderControl('private', 1);

  /** Controle privado estrangeiro. */
  static readonly foreign = new ShareholderControl('foreign', 2);

  static readonly values: readonly ShareholderControl[] = [
    ShareholderControl.state,
    ShareholderControl.private,
    ShareholderControl.foreign,
  ];

  protected get typeName(): string {
    return 'ShareholderControl';
  }

  /** A classe do texto do FCA, ou `null` quando ele não diz. */
  static fromFca(text: string): ShareholderControl | null {
    const t = text.trim().toLowerCase();
    if (t.startsWith('estatal')) return ShareholderControl.state;
    if (t.startsWith('privad')) return ShareholderControl.private;
    if (t.startsWith('estrangeir')) return ShareholderControl.foreign;
    return null;
  }
}

/** Um trecho do histórico: a espécie de controle valendo desde [since]. */
export class ShareholderControlPeriod {
  /** Primeiro dia em que a espécie vale. */
  readonly since: DateTime;

  /** A espécie. */
  readonly control: ShareholderControl;

  constructor(args: { since: DateTime; control: ShareholderControl }) {
    this.since = args.since;
    this.control = args.control;
  }
}

/** Uma linha do FCA, como a ferramenta a lê. */
export interface ShareholderControlFiling {
  readonly reference: DateTime;
  readonly species: string;
  readonly speciesDate: DateTime | null;
}

/** Pacote lido por [ShareholderControlHistory.decode]. */
export interface ShareholderControlPackage {
  readonly generatedAt: DateTime;
  readonly byIssuer: Map<string, ShareholderControlPeriod[]>;
}

/**
 * O dia civil de [d], à meia-noite em UTC: a data do formulário não tem
 * hora, e o fuso da máquina não pode movê-la.
 */
function utcDay(d: DateTime): DateTime {
  return DateTime.utc(d.year, d.month, d.day);
}

function day(d: DateTime): string {
  return utcDay(d).toIso8601String().substring(0, 10);
}

/** O histórico do controle, montado das linhas do FCA, e o pacote. */
export const ShareholderControlHistory = {
  /** Versão do formato do pacote. */
  version: 1,

  /**
   * O histórico de uma companhia, a partir das linhas do FCA de todos os anos.
   *
   * **A data da mudança.** O formulário é anual, com data de referência no
   * primeiro dia do ano, e a privatização acontece no meio dele. A coluna
   * `Data_Especie_Controle_Acionario` deveria dar o dia, mas vem em branco,
   * com a data da fundação ou com a do evento conforme a companhia e o ano: a
   * Eletrobras declara 28/01/1971 nos formulários de 2022 a 2024 e 17/06/2022
   * nos de 2025 e 2026. Por isso, para cada mudança entre o formulário de um
   * ano e o do seguinte, vale a primeira data declarada **pela espécie nova**,
   * em qualquer formulário, que caia entre a referência do último formulário
   * da espécie antiga e um ano depois da do primeiro da nova. Sem data
   * plausível, a mudança vale da referência do primeiro formulário da espécie
   * nova, 1º de janeiro — o que pode adiantá-la ou atrasá-la em meses: a
   * CEEE-D, privatizada em julho de 2021, muda em 01/01/2022.
   *
   * Linhas sem espécie legível são ignoradas. Devolve lista vazia quando não
   * sobra nenhuma.
   */
  fromFilings(filings: readonly ShareholderControlFiling[]): ShareholderControlPeriod[] {
    const rows: { reference: DateTime; control: ShareholderControl; speciesDate: DateTime | null }[] = [];
    for (const f of filings) {
      const c = ShareholderControl.fromFca(f.species);
      if (c === null) continue;
      rows.push({
        reference: utcDay(f.reference),
        control: c,
        speciesDate: f.speciesDate === null ? null : utcDay(f.speciesDate),
      });
    }
    rows.sort((a, b) => a.reference.compareTo(b.reference));
    if (rows.length === 0) return [];
    const periods: ShareholderControlPeriod[] = [
      new ShareholderControlPeriod({ since: rows[0]!.reference, control: rows[0]!.control }),
    ];
    for (let i = 1; i < rows.length; i++) {
      const before = rows[i - 1]!;
      const now = rows[i]!;
      if (now.control === before.control) continue;
      // Um ano de calendário depois, e não 366 dias corridos.
      const ref = now.reference;
      const until = DateTime.utc(ref.year + 1, ref.month, ref.day);
      const candidates: DateTime[] = [];
      for (const l of rows) {
        if (l.control === now.control && l.speciesDate !== null) {
          if (!l.speciesDate.isBefore(before.reference) && !l.speciesDate.isAfter(until)) {
            candidates.push(l.speciesDate);
          }
        }
      }
      candidates.sort((a, b) => a.compareTo(b));
      periods.push(
        new ShareholderControlPeriod({
          since: candidates.length === 0 ? now.reference : candidates[0]!,
          control: now.control,
        }),
      );
    }
    return periods;
  },

  /**
   * A espécie de controle no dia de [asOf], ou `null` antes do primeiro
   * trecho. A comparação é por dia civil, em UTC, como as datas do histórico.
   */
  at(periods: readonly ShareholderControlPeriod[], asOf: DateTime): ShareholderControl | null {
    const d = utcDay(asOf);
    let current: ShareholderControl | null = null;
    for (const p of periods) {
      if (utcDay(p.since).isAfter(d)) break;
      current = p.control;
    }
    return current;
  },

  /**
   * O pacote: o histórico de cada emissor, pela raiz do código de
   * negociação — a mesma chave do registro da B3.
   */
  encode(byIssuer: ReadonlyMap<string, readonly ShareholderControlPeriod[]>, args: { generatedAt: DateTime }): JsonObject {
    const issuers: JsonObject = {};
    for (const e of [...byIssuer.keys()].sort(compareStr)) {
      issuers[e] = byIssuer.get(e)!.map((p) => ({ desde: day(p.since), controle: p.control.name }));
    }
    return {
      versao: ShareholderControlHistory.version,
      geradoEm: day(args.generatedAt),
      fonte: 'Formulário Cadastral da CVM, Especie_Controle_Acionario',
      emissores: issuers,
    };
  },

  /** Lê o pacote; `null` quando a versão ou a forma não são as esperadas. */
  decode(json: JsonObject): ShareholderControlPackage | null {
    if (json['versao'] !== ShareholderControlHistory.version) return null;
    const parsed = DateTime.tryParse(asString(json['geradoEm']) ?? '');
    const generated = parsed === null ? null : utcDay(parsed);
    const issuers = json['emissores'];
    if (generated === null || !isJsonObject(issuers)) return null;
    const output = new Map<string, ShareholderControlPeriod[]>();
    for (const [key, list] of Object.entries(issuers)) {
      if (!Array.isArray(list)) return null;
      const periods: ShareholderControlPeriod[] = [];
      for (const p of list) {
        if (!isJsonObject(p)) return null;
        const readOrdering = DateTime.tryParse(asString(p['desde']) ?? '');
        const since = readOrdering === null ? null : utcDay(readOrdering);
        const control = ShareholderControl.values.find((c) => c.name === p['controle']) ?? null;
        if (since === null || control === null) return null;
        periods.push(new ShareholderControlPeriod({ since, control }));
      }
      periods.sort((a, b) => a.since.compareTo(b.since));
      output.set(key, periods);
    }
    return { generatedAt: generated, byIssuer: output };
  },
};
