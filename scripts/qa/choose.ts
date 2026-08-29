/**
 * Escolha interativa do modelo, feita DEPOIS de mostrar o tamanho do alvo.
 *
 * O ponto e decidir com o diff na frente: um diff de 4 linhas nao merece o Pro
 * high (3-4 min), e um refactor de 17 arquivos nao merece o Flash low. Fixar um
 * padrao unico erra nos dois extremos.
 *
 * REGRA INEGOCIAVEL: so pergunta quando ha terminal. Um hook de git roda sem
 * TTY -- perguntar ali travaria o commit num prompt que ninguem ve, que e
 * exatamente o modo de falha que faz um gate ser arrancado.
 */
import { createInterface } from 'node:readline';

import type { AuditTarget } from './collect.ts';
import { latestChoices, listAgyModels, type ModelChoice } from './models.ts';

/**
 * Estimativa de tokens de entrada, calibrada com medicao real deste repositorio.
 *
 * Duas medicoes, mesmo backend `agy`:
 *
 *   arquivo de 4 linhas   ->  12.022 tokens de entrada
 *   diff de 124.859 chars ->  56.235 tokens de entrada
 *
 * A primeira e praticamente toda custo FIXO: o `agy` e um agente, e injeta o
 * proprio system prompt mais a definicao de ~50 ferramentas em toda chamada.
 * Nosso rulebook viaja dentro desse mesmo bloco. Ou seja, ~12.000 tokens saem
 * antes de qualquer codigo ser lido.
 *
 * Subtraindo o fixo da segunda medicao sobram 44.235 tokens para 124.859
 * caracteres -- 2,8 caracteres por token. Codigo denso tokeniza bem pior que a
 * regra classica de 4 caracteres.
 *
 * A conta abaixo reproduz as duas medicoes com erro de ~1%.
 */
const CHARS_PER_TOKEN = 2.8;
const FIXED_OVERHEAD_TOKENS = 12_000;

function estimateTokens(chars: number): number {
  return Math.round(chars / CHARS_PER_TOKEN);
}

function describeTarget(target: AuditTarget): string {
  const material = estimateTokens(target.payload.length);
  const total = material + FIXED_OVERHEAD_TOKENS;
  const k = (n: number): string => `${Math.round(n / 1000)}k`;
  return (
    `${target.files.length} arquivo(s), ` +
    `${target.payload.length.toLocaleString('pt-BR')} caracteres\n` +
    `      ~${k(material)} tokens de material + ~${k(FIXED_OVERHEAD_TOKENS)} ` +
    `de overhead fixo = ~${k(total)} de entrada`
  );
}

/** Como resolver a escolha de modelo. */
export interface ChooseOptions {
  /** Terminal disponivel? Sem isso, nao ha o que perguntar. */
  interactive: boolean;
  /** Modelo ja definido por --model: respeitado, sem pergunta. */
  explicitModel?: string;
}

/**
 * Devolve o id do modelo escolhido, ou `undefined` para deixar o backend usar
 * o padrao dele.
 */
export async function chooseModel(
  target: AuditTarget,
  opts: ChooseOptions,
): Promise<string | undefined> {
  if (opts.explicitModel) return opts.explicitModel;
  if (!opts.interactive) return undefined;

  let choices: ModelChoice[];
  try {
    choices = latestChoices(listAgyModels());
  } catch (error) {
    // Falhar a descoberta nao pode impedir a auditoria: seguimos no padrao.
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`  (nao listei os modelos: ${message})\n`);
    return undefined;
  }
  if (choices.length === 0) return undefined;

  process.stdout.write(`\nAlvo: ${target.label}\n`);
  process.stdout.write(
    `      ${describeTarget(target)}\n\n`,
  );
  process.stdout.write('Modelo para esta auditoria:\n');
  choices.forEach((c, i) => {
    process.stdout.write(
      `  ${i + 1}) ${c.id.padEnd(24)} ${c.hint}\n`,
    );
  });
  process.stdout.write(`  0) padrao do backend\n\n`);

  const answer = await ask(`Escolha [1-${choices.length}, Enter = 1]: `);
  const trimmed = answer.trim();

  if (trimmed === '0') return undefined;
  if (trimmed === '') return choices[0]!.id;

  const index = Number.parseInt(trimmed, 10);
  if (Number.isInteger(index) && index >= 1 && index <= choices.length) {
    return choices[index - 1]!.id;
  }

  process.stdout.write(`  entrada invalida; usando ${choices[0]!.id}\n`);
  return choices[0]!.id;
}

function ask(question: string): Promise<string> {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer);
    });
  });
}
