// A leitura da réplica fora da amostra (item C7, decisões 129 e 133).
//
// **Antes da data fixada, só a situação**: quantas coortes estão seladas e
// quantas já têm o retorno do horizonte — nenhuma estatística. **Na data**, o
// critério da decisão 96 sobre as previsões seladas do motor pré-registrado,
// pela mesma função que mede o R3, com os retornos de um backtest `--c7` feito
// com a base de então — e, ao lado, a mesma conta sobre a série de cada motor
// posterior, que é referência e não a leitura.
//
// Uso:
//   npm run tool -- c7-reading                        # situação
//   npm run tool -- c7-reading --ler 12 \
//       [--fim-dos-dados AAAA-MM-DD] [--hoje AAAA-MM-DD]  # a partir de 30/09/2029
import { existsSync, writeFileSync } from 'node:fs';

import { DateTime, parseInt_ } from '../src/core';
import { ProtocolViolated, read, sealsDir, situation } from './c7/protocol';
import { errln, fail, flagValue, jsonPretty, outln, readJson } from './lib/files';

type Json = Record<string, unknown>;

export async function main(args: string[]): Promise<void> {
  const today = DateTime.parse(flagValue(args, '--hoje') ?? DateTime.now().toIso8601String().slice(0, 10));
  const dataEnd = DateTime.parse(flagValue(args, '--fim-dos-dados') ?? '2026-09-04');
  const folder = sealsDir;
  const reading = flagValue(args, '--ler');

  if (reading === null) {
    outln(jsonPretty(situation({ folder, today, dataEnd }), '  '));
    return;
  }
  const source = 'data/c7/coortes.json';
  if (!existsSync(source)) fail(`Falta ${source}, com os retornos: rode o backtest em modo --c7 com --fim-dos-dados da base de hoje.`);
  try {
    const months = parseInt_(reading);
    const result = await readFromFile(months, folder, today, source);
    const output = `${folder}/leitura_${months}m.json`;
    writeFileSync(output, `${jsonPretty(result)}\n`);
    const fm = ((result['leitura'] as Json)['famaMacBeth'] as Json)['potencialDadoBm'] as Json | null;
    outln(`== C7, ${months} meses ==`);
    outln(
      `  potencial dado o B/M: ${fm?.['media'] ?? null}  t corrigido ${fm?.['tSobreposicao'] ?? null} / ${fm?.['criticoSobreposicao'] ?? null}  ` +
        `Newey-West ${fm?.['tNeweyWest'] ?? null}  passa: ${fm?.['passaR3'] ?? false}`,
    );
    outln(`  previsões refeitas que divergem do selo: ${result['previsoesRefeitasQueDivergem']}`);
    // A leitura é a do pré-registrado; a de cada motor posterior vem ao lado,
    // sem decidir nada (decisão 129).
    for (const [engine, value] of Object.entries(result['motoresDaData'] as Json)) {
      const m = ((value as Json)['famaMacBeth'] as Json)['potencialDadoBm'] as Json | null;
      outln(`  motor da data ${engine.slice(0, 8)}: ${m?.['media'] ?? null}  t corrigido ${m?.['tSobreposicao'] ?? null}  (referência, não a leitura)`);
    }
    outln(`  escrito ${output}`);
  } catch (e) {
    if (!(e instanceof ProtocolViolated)) throw e;
    errln(e.toString());
    process.exit(1);
  }
}

export function readFromFile(months: number, folder: string, today: DateTime, source: string): Promise<Json> {
  return read({ months, folder, today, rows: readJson<Json[]>(source) });
}
