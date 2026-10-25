// O setor das companhias deslistadas que a B3 não classifica (item C1b).
//
// A decisão 87 põe o setor da B3 em todo ativo, e o portal responde também
// para 43 das 164 deslistadas da ponte. Para as outras, a única classificação
// que existe é a que a companhia declara na FCA da CVM, o "setor de atividade",
// numa taxonomia diferente.
//
// **A cascata não precisa da taxonomia inteira, só de três portas**: a Porta 1
// (instituição financeira), a precedência do ciclo (commodity) e o prazo
// determinado (concessão). Então a tradução é medida, e não escrita à mão: para
// cada setor da CVM, as listadas que têm os dois cadastros dizem qual
// combinação das três portas é a da maioria, e a classificação da B3 mais comum
// com essa combinação passa a representar o setor. A concordância é conferida
// nas próprias listadas **sem a companhia**, para que ela não vote em si mesma.
//
// Setor da CVM sem listada que o represente fica sem classificação — e aí a
// Porta 1 não dispara, que é o recuo que a cascata já declara.
import { existsSync } from 'node:fs';

import {
  type B3Classification,
  compareNum,
  compareStr,
  ConcessionSectors,
  CyclicalSectors,
  FinancialSectors,
  tryParseInt,
} from '../../src/core';
import { filesIn } from '../lib/files';
import { readCvmCsv } from './csv';

/** As três portas da cascata que o setor decide. */
export interface Gates {
  readonly financial: boolean;
  readonly cyclical: boolean;
  readonly concession: boolean;
}

export function gatesOf(c: B3Classification): Gates {
  const args = { sectorKey: c.sectorKey, industry: c.industry };
  return {
    financial: FinancialSectors.isFinancial(args),
    cyclical: CyclicalSectors.hasCyclePrecedence(args),
    concession: ConcessionSectors.hasFiniteTerm(args),
  };
}

/** Chave de igualdade das portas — o registro do Dart comparava por valor. */
const gatesKey = (g: Gates) => `${g.financial}|${g.cyclical}|${g.concession}`;

/** Uma listada com os dois cadastros: CNPJ e classificação da B3. */
type Pair = readonly [cnpj: string, classification: B3Classification];

/** Concordância das três portas, pelo setor da CVM contra a B3. */
export interface SectorAgreement {
  readonly listed: number;
  readonly withoutReference: number;
  readonly financial: number;
  readonly cyclical: number;
  readonly concession: number;
  readonly totalCount: number;
  readonly divergent: string[];
}

export class CvmSector {
  private static readonly holdingPrefix = 'Emp. Adm. Part. - ';

  private constructor(
    /** Setor de atividade da FCA mais recente de cada CNPJ. */
    readonly sectorByCnpj: Map<string, string>,
    /** Setor da CVM → (CNPJ da listada, classificação da B3). */
    private readonly bySector: Map<string, Pair[]>,
  ) {}

  /**
   * Lê a FCA geral de `data/cvm` e liga as listadas pela ponte.
   *
   * - [listedClassification]: CNPJ da listada → classificação da B3.
   */
  static read(listedClassification: Map<string, B3Classification>, folder = 'data/cvm'): CvmSector | null {
    if (!existsSync(folder)) return null;
    const files = filesIn(folder, /^fca_cia_aberta_geral_\d{4}\.csv$/);
    if (files.length === 0) return null;
    const last = new Map<string, readonly [ref: string, version: number, sector: string]>();
    for (const f of files) {
      for (const r of readCvmCsv(f)) {
        const cnpj = r['CNPJ_Companhia'];
        const ref = r['Data_Referencia'] ?? '';
        const version = tryParseInt(r['Versao'] ?? '') ?? 0;
        const sector = (r['Setor_Atividade'] ?? '').trim();
        if (cnpj === undefined || sector === '') continue;
        const current = last.get(cnpj);
        if (current === undefined || compareStr(ref, current[0]) > 0 || (ref === current[0] && version >= current[1])) {
          last.set(cnpj, [ref, version, sector]);
        }
      }
    }
    const sectorByCnpj = new Map([...last].map(([cnpj, v]) => [cnpj, v[2]] as const));
    const bySector = new Map<string, Pair[]>();
    for (const [cnpj, classification] of listedClassification) {
      const sector = sectorByCnpj.get(cnpj);
      if (sector === undefined) continue;
      const list = bySector.get(sector) ?? [];
      list.push([cnpj, classification]);
      bySector.set(sector, list);
    }
    return new CvmSector(sectorByCnpj, bySector);
  }

  /**
   * As listadas do setor, tentando a forma sem o prefixo de holding e a com
   * ele quando a exata não tem nenhuma.
   */
  private pairs(sector: string): readonly Pair[] {
    const exact = this.bySector.get(sector);
    if (exact !== undefined && exact.length > 0) return exact;
    const p = CvmSector.holdingPrefix;
    const other = sector.startsWith(p) ? sector.slice(p.length) : `${p}${sector}`;
    return this.bySector.get(other) ?? [];
  }

  /** A classificação da B3 que representa o setor, sem [exclude]. */
  private static representative(pairs: readonly Pair[], exclude?: string): B3Classification | null {
    const useful = pairs.filter(([cnpj]) => cnpj !== exclude).map(([, c]) => c);
    if (useful.length === 0) return null;
    // Map preserva a ordem de inserção, como o LinkedHashMap do Dart: no
    // empate de votos fica a primeira combinação vista.
    const votes = new Map<string, number>();
    for (const c of useful) {
      const k = gatesKey(gatesOf(c));
      votes.set(k, (votes.get(k) ?? 0) + 1);
    }
    let majority: [string, number] | null = null;
    for (const entry of votes) if (majority === null || entry[1] > majority[1]) majority = entry;
    const byLabel = new Map<string, [B3Classification, number]>();
    for (const c of useful) {
      if (gatesKey(gatesOf(c)) !== majority![0]) continue;
      const current = byLabel.get(c.label);
      byLabel.set(c.label, [c, (current?.[1] ?? 0) + 1]);
    }
    // Empate de contagem: o rótulo em ordem alfabética, para o resultado não
    // depender da ordem de leitura.
    const sortedRows = [...byLabel.values()].sort((a, b) => {
      const n = compareNum(b[1], a[1]);
      return n !== 0 ? n : compareStr(a[0].label, b[0].label);
    });
    return sortedRows[0]![0];
  }

  /** A classificação que representa o setor da CVM de [cnpj], ou `null`. */
  classificationOf(cnpj: string): B3Classification | null {
    const sector = this.sectorByCnpj.get(cnpj);
    if (sector === undefined) return null;
    return CvmSector.representative(this.pairs(sector));
  }

  /**
   * Nas listadas, as três portas pelo setor da CVM, sem a companhia, contra as
   * portas pela B3.
   */
  agreement(): SectorAgreement {
    let n = 0;
    let withoutCount = 0;
    let financialCount = 0;
    let cyclicalCount = 0;
    let concessionCount = 0;
    let totalCount = 0;
    const divergent: string[] = [];
    for (const [sector, pairs] of this.bySector) {
      for (const [cnpj, b3] of pairs) {
        n++;
        const predicted = CvmSector.representative(pairs, cnpj);
        if (predicted === null) {
          withoutCount++;
          continue;
        }
        const p = gatesOf(predicted);
        const r = gatesOf(b3);
        if (p.financial === r.financial) financialCount++;
        if (p.cyclical === r.cyclical) cyclicalCount++;
        if (p.concession === r.concession) concessionCount++;
        if (gatesKey(p) === gatesKey(r)) {
          totalCount++;
        } else {
          divergent.push(`${sector}: ${b3.label} → ${predicted.label}`);
        }
      }
    }
    return {
      listed: n,
      withoutReference: withoutCount,
      financial: financialCount,
      cyclical: cyclicalCount,
      concession: concessionCount,
      totalCount,
      divergent,
    };
  }
}
