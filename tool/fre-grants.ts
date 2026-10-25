// A6 — o prazo das outorgas, do Formulário de Referência para o aplicativo.
//
// Lê o quadro de ativos intangíveis do FRE (item 9.1.b), fica com as linhas de
// "Concessões" do documento mais recente de cada companhia, e resume o texto
// livre da coluna `Duracao` pela mediana dos fins vigentes
// (`FreConcessionTerm`). Grava o pacote que o aplicativo lê e o relatório de
// cobertura.
//
// **Filtro de qualidade.** Só entra no pacote o prazo de um formulário com data
// de referência a partir de 2020 e com ao menos uma outorga vigente legível. O
// FRE repete contrato vencido e renovado com o prazo antigo — a distribuição da
// Cemig aparece "até fevereiro de 2016" no formulário de 2019 —, e prazo velho
// imposto como horizonte seria erro novo.
//
// **O que o pacote muda no preço é pouco, e está dito por quê** na decisão 88:
// com retorno terminal neutro, só o contrato que acaba dentro da projeção
// explícita move o preço.
//
// Uso:
//   python tool/cvm_baixar.py --docs FRE --destino data/cvm/fre
//   npm run tool -- fre-grants
import { existsSync } from 'node:fs';

import {
  B3RegistryCodec,
  compareStr,
  ConcessionSectors,
  ConcessionTerm,
  ConcessionTermsCodec,
  DateTime,
  FreConcessionTerm,
  type JsonObject,
  tryParseInt,
} from '../src/core';
import { readCvmCsv } from './cvm/csv';
import { fail, filesIn, jsonPretty, outln, readJson, writeText } from './lib/files';

const output = 'public/assets/cvm/outorgas.json';
const report = 'docs/validacao/outorgas.json';

/** Referência mínima do formulário: antes disso, o prazo é velho demais. */
const minReference = DateTime.utc(2020, 1, 1);

function day(v: string | undefined): DateTime | null {
  if (v === undefined || v.length < 10) return null;
  return DateTime.tryParse(`${v.slice(0, 10)}T00:00:00Z`);
}

const fmt = (d: DateTime): string => d.toIso8601String().slice(0, 10);

interface Latest {
  ref: DateTime;
  version: number;
  durations: string[];
}

export function main(_args: string[]): void {
  const dir = 'data/cvm/fre';
  if (!existsSync(dir)) fail('sem data/cvm/fre — rode: python tool/cvm_baixar.py --docs FRE --destino data/cvm/fre');
  const bridge = new Map<string, string[]>();
  const pairs = readJson<{ ponte: Record<string, string> }>('docs/validacao/ponte_cvm.json').ponte;
  for (const [ticker, cnpj] of Object.entries(pairs)) {
    let list = bridge.get(cnpj);
    if (list === undefined) bridge.set(cnpj, (list = []));
    list.push(ticker);
  }
  const registry = B3RegistryCodec.decodePackage(readJson<JsonObject>('public/assets/b3/emissores.json'));

  // CNPJ → documento mais recente com concessão: maior referência, e nela a
  // maior versão.
  const byCnpj = new Map<string, Latest>();
  for (const f of filesIn(dir, /fre_cia_aberta_ativo_intangivel_/)) {
    for (const r of readCvmCsv(f)) {
      if (!(r['Tipo_Ativo'] ?? '').startsWith('Concess')) continue;
      const cnpj = r['CNPJ_Companhia'];
      const ref = day(r['Data_Referencia']);
      const version = tryParseInt(r['Versao'] ?? '');
      if (cnpj === undefined || ref === null || version === null) continue;
      const current = byCnpj.get(cnpj);
      if (
        current === undefined ||
        ref.isAfter(current.ref) ||
        (ref.isAtSameMomentAs(current.ref) && version > current.version)
      ) {
        byCnpj.set(cnpj, { ref, version, durations: [r['Duracao'] ?? ''] });
      } else if (ref.isAtSameMomentAs(current.ref) && version === current.version) {
        current.durations.push(r['Duracao'] ?? '');
      }
    }
  }

  const pkg = new Map<string, ConcessionTerm>();
  const rows: Record<string, unknown>[] = [];
  for (const [cnpj, latest] of byCnpj) {
    const tickers = bridge.get(cnpj);
    if (tickers === undefined) continue;
    const summary = FreConcessionTerm.summarize(latest.durations, latest.ref);
    const recent = !latest.ref.isBefore(minReference);
    const enters = recent && summary.end !== null;
    for (const t of tickers) {
      const issuer = registry.get(t.length >= 4 ? t.slice(0, 4) : '');
      const c = issuer?.classification ?? null;
      const concession = c !== null && ConcessionSectors.hasFiniteTerm({ sectorKey: c.sectorKey, industry: c.industry });
      rows.push({
        ticker: t,
        cnpj,
        concessao: concession,
        classificacao: c?.label ?? null,
        referencia: fmt(latest.ref),
        versao: latest.version,
        contratos: summary.contracts,
        lidos: summary.readCount,
        vigentes: summary.inForceCount,
        fim: summary.end === null ? null : fmt(summary.end),
        entra: enters,
        motivo: enters
          ? null
          : !recent
            ? `formulário de ${latest.ref.year}, antes de 2020`
            : 'nenhuma outorga vigente com data legível',
      });
      if (enters) {
        pkg.set(
          t,
          new ConcessionTerm({
            end: summary.end!,
            contracts: summary.contracts,
            parsed: summary.readCount,
            active: summary.inForceCount,
            reference: latest.ref,
          }),
        );
      }
    }
  }
  rows.sort((a, b) => compareStr(a['ticker'] as string, b['ticker'] as string));

  let newest = DateTime.utc(2000);
  for (const v of byCnpj.values()) if (v.ref.isAfter(newest)) newest = v.ref;
  writeText(output, JSON.stringify(ConcessionTermsCodec.encode(pkg, { generatedAt: newest })));
  writeText(report, jsonPretty(rows));

  const concessions = rows.filter((l) => l['concessao'] === true);
  outln(`  companhias com concessão no FRE: ${byCnpj.size}`);
  outln(`  tickers ligados: ${rows.length}, no pacote: ${pkg.size}`);
  outln(`  concessões pela classificação da B3: ${concessions.length}`);
  for (const l of concessions) {
    outln(
      `    ${(l['ticker'] as string).padEnd(7)} ref ${l['referencia']}  ${l['vigentes']}/${l['contratos']} vigentes  ` +
        `fim ${(l['fim'] as string | null) ?? '—'}  ${l['entra'] === true ? 'ENTRA' : l['motivo']}`,
    );
  }
  outln(`  gravado ${output} e ${report}`);
}
