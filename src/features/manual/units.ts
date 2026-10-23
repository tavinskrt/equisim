import { ManualField } from '../../core';
import { Fmt } from '../../copy';

/**
 * A unidade de cada campo do editor: como ele aparece, como se lê o que foi
 * digitado e a tolerância que separa "seu número" de "o do motor".
 *
 * - `reais`: lucro, editado em **milhões** — ninguém digita nove zeros.
 * - `rate`: taxa ao ano, editada em pontos percentuais com duas casas.
 * - `fraction`: parcela do lucro, editada em percentual com uma casa.
 */
export type Unit = 'reais' | 'rate' | 'fraction';

export const Units = {
  /** O texto do campo: `1.234,5` vira `1234,5`, sem prefixo nem sufixo. */
  display(u: Unit, v: number): string {
    switch (u) {
      case 'reais':
        return Fmt.ratio(v / 1e6, 1);
      case 'rate':
        return Fmt.ratio(v * 100, 2);
      case 'fraction':
        return Fmt.ratio(v * 100, 1);
    }
  },

  /** O valor por extenso, para a referência do motor e o leitor de tela. */
  reference(u: Unit, v: number): string {
    return u === 'reais' ? `R$ ${Units.display(u, v)} mi` : `${Units.display(u, v)}%`;
  },

  /**
   * Lê o que foi digitado, em pt-BR. O ponto é separador de milhar quando há
   * vírgula, e — **só no lucro** — quando separa grupos de três: "1.250" é mil
   * duzentos e cinquenta milhões, mas "12.5" numa taxa continua 12,5%.
   */
  read(u: Unit, text: string): number | null {
    let s = text.replace(/\s/g, '').replace('R$', '').replace('%', '').replace('−', '-');
    if (s === '' || s === '-') return null;
    if (s.includes(',')) s = s.replace(/\./g, '').replace(',', '.');
    else if (u === 'reais' && /^-?\d{1,3}(\.\d{3})+$/.test(s)) s = s.replace(/\./g, '');
    const n = Number(s);
    if (!Number.isFinite(n) || s.trim() === '') return null;
    return u === 'reais' ? n * 1e6 : n / 100;
  },

  /** Abaixo disto, o campo ainda é o do motor: meia casa da exibição. */
  tolerance(u: Unit): number {
    switch (u) {
      case 'reais':
        return 0.05e6;
      case 'rate':
        return 0.00005;
      case 'fraction':
        return 0.0005;
    }
  },

  suffix(u: Unit): string {
    return u === 'reais' ? 'mi' : u === 'rate' ? '% a.a.' : '%';
  },

  of(field: ManualField): Unit {
    if (field === ManualField.baseProfit) return 'reais';
    if (field === ManualField.retention) return 'fraction';
    return 'rate';
  },
};
