// O prazo das outorgas como era conhecido numa data (item A6 nas coortes).
//
// O pacote do aplicativo (`public/assets/cvm/outorgas.json`) é o formulário
// mais recente de cada companhia, e numa coorte de 2018 isso é conhecimento
// futuro. Aqui cada coorte lê o Formulário de Referência **recebido pela CVM
// até a data dela** — a data de recebimento vem do quadro geral
// `fre_cia_aberta_AAAA.csv`, pelo número do documento —, com a mesma regra do
// pacote:
//
// - o documento de maior referência e, nela, de maior versão;
// - a mediana dos fins das outorgas vigentes (`FreConcessionTerm.summarize`);
// - e o filtro de idade transposto para a coorte: o pacote aceita formulário
//   de referência a partir de 2020, seis anos antes do ano em que foi montado,
//   e a coorte aceita o de até seis anos antes do ano dela.
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';

import { compareStr, ConcessionTerm, DateTime, FreConcessionTerm, type JsonObject, tryParseInt } from '../../src/core';
import { readCvmCsv } from './csv';

interface GrantDoc {
  readonly received: DateTime;
  readonly ref: DateTime;
  readonly version: number;
  readonly durations: string[];
}

const day = (v: string | undefined): DateTime | null =>
  v === undefined || v.length < 10 ? null : DateTime.tryParse(`${v.slice(0, 10)}T00:00:00Z`);

export class GrantsByDate {
  /** Anos de idade máxima do formulário, contados do ano da data. */
  static readonly maxAgeYears = 6;

  private constructor(
    /** CNPJ → documentos com concessão, com recebimento, referência, versão e os textos de duração. */
    private readonly docs: Map<string, GrantDoc[]>,
    /** Ticker → CNPJ. */
    private readonly bridge: Map<string, string>,
  ) {}

  /** Lê `data/cvm/fre` e a ponte ticker↔CNPJ. `null` sem os arquivos. */
  static read(folder = 'data/cvm/fre'): GrantsByDate | null {
    const bridgeFile = 'docs/validacao/ponte_cvm.json';
    if (!existsSync(folder) || !existsSync(bridgeFile)) return null;

    const receipt = new Map<string, DateTime>();
    const files = readdirSync(folder)
      .map((name) => `${folder}/${name}`)
      .filter((p) => statSync(p).isFile())
      .sort(compareStr);
    for (const f of files) {
      const name = f.split('/').pop()!;
      if (!/^fre_cia_aberta_\d{4}\.csv$/.test(name)) continue;
      for (const r of readCvmCsv(f)) {
        const id = r['ID_DOC'];
        const received = day(r['DT_RECEB']);
        if (id !== undefined && received !== null) receipt.set(id, received);
      }
    }

    const byDoc = new Map<string, GrantDoc & { cnpj: string }>();
    for (const f of files) {
      if (!f.includes('fre_cia_aberta_ativo_intangivel_')) continue;
      for (const r of readCvmCsv(f)) {
        if (!(r['Tipo_Ativo'] ?? '').startsWith('Concess')) continue;
        const id = r['ID_Documento'];
        const cnpj = r['CNPJ_Companhia'];
        const ref = day(r['Data_Referencia']);
        const version = tryParseInt(r['Versao'] ?? '');
        const received = id === undefined ? undefined : receipt.get(id);
        if (cnpj === undefined || ref === null || version === null || received === undefined) continue;
        const current = byDoc.get(id!);
        if (current === undefined) {
          byDoc.set(id!, { cnpj, received, ref, version, durations: [r['Duracao'] ?? ''] });
        } else {
          current.durations.push(r['Duracao'] ?? '');
        }
      }
    }
    const docs = new Map<string, GrantDoc[]>();
    for (const d of byDoc.values()) {
      let list = docs.get(d.cnpj);
      if (list === undefined) docs.set(d.cnpj, (list = []));
      list.push({ received: d.received, ref: d.ref, version: d.version, durations: d.durations });
    }

    const pairs = (JSON.parse(readFileSync(bridgeFile, 'utf8')) as JsonObject)['ponte'] as Record<string, string>;
    return new GrantsByDate(docs, new Map(Object.entries(pairs)));
  }

  /** O prazo conhecido em [date], ou `null`. */
  atDate(ticker: string, date: DateTime): ConcessionTerm | null {
    const cnpj = this.bridge.get(ticker);
    return cnpj === undefined ? null : this.atDateByCnpj(cnpj, date);
  }

  /**
   * O prazo da companhia [cnpj] conhecido em [date], ou `null` — para as
   * deslistadas, que não estão na ponte do universo de hoje.
   */
  atDateByCnpj(cnpj: string, date: DateTime): ConcessionTerm | null {
    const ownDocs = this.docs.get(cnpj);
    if (ownDocs === undefined) return null;
    const today = DateTime.utc(date.year, date.month, date.day);
    let best: GrantDoc | null = null;
    for (const d of ownDocs) {
      if (d.received.isAfter(today)) continue;
      if (best === null || d.ref.isAfter(best.ref) || (d.ref.isAtSameMomentAs(best.ref) && d.version > best.version)) best = d;
    }
    if (best === null || best.ref.year < date.year - GrantsByDate.maxAgeYears) return null;
    const summary = FreConcessionTerm.summarize(best.durations, best.ref);
    if (summary.end === null) return null;
    return new ConcessionTerm({
      end: summary.end,
      contracts: summary.contracts,
      parsed: summary.readCount,
      active: summary.inForceCount,
      reference: best.ref,
    });
  }
}
