/** Quais negócios operam sob contrato de prazo determinado. */

import { CyclicalSectors } from './cyclical-sectors';

/**
 * Setores cujo direito de operar tem data para acabar.
 *
 * **Por que existe.** O valor terminal do motor é perpétuo para todo ativo.
 * Numa concessão — transmissão, distribuição, saneamento, rodovia, ferrovia,
 * aeroporto — o direito de operar acaba em data marcada, e o ativo reverte ao
 * poder concedente ou vai a nova licitação.
 *
 * **O que isto NÃO faz.** Não trunca a perpetuidade, porque **o prazo não é
 * publicado**. Medido em 10/09/2026: a razão
 * `(imobilizado + intangível) ÷ D&A` parecia servir de estimador do prazo
 * remanescente e não serve — ela dá 6,3 anos para a TAEE11, cujas concessões
 * vão a 2042, e 14,3 anos para a WEGE3, que não tem concessão alguma. O que
 * ela mede é giro da base de ativos. Ver `docs/validacao/concessao.md`.
 *
 * **O que isto faz.** Bloqueia a afirmação que o contrato nega diretamente: a
 * de que o **retorno excedente sobrevive para sempre**. Uma concessão é
 * relicitada, e a tarifa é fixada para remunerar o capital ao custo dele —
 * não acima. O terminal neutro da decisão 25, `ROIC_∞ = WACC`, é exatamente o
 * modelo certo para esse negócio, e a exceção de vantagem competitiva é
 * exatamente o errado.
 *
 * A lista é **declarada, não inferida**, pela mesma razão que a de
 * [CyclicalSectors]: quem tem concessão é fato do contrato, não do dado.
 */
export const ConcessionSectors = {
  /** Chaves de setor cujo conteúdo inteiro opera sob concessão. */
  sectorKeys: ['saneamento', 'infraestrutura'] as readonly string[],

  /**
   * Termos de subsetor que denunciam contrato de prazo determinado.
   *
   * A comparação é sobre o subsetor **normalizado**, sem acento e sem
   * pontuação, pela mesma razão que em [CyclicalSectors]: a fonte publica
   * variantes do mesmo rótulo.
   *
   * `energia eletrica` cobre geração, transmissão, distribuição e
   * comercialização, e as quatro dependem de outorga — a comercializadora
   * pura seria a exceção, e o universo não tem nenhuma isolada.
   */
  industryTerms: [
    'energia eletrica',
    'agua e saneamento',
    'exploracao de rodovias',
    'transporte ferroviario',
    'aeroportu',
    'concessao',
  ] as readonly string[],

  /**
   * `true` quando o direito de operar tem prazo.
   *
   * - [sectorKey]: chave setorial da fonte, já em minúsculas.
   * - [industry]: subsetor da fonte, com acentuação e pontuação originais.
   */
  hasFiniteTerm(args: { sectorKey?: string | null; industry?: string | null } = {}): boolean {
    const key = CyclicalSectors.normalize(args.sectorKey);
    for (const k of ConcessionSectors.sectorKeys) {
      if (key === CyclicalSectors.normalize(k)) return true;
    }
    const sub = CyclicalSectors.normalize(args.industry);
    if (sub.length === 0) return false;
    for (const term of ConcessionSectors.industryTerms) {
      if (sub.includes(term)) return true;
    }
    return false;
  },
};
