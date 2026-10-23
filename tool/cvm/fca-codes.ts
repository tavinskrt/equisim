// Códigos de negociação e composição de unit declarados na FCA da CVM.
//
// A FCA traz, por valor mobiliário, o código de negociação **de 2018 em
// diante** (de 2010 a 2017 a coluna vem vazia, limitações §1.11) e, para a
// unit, a composição em texto livre. Serve a duas coisas no item C3:
//
// - **encadear o ticker renomeado**: a fonte de preços publica a série inteira
//   sob o código de hoje, e o COTAHIST, sob o código de cada época — a BHIA3
//   era VVAR3 até 2023, a VBBR3 era BRDT3 até 2021;
// - **conferir a razão de unidade**: a composição declarada é a verdade contra
//   a qual a razão medida na coorte se confere.
//
// **Desde o item B16 ela deixou de ser só conferência**: a composição
// declarada passou a ser o que o motor usa, e a razão medida no valor de
// mercado, a conferência. Por isso ela é indexada por **CNPJ** e por **ano**:
// o código de negociação da FCA vem em branco ou zerado em parte das linhas —
// a BPAC11 declara sob `000000` —, e uma avaliação datada precisa do
// formulário vigente na data dela, não do último.
import { existsSync, readdirSync, statSync } from 'node:fs';

import { compareStr, UnitComposition, UnitCompositionCodec } from '../../src/core';
import { readCvmCsv } from './csv';

/** Código com cara de ticker da B3: quatro letras e o número da classe. */
const tickerPattern = /^[A-Z]{4}\d{1,2}$/;

/** Códigos de negociação por CNPJ, e composição de unit por CNPJ e por código. */
export class FcaCodes {
  private constructor(
    /** Códigos de ação declarados por cada companhia, em qualquer ano. */
    readonly byCnpj: Map<string, Set<string>>,
    /**
     * Ações por unit, lidas da composição declarada, por código de unit.
     *
     * Continua existindo para a conferência de
     * [`ponte_por_papel.md`](../../docs/validacao/ponte_por_papel.md) §3, que
     * compara a razão medida com a declarada sem passar pelo CNPJ. Vale a do
     * formulário mais recente, e por isso **não** serve a uma avaliação datada
     * — para essa, [unitsByCnpj].
     */
    readonly sharesPerUnit: Map<string, number>,
    /** Composição declarada de cada unit, por ano, por CNPJ da companhia. */
    readonly unitsByCnpj: Map<string, UnitComposition[]>,
  ) {}

  /**
   * Lê todas as FCAs de valor mobiliário em [dir]. Sem arquivo, devolve mapas
   * vazios — quem chama recua para o próprio ticker.
   */
  static read(dir = 'data/cvm'): FcaCodes {
    const byCnpj = new Map<string, Set<string>>();
    const unit = new Map<string, number>();
    const byCnpjUnit = new Map<string, Map<number, UnitComposition>>();
    if (!existsSync(dir)) return new FcaCodes(byCnpj, unit, new Map());
    const files = readdirSync(dir)
      .filter((name) => /^fca_cia_aberta_valor_mobiliario_\d{4}\.csv$/.test(name) && statSync(`${dir}/${name}`).isFile())
      .map((name) => `${dir}/${name}`)
      .sort(compareStr);
    for (const f of files) {
      const year = Number.parseInt(f.split('/').pop()!.replace(/\D/g, '').slice(0, 4), 10);
      for (const r of readCvmCsv(f)) {
        const cnpj = r['CNPJ_Companhia'];
        const code = (r['Codigo_Negociacao'] ?? '').trim().toUpperCase();
        if (cnpj !== undefined && tickerPattern.test(code)) {
          let set = byCnpj.get(cnpj);
          if (set === undefined) byCnpj.set(cnpj, (set = new Set()));
          set.add(code);
        }
        if (!(r['Valor_Mobiliario'] ?? '').startsWith('Units')) continue;
        const text = (r['Composicao_BDR_Unit'] ?? '').trim();
        const n = UnitCompositionCodec.parse(text);
        if (n === null) continue;
        if (tickerPattern.test(code)) unit.set(code, n);
        if (cnpj === undefined) continue;
        // Uma companhia pode ter mais de uma linha de unit no mesmo ano —
        // versões do formulário, ou classes distintas. Vale a **maior**
        // composição do ano: a linha residual costuma ser a que declara só uma
        // das espécies.
        let years = byCnpjUnit.get(cnpj);
        if (years === undefined) byCnpjUnit.set(cnpj, (years = new Map()));
        const current = years.get(year);
        if (current === undefined || n > current.shares) {
          years.set(year, new UnitComposition({ year, shares: n, declared: text }));
        }
      }
    }
    return new FcaCodes(
      byCnpj,
      unit,
      new Map([...byCnpjUnit].map(([cnpj, years]) => [cnpj, [...years.values()].sort((a, b) => a.year - b.year)])),
    );
  }
}
