/**
 * A ponte entre o ticker negociado e o CNPJ que arquiva na CVM.
 *
 * **Por que ela não é trivial.** A CVM identifica companhia por CNPJ; a bolsa,
 * por ticker. O FCA publica `Codigo_Negociacao`, que **parece** ser a ponte e
 * não é: conferido em 11/09/2026 sobre 1.023 linhas do FCA 2024, **44% vêm em
 * branco**, e o resto traz código CVM (`25585` na CSN Mineração), zeros
 * (`000000` no BTG) ou a string `ADR` (Marfrig).
 *
 * A resolução usa cinco regras, em ordem, e **para na primeira que
 * responde**:
 *
 * 0. **O registro oficial da B3**, quando há: o emissor de quatro letras traz
 *    o código CVM, e o código CVM leva ao CNPJ pelos metadados das
 *    demonstrações (decisão 82). É declarado, e não inferido — e é o único que
 *    acompanha fusão: em 14/09/2026 ele corrigiu `MBRF3`, que as regras abaixo
 *    ligavam à BRF por causa do nome "BRF S.A." na fonte de preços, quando a
 *    MBRF é a Marfrig; e `AUAU3`, ligado à Petz pelo nome "Pet Center" em vez
 *    da União Pet.
 * 1. `Codigo_Negociacao` com **formato de ticker**, sobre todos os anos de
 *    FCA disponíveis. Sete anos dão 644 códigos e **zero ambiguidade**.
 * 2. Propagação pela **raiz de quatro letras**, quando ela aponta para um
 *    CNPJ único — é o que resolve a classe que a companhia não declarou.
 * 3. Nome **idêntico** após normalização.
 * 4. [overrides], a tabela declarada abaixo.
 *
 * **Casamento aproximado de nome está proibido, e a razão está medida.** Com
 * corte de similaridade em 0,62, `CSNA3` — cujo nome na fonte de preços é só
 * "CSN" — casa com **COSAN S.A.** a 0,75: confiante e errado. Uma ponte errada
 * não falha, ela avalia a empresa trocada.
 *
 * Ver `docs/validacao/cvm_conferencia.md §2`.
 */

const ACCENTED = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
const PLAIN = 'aaaaaeeeeiiiiooooouuuucn';
const PUNCTUATION = ['.', ',', '-', '/'] as const;
const CORPORATE_TERMS = [
  ' s a ',
  ' sa ',
  ' participacoes ',
  ' part ',
  ' holding ',
  ' cia ',
  ' companhia ',
  ' bco ',
  ' banco ',
] as const;

/** Resolve ticker para CNPJ. */
export const CvmBridge = {
  /**
   * Um código só é candidato a ticker se tiver a forma da B3.
   *
   * É este filtro que descarta `25585`, `000000` e `ADR` sem precisar
   * enumerá-los.
   *
   * **A raiz admite dígito depois da primeira posição**, e não admiti-lo foi
   * defeito: `B3SA3` — a própria B3 — tem raiz `B3SA`. A primeira versão
   * exigia `[A-Z]{4}` e descartava a bolsa como se fosse lixo de
   * preenchimento. O que separa ticker de código CVM é **começar por letra**,
   * não ser todo de letras.
   */
  tickerFormat: /^[A-Z][A-Z0-9]{3}[0-9]{1,2}$/,

  /** `true` quando [code] tem forma de ticker negociável. */
  looksLikeTicker(code: string): boolean {
    return CvmBridge.tickerFormat.test(code.trim().toUpperCase());
  },

  /**
   * Raiz de quatro letras — as classes de uma mesma companhia a compartilham.
   *
   * Devolve `null` para código que não tenha a forma esperada, em vez de
   * recortar às cegas: `substring(0, 4)` sobre uma entrada curta lança, e
   * sobre uma entrada estranha inventa uma raiz que casaria com outra coisa.
   */
  root(ticker: string): string | null {
    const t = ticker.trim().toUpperCase();
    return CvmBridge.tickerFormat.test(t) ? t.substring(0, 4) : null;
  },

  /**
   * Nome em minúsculas, sem acento e sem os sufixos societários que a CVM e a
   * fonte de preços grafam de formas diferentes.
   *
   * Serve **apenas** para igualdade exata. Não use para similaridade.
   */
  normalizeName(name: string): string {
    let b = '';
    for (const ch of name.toLowerCase()) {
      const i = ACCENTED.indexOf(ch);
      b += i >= 0 ? PLAIN[i]! : ch;
    }
    // Cerca com espaço antes de remover os termos: sem isso ` cia ` não casa
    // em "CIA SIDERURGICA NACIONAL", que começa por ele, e o nome sai
    // diferente do mesmo nome escrito com prefixo.
    let s = ` ${b} `;
    for (const p of PUNCTUATION) {
      s = s.replaceAll(p, ' ');
    }
    s = s.replace(/\s+/g, ' ');
    for (const term of CORPORATE_TERMS) {
      while (s.includes(term)) {
        s = s.replaceAll(term, ' ');
      }
    }
    return s.replace(/\s+/g, ' ').trim();
  },

  /**
   * Tabela declarada, para o que as três regras automáticas não alcançam.
   *
   * **Cada entrada é uma afirmação verificada contra o `DENOM_CIA` da CVM**,
   * não um palpite. Companhias grandes caem aqui porque nunca preencheram o
   * `Codigo_Negociacao` com o ticker — o BTG grafa `000000` e a B3 não grafa
   * nada.
   */
  overrides: new Map<string, string>([
    // Nunca declararam o código no FCA.
    ['B3SA3', '09.346.601/0001-25'], // B3 S.A. - BRASIL, BOLSA, BALCÃO
    ['CSNA3', '33.042.730/0001-04'], // CIA SIDERURGICA NACIONAL
    ['BPAC3', '30.306.294/0001-45'], // BCO BTG PACTUAL S.A.
    ['BPAC5', '30.306.294/0001-45'],
    ['BPAC11', '30.306.294/0001-45'],
    ['B1003', '52.270.350/0001-71'], // B100 S.A.
    ['CTAX3', '04.032.433/0001-80'], // CONTAX PARTICIPAÇÕES — em recuperação
    ['NORD3', '60.884.319/0001-59'], // NORDON INDUSTRIAS METALURGICAS
    ['HAGA3', '30.540.991/0001-66'], // HAGA S.A. INDUSTRIA E COMERCIO
    ['HAGA4', '30.540.991/0001-66'],
  ]) as ReadonlyMap<string, string>,

  /**
   * Tickers cuja companhia **não foi encontrada** nos arquivos de 2024, e que
   * por isso ficam sem ponte até que a carga histórica os alcance.
   *
   * Estão aqui **nomeados** em vez de silenciosamente ausentes, porque uma
   * lacuna declarada é dívida e uma lacuna silenciosa é defeito.
   *
   * - `FASA3`, `LUXM4`, `OBTC3`: sem companhia correspondente em 2024;
   *   provável deslistagem ou mudança de razão social. A carga de todos os
   *   anos (A1.6) deve alcançá-los.
   * - `MAPT3`: o nome na fonte de preços é "CIA MARCOPOLO", que casa com
   *   `MARCOPOLO S.A.` — **mas a Marcopolo negocia como POMO3 e POMO4**. É o
   *   mesmo formato de engano do `CSNA3`/`COSAN`, e por isso fica sem ponte
   *   em vez de receber a errada.
   */
  withoutBridge: new Set<string>(['FASA3', 'LUXM4', 'OBTC3', 'MAPT3']) as ReadonlySet<string>,

  /**
   * Resolve o CNPJ de [ticker].
   *
   * - [byCode]: mapa ticker → CNPJ construído do FCA, já filtrado por
   *   [looksLikeTicker] e já conferido como não ambíguo.
   * - [byName]: mapa nome normalizado → CNPJ, do `DENOM_CIA` da CVM.
   * - [assetName]: nome do ativo na fonte de preços, para a regra 3.
   * - [byOfficialRegistry]: raiz de quatro letras → CNPJ, do registro da B3
   *   cruzado com o código CVM das demonstrações. Regra 0.
   *
   * Devolve `null` quando nenhuma regra responde — e isso é resposta, não
   * falha.
   */
  resolver(
    ticker: string,
    args: {
      byCode: ReadonlyMap<string, string>;
      byName?: ReadonlyMap<string, string>;
      assetName?: string | null;
      byOfficialRegistry?: ReadonlyMap<string, string>;
    },
  ): string | null {
    const byName = args.byName ?? new Map<string, string>();
    const byOfficialRegistry = args.byOfficialRegistry ?? new Map<string, string>();
    const t = ticker.trim().toUpperCase();

    // O veto vem **antes** de tudo, e é o que [withoutBridge] significa.
    // Deixá-lo como comentário não bastou: o `MAPT3` foi resolvido para a
    // Marcopolo pela regra de nome, ao lado de `POMO3` e `POMO4`, que é o
    // engano que a própria lista existia para impedir.
    if (CvmBridge.withoutBridge.has(t)) return null;

    // Regra 0: o registro da B3, por emissor. Declarado vence inferido.
    const r0 = CvmBridge.root(t);
    const official = r0 === null ? undefined : byOfficialRegistry.get(r0);
    if (official !== undefined) return official;

    const direct = args.byCode.get(t);
    if (direct !== undefined) return direct;

    const r = CvmBridge.root(t);
    if (r !== null) {
      const ofRoot = new Set<string>();
      for (const [key, value] of args.byCode) {
        if (key.startsWith(r) && CvmBridge.root(key) === r) ofRoot.add(value);
      }
      if (ofRoot.size === 1) return ofRoot.values().next().value!;
    }

    if (args.assetName !== undefined && args.assetName !== null) {
      const exactMatch = byName.get(CvmBridge.normalizeName(args.assetName));
      if (exactMatch !== undefined) return exactMatch;
    }

    return CvmBridge.overrides.get(t) ?? null;
  },

  /**
   * Resolve o universo inteiro, **propagando a raiz depois** de todas as
   * outras regras.
   *
   * A propagação tardia é o que resolve `AXIA7` e `EQPA5`: nenhum dos dois é
   * alcançado pelas regras diretas, mas `AXIA3` e `EQPA3` são — pelo nome —, e
   * classes da mesma raiz são a mesma companhia. Propagar **antes** não
   * funcionaria, porque na primeira passada a raiz ainda não tem nenhum
   * membro resolvido.
   *
   * - [tickers]: universo a resolver.
   * - [names]: nome de cada ativo na fonte de preços, quando houver.
   */
  resolveUniverse(
    tickers: Iterable<string>,
    args: {
      byCode: ReadonlyMap<string, string>;
      byName?: ReadonlyMap<string, string>;
      names?: ReadonlyMap<string, string>;
      byOfficialRegistry?: ReadonlyMap<string, string>;
    },
  ): Map<string, string> {
    const list = [...tickers];
    const names = args.names ?? new Map<string, string>();
    const out = new Map<string, string>();
    for (const t of list) {
      const c = CvmBridge.resolver(t, {
        byCode: args.byCode,
        byName: args.byName ?? new Map<string, string>(),
        assetName: names.get(t) ?? null,
        byOfficialRegistry: args.byOfficialRegistry ?? new Map<string, string>(),
      });
      if (c !== null) out.set(t.trim().toUpperCase(), c);
    }

    // Segunda passada: quem ficou de fora herda o CNPJ da própria raiz, se ela
    // for unânime entre os já resolvidos.
    const byRoot = new Map<string, Set<string>>();
    for (const [key, value] of out) {
      const r = CvmBridge.root(key);
      if (r !== null) {
        let set = byRoot.get(r);
        if (set === undefined) {
          set = new Set<string>();
          byRoot.set(r, set);
        }
        set.add(value);
      }
    }
    for (const t of list) {
      const k = t.trim().toUpperCase();
      if (out.has(k)) continue;
      if (CvmBridge.withoutBridge.has(k)) continue;
      const r = CvmBridge.root(k);
      if (r === null) continue;
      const c = byRoot.get(r);
      if (c !== undefined && c.size === 1) out.set(k, c.values().next().value!);
    }
    return out;
  },

  /**
   * Companhias alcançadas por tickers de **raízes diferentes**.
   *
   * **É a regra geral que o veto de [withoutBridge] resolve caso a caso.** As
   * classes de uma companhia compartilham a raiz — `POMO3` e `POMO4` são a
   * Marcopolo. Quando um CNPJ recebe `POMO` **e** `MAPT`, uma das duas pontes
   * está errada, e nenhuma medição interna diz qual.
   *
   * Não remove nada por conta própria: uma companhia pode legitimamente ter
   * mudado de raiz — a Natura virou `NTCO` — e apagar o histórico seria pior.
   * Devolve o conflito para quem carrega decidir, e para o relatório mostrar.
   *
   * Devolve CNPJ → conjunto de raízes, apenas onde há mais de uma.
   */
  rootConflicts(bridge: ReadonlyMap<string, string>): Map<string, Set<string>> {
    const byCnpj = new Map<string, Set<string>>();
    for (const [key, value] of bridge) {
      const r = CvmBridge.root(key);
      if (r !== null) {
        let set = byCnpj.get(value);
        if (set === undefined) {
          set = new Set<string>();
          byCnpj.set(value, set);
        }
        set.add(r);
      }
    }
    const out = new Map<string, Set<string>>();
    for (const [key, value] of byCnpj) {
      if (value.size > 1) out.set(key, value);
    }
    return out;
  },
};
