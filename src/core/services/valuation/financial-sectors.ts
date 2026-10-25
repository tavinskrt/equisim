/** Quem é instituição financeira, para a Porta 1. */

import { CyclicalSectors } from './cyclical-sectors';

/**
 * Setores cujo passivo oneroso é insumo do negócio, e não financiamento.
 *
 * **A lista é declarada, não inferida**, como a de [CyclicalSectors]. Aceita
 * as duas taxonomias que chegam ao motor:
 *
 * - a **oficial da B3** (item A5, decisão 87): setor `Financeiro` e um dos
 *   subsetores de [officialSubsectors];
 * - a da **fonte de preços**, que ainda é o recuo quando a B3 não classifica o
 *   emissor: a chave [sourceKey].
 *
 * **O setor `Financeiro` inteiro não serve.** A B3 põe nele a exploração de
 * imóveis — shopping centers como ALOS3 e MULT3, cujo passivo é financiamento
 * de verdade — e as holdings diversificadas, como ITSA4, que não captam
 * depósito. Mandá-las à via do acionista sem ponte de dívida seria o erro que
 * a Porta 1 existe para evitar, ao contrário.
 */
export const FinancialSectors = {
  /** Chave do setor financeiro na taxonomia do perfil da fonte de preços. */
  sourceKey: 'servicos-financeiros',

  /** Chave do setor econômico `Financeiro` da B3. */
  officialSectorKey: 'financeiro',

  /**
   * Subsetores da B3 em que depósito, captação, reserva técnica ou caixa de
   * clientes são matéria-prima: bancos, seguradoras, resseguradora, bolsa e
   * serviços financeiros.
   */
  officialSubsectors: [
    'intermediarios financeiros',
    'previdencia e seguros',
    'servicos financeiros diversos',
  ] as readonly string[],

  /**
   * `true` quando o ativo entra na Porta 1.
   *
   * - [sectorKey]: chave setorial, já em minúsculas.
   * - [industry]: subsetor, como publicado — na taxonomia oficial,
   *   "Subsetor / Segmento".
   */
  isFinancial(args: { sectorKey?: string | null; industry?: string | null } = {}): boolean {
    const key = args.sectorKey?.trim().toLowerCase();
    if (key === FinancialSectors.sourceKey) return true;
    if (key !== FinancialSectors.officialSectorKey) return false;
    const sub = CyclicalSectors.normalize(args.industry);
    for (const s of FinancialSectors.officialSubsectors) {
      if (sub.startsWith(s)) return true;
    }
    return false;
  },
};
