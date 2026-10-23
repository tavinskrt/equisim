/**
 * O que muda o capital de uma companhia **depois** do balanço, e como o
 * aplicativo o recebe (itens B28 e B29).
 *
 * Duas listas por ativo, e as duas saem do Formulário de Referência da CVM,
 * conferidas contra o COTAHIST:
 *
 * - **emissões por valor** ([ShareIssue]): o capital que entrou e não está no
 *   último balanço — a cascata o soma ao patrimônio da ponte;
 * - **eventos de ações** ([ShareEvent]): desdobramento, grupamento e
 *   bonificação, com a data ex — o preparo completa com eles o ajuste que a
 *   fonte de preços deixou de fazer.
 */

import { ShareIssue } from '../../entities/share-issue';
import { DateTime } from '../../lang/date-time';
import { isJsonObject, type JsonObject } from '../../lang/json';
import { compareStr, isInt, round, roundToDouble } from '../../lang/num';
import { Money } from '../../value-objects/money';
import { ShareEvent } from '../b3/corporate-events';

/** Emissões e eventos de ações de um ativo. */
export class CapitalEvents {
  /** Emissões por valor, em ordem de data. */
  readonly issues: readonly ShareIssue[];

  /** Eventos de ações, em ordem de data ex. */
  readonly shareEvents: readonly ShareEvent[];

  /** Declara as duas listas. */
  constructor(args: { issues?: readonly ShareIssue[]; shareEvents?: readonly ShareEvent[] } = {}) {
    this.issues = args.issues ?? [];
    this.shareEvents = args.shareEvents ?? [];
  }

  /** Nenhuma das duas listas tem entrada. */
  get isEmpty(): boolean {
    return this.issues.length === 0 && this.shareEvents.length === 0;
  }
}

/** Lê e grava o pacote de eventos de capital. */
export const CapitalEventsCodec = {
  /**
   * Versão do formato do pacote. A 2 grava o valor da emissão em centavos
   * inteiros, e não em reais.
   */
  version: 2,

  /** Grava o pacote. */
  encodePackage(byTicker: ReadonlyMap<string, CapitalEvents>, args: { generatedAt: DateTime }): JsonObject {
    const day = (d: DateTime): string => d.toIso8601String().substring(0, 10);
    const assets: JsonObject = {};
    const entries = [...byTicker.entries()].sort((a, b) => compareStr(a[0], b[0]));
    for (const [key, value] of entries) {
      if (value.isEmpty) continue;
      assets[key] = {
        emissoes: [...value.issues]
          .sort((a, b) => a.date.compareTo(b.date))
          .map((i) => {
            const issue: JsonObject = { data: day(i.date), centavos: i.amount.cents, acoes: i.shares };
            if (!i.declared) issue['declarada'] = false;
            return issue;
          }),
        eventos: [...value.shareEvents]
          .sort((a, b) => a.exDate.compareTo(b.exDate))
          .map((v) => ({ dataEx: day(v.exDate), fator: v.factor })),
      };
    }
    return {
      versao: CapitalEventsCodec.version,
      geradoEm: day(args.generatedAt),
      ativos: assets,
    };
  },

  /**
   * Lê o pacote. Entrada malformada é **pulada**, e não derruba a leitura: um
   * ativo sem emissão lida é avaliado com o patrimônio do balanço, que é o
   * comportamento anterior.
   */
  decodePackage(pkg: JsonObject): Map<string, CapitalEvents> {
    const out = new Map<string, CapitalEvents>();
    const assets = pkg['ativos'];
    if (!isJsonObject(assets)) return out;
    const date = (x: unknown): DateTime | null => (typeof x === 'string' ? DateTime.tryParse(x) : null);
    const number = (x: unknown): number | null => (typeof x === 'number' ? x : null);
    // Quantidade de ação é inteira: fração na fonte é entrada malformada.
    const whole = (x: unknown): number | null =>
      isInt(x)
        ? x
        : typeof x === 'number' && Number.isFinite(x) && Math.abs(x - roundToDouble(x)) < 1e-9
          ? round(x)
          : null;
    for (const [key, v] of Object.entries(assets)) {
      if (!isJsonObject(v)) continue;
      const issuances: ShareIssue[] = [];
      const list = v['emissoes'];
      if (Array.isArray(list)) {
        for (const x of list) {
          if (!isJsonObject(x)) continue;
          const d = date(x['data']);
          const cents = x['centavos'];
          const shares = whole(x['acoes']);
          if (d === null || !isInt(cents) || shares === null) continue;
          const i = new ShareIssue({
            date: d,
            amount: new Money(cents),
            shares,
            declared: x['declarada'] !== false,
          });
          if (i.isUsable) issuances.push(i);
        }
      }
      const events: ShareEvent[] = [];
      const eventList = v['eventos'];
      if (Array.isArray(eventList)) {
        for (const x of eventList) {
          if (!isJsonObject(x)) continue;
          const d = date(x['dataEx']);
          const f = number(x['fator']);
          if (d === null || f === null || !Number.isFinite(f) || f <= 0) continue;
          events.push(new ShareEvent({ exDate: d, factor: f, observedRatio: 1 / f }));
        }
      }
      const c = new CapitalEvents({ issues: issuances, shareEvents: events });
      if (!c.isEmpty) out.set(key, c);
    }
    return out;
  },
};
