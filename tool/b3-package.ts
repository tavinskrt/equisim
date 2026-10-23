// A3.3 — empacota o registro de emissores da B3 para o aplicativo.
//
// Lê as respostas baixadas por `tool/b3_companhias_baixar.py`, passa cada uma
// pelo leitor do núcleo (`B3Registry`) e grava no formato de `B3RegistryCodec`.
// O aplicativo carrega o pacote e usa a contagem oficial como árbitro do
// divisor por papel (decisão 83).
//
// A classificação setorial oficial (item A5) sai do detalhe baixado por
// `tool/b3_complemento_baixar.py`; sem ele, o emissor fica sem classificação e o
// aplicativo recua para a taxonomia da fonte de preços.
//
// Uso:
//   python tool/b3_companhias_baixar.py
//   python tool/b3_complemento_baixar.py
//   npm run tool -- b3-package
import { existsSync, statSync } from 'node:fs';
import { basename } from 'node:path';

import { type B3Issuer, B3Registry, B3RegistryCodec, DateTime, type JsonObject } from '../src/core';
import { fail, filesIn, outln, readJson, writeText } from './lib/files';

const output = 'public/assets/b3/emissores.json';

export function main(_args: string[]): void {
  const dir = 'data/b3/companhias';
  if (!existsSync(dir)) fail('sem data/b3/companhias — rode tool/b3_companhias_baixar.py');
  const issuers: B3Issuer[] = [];
  let events = 0;
  let withoutCount = 0;
  let withoutClassification = 0;
  let oldest: DateTime | null = null;
  for (const f of filesIn(dir, /.*/)) {
    const raw = readJson<JsonObject>(f);
    const consultedAt = DateTime.parse(raw['consultadoEm'] as string);
    // A classificação setorial vem do detalhe do mesmo emissor (item A5).
    const supplement = `data/b3/complemento/${basename(f)}`;
    const detail = existsSync(supplement) ? ((readJson<JsonObject>(supplement)['detalhe'] as JsonObject | null | undefined) ?? null) : null;
    for (const c of raw['resposta'] as JsonObject[]) {
      const e = B3Registry.issuer(c, { consultedOn: consultedAt, detail });
      if (e === null) continue;
      issuers.push(e);
      events += e.events.length;
      if (e.totalShares === null) withoutCount++;
      if (e.classification === null) withoutClassification++;
      if (oldest === null || consultedAt.isBefore(oldest)) oldest = consultedAt;
    }
  }
  const pkg = B3RegistryCodec.encodePackage(issuers, { generatedAt: oldest ?? DateTime.utc(2000) });
  writeText(output, JSON.stringify(pkg));
  outln(`  emissores: ${issuers.length}  sem contagem: ${withoutCount}  sem classificação: ${withoutClassification}`);
  outln(`  eventos de ações compostos: ${events}`);
  outln(`  consulta mais antiga: ${oldest?.toIso8601String().slice(0, 10) ?? 'null'}`);
  outln(`  tamanho: ${(statSync(output).size / 1024).toFixed(0)} KB`);
  outln(`  gravado ${output}`);
}
