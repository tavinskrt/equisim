// Sela as previsões das coortes novas (item C7, decisões 129 e 133).
//
// Lê `data/c7/coortes.json` — do backtest em modo `--c7` — e grava, em
// `docs/validacao/c7/`, um arquivo de previsões por coorte que ainda não tem
// selo do motor atual, com o hash do git dele no índice. **Nunca reescreve um
// selo**: uma coorte já selada é refeita e conferida, e a divergência é
// relatada. Ver `tool/c7/protocol.ts`.
//
// Uso, a cada trimestre fechado:
//   npm run tool -- backtest-valuation --montagem aplicativo \
//       --com-deslistadas --trimestral --c7 [--fim-dos-dados AAAA-MM-DD]
//   npm run tool -- c7-seal [--hoje AAAA-MM-DD]
//   npm run tool -- c7-preregistered [--fim-dos-dados AAAA-MM-DD]
//
// Com o motor igual ao pré-registrado, este programa sela a série
// pré-registrada; com motor novo, sela a série «motor da data», e a
// pré-registrada sai do commit dela pelo terceiro passo (decisão 138).
//
// **Selar logo depois da coorte** é o que dá valor ao selo: o commit do
// arquivo selado é a prova de que a previsão existia antes do desfecho.
import { existsSync } from 'node:fs';

import { DateTime } from '../src/core';
import { currentEngine, ProtocolViolated, seal, sealsDir } from './c7/protocol';
import { errln, fail, flagValue, outln, readJson } from './lib/files';

export async function main(args: string[]): Promise<void> {
  const source = 'data/c7/coortes.json';
  if (!existsSync(source)) {
    fail(`Falta ${source}. Rode antes: npm run tool -- backtest-valuation --montagem aplicativo --com-deslistadas --trimestral --c7`);
  }
  const rows = readJson<Record<string, unknown>[]>(source);
  const engine = await currentEngine();
  // A data do selo é injetável, como na leitura: o relógio só entra quando
  // `--hoje` não vem. O que prova quando o selo foi feito é o commit dele.
  const today = flagValue(args, '--hoje') ?? DateTime.now().toIso8601String().slice(0, 10);
  try {
    const r = await seal({ rows, engine, folder: sealsDir, today });
    outln(`== Selagem do C7 — série ${r.series} ==`);
    outln(`  motor: ${engine.fingerprint}${engine.clean ? '' : `  (núcleo com mudança não commitada sobre ${engine.commit?.slice(0, 7)})`}`);
    outln(`  seladas agora: ${r.sealedCohorts.length === 0 ? 'nenhuma' : r.sealedCohorts.join(', ')}`);
    outln(`  já seladas, conferidas: ${r.alreadySealed.length === 0 ? 'nenhuma' : r.alreadySealed.join(', ')}`);
    for (const [cohort, n] of r.divergent) {
      outln(`  ! ${cohort}: ${n} previsões refeitas divergem do selo — o selo não muda, e a divergência precisa de explicação`);
    }
    if (r.series !== 'preRegistrado') {
      outln(
        '  ! o motor mudou desde o pré-registrado: a série dele para estas coortes sai do commit registrado no índice — rode ' +
          '`npm run tool -- c7-preregistered` (decisão 138)',
      );
    }
  } catch (e) {
    if (!(e instanceof ProtocolViolated)) throw e;
    errln(e.toString());
    process.exit(1);
  }
}
