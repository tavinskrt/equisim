#!/usr/bin/env node
/**
 * Verificacoes locais do gate de QA. SEM REDE.
 *
 * Roda no `pre-commit`, onde o orcamento e de milissegundos: os commits deste
 * projeto saem pelo GitHub Desktop, que congela a interface enquanto o hook
 * executa e nao oferece `--no-verify` na tela. Qualquer coisa que dependa de
 * rede vai para o `pre-push`.
 *
 * POR QUE .mjs E NAO .ts: este arquivo roda com `node` puro, sem `tsx` e sem
 * `npx`. O hook e disparado por um processo GUI, onde cada camada a mais de
 * resolucao e um ponto de falha e algumas centenas de milissegundos. O resto
 * da cadeia de QA e TypeScript; este arquivo e a excecao deliberada.
 *
 * ESCOPO: apenas LINHAS ADICIONADAS pelo que esta em staging. Codigo legado
 * nao e julgado -- mesma calibragem do agente Gemini (ver qa/rules.ts).
 *
 * Saida: 0 = liberado, 1 = bloqueado.
 */
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';

const SKIP_FILE = '.qa-skip';

/**
 * Arquivo que declara os tokens de cor. Sua existencia LIGA as regras de
 * sistema de design (L6-L11).
 *
 * POR QUE UM GATILHO E NAO UM INTERRUPTOR MANUAL: hoje a base tem 62 literais
 * `Color(0x...)` e 209 espacadores magicos. Ligar essas regras antes de o
 * sistema existir bloquearia todo commit de interface -- inclusive os da
 * propria refatoracao, que precisa declarar cor literal em algum lugar. Seria
 * repetir o defeito que a lista ENV_TEMPLATES abaixo documenta: um gate que
 * impede trabalho legitimo e um gate que sera arrancado.
 *
 * Com o gatilho, as regras nascem dormentes e acordam sozinhas no commit que
 * cria o sistema (tarefa UI-01 do plano de refatoracao). A partir dai, todo
 * literal NOVO em codigo de tela e regressao -- porque passou a existir para
 * onde apontar.
 *
 * LIMITACAO CONHECIDA: durante a migracao (tarefas UI-09/UI-10), mover uma
 * linha legada de lugar faz o git registra-la como adicionada, e a regra
 * dispara. Isso e desconforto, nao defeito: a ordem de trabalho pretendida e
 * migrar o arquivo inteiro e so entao commitar, e nesse caso as linhas
 * adicionadas ja usam token.
 */
const TOKEN_SYSTEM_ANCHOR = 'lib/presentation/theme/fin_colors.dart';

/** Diretorio do sistema de tokens: e a casa dos literais, nao pode ser reu. */
const THEME_DIR = 'lib/presentation/theme/';

const TOKENS_ACTIVE = existsSync(TOKEN_SYSTEM_ANCHOR);

/**
 * Codigo de tela: Dart sob `lib/`, fora do diretorio de tokens e fora do que o
 * `build_runner` gera.
 *
 * `packages/equisim_core` fica de fora por construcao -- e Dart puro, sem
 * Flutter, entao nao ha cor nem widget la para julgar.
 */
function isScreenDart(file) {
  return (
    file.startsWith('lib/') &&
    file.endsWith('.dart') &&
    !file.endsWith('.g.dart') &&
    !file.startsWith(THEME_DIR)
  );
}

/**
 * Regras deterministicas de linha.
 *
 * Criterio de admissao: falso positivo proximo de zero. Uma regra que exige
 * julgamento nao entra aqui -- entra no rulebook do Gemini, que roda no push.
 * Cada `test` recebe a linha adicionada (sem o "+") e o caminho do arquivo.
 */
const RULES = [
  {
    id: 'L1',
    category: 'FLOAT_EQUALITY',
    title: 'Comparacao de igualdade com literal de ponto flutuante',
    appliesTo: (file) => file.endsWith('.dart'),
    test: (line) => /[=!]=\s*-?\d+\.\d+/.test(stripStringsAndComments(line)),
    explain:
      'Em IEEE-754, 0.1 + 0.2 != 0.3. Comparar dinheiro com == falha de forma\n' +
      '  silenciosa e intermitente. Compare centavos inteiros, ou use epsilon\n' +
      '  proporcional a escala do valor.',
  },
  {
    id: 'L2',
    category: 'MERGE_CONFLICT',
    title: 'Marcador de conflito de merge nao resolvido',
    appliesTo: () => true,
    test: (line) => /^(<{7}|={7}|>{7})(\s|$)/.test(line),
    explain: 'O arquivo tem conflito de merge por resolver. Commitar assim quebra o build.',
  },
  {
    id: 'L3',
    category: 'NONDETERMINISTIC_CORE',
    title: 'DateTime.now() dentro do nucleo de dominio puro',
    appliesTo: (file) => file.startsWith('packages/equisim_core/lib/'),
    // `asOf ?? DateTime.now()` e o padrao CORRETO -- relogio injetavel com
    // fallback. Só o uso direto, sem injecao, torna o calculo irreproduzivel
    // e o teste nao-deterministico.
    test: (line) => {
      const code = stripStringsAndComments(line);
      return /DateTime\.now\(\)/.test(code) && !/\?\?\s*DateTime\.now\(\)/.test(code);
    },
    explain:
      'O nucleo precisa ser reproduzivel: a mesma entrada tem de dar a mesma\n' +
      '  saida hoje e daqui a um ano. Receba a data por parametro, com o padrao\n' +
      '  ja usado no repositorio: `asOf ?? DateTime.now()`.',
  },
  {
    id: 'L4',
    category: 'ROUNDING',
    title: 'Arredondamento por ida e volta em String',
    appliesTo: (file) => file.endsWith('.dart'),
    test: (line) => {
      const code = stripStringsAndComments(line);
      return /parse\s*\(/.test(code) && /toStringAsFixed\s*\(/.test(code);
    },
    explain:
      'toStringAsFixed formata a representacao binaria, nao arredonda em half-up\n' +
      '  decimal: (2.675).toStringAsFixed(2) devolve "2.67". Converter de volta\n' +
      '  para double propaga o erro como se fosse valor arredondado.',
  },

  // --- Sistema de design ---------------------------------------------------
  //
  // Da L6 em diante as regras tem `requiresTokens: true` e so valem depois que
  // `lib/presentation/theme/fin_colors.dart` existe. Ver TOKEN_SYSTEM_ANCHOR.
  //
  // Todas operam na forma de UMA LINHA. A forma multilinha (`EdgeInsets.only(`
  // com os argumentos abaixo) escapa de proposito: um scanner de linha nao a
  // reconhece sem virar parser, e chutar aqui produziria o falso positivo que
  // este arquivo nao admite. Esse resto fica com a regra R17 do Gemini, que le
  // a arvore inteira no pre-push.

  {
    id: 'L5',
    category: 'DESIGN_TOKEN',
    title: 'fontSize com valor fracionario',
    // Sem gatilho: meio pixel nao e degrau de escala em regime nenhum. Os oito
    // tamanhos fracionarios da base (9.5, 10.5, 11.5, 12.5, 13.5...) nasceram
    // de empurrar o numero ate caber, e nao de uma decisao tipografica.
    appliesTo: (file) => file.endsWith('.dart'),
    test: (line) => /\bfontSize\s*:\s*\d+\.\d+/.test(stripStringsAndComments(line)),
    explain:
      'Meio pixel nao e um degrau perceptivel de hierarquia: 12 e 12.5 leem\n' +
      '  igual, e o par so existe porque alguem ajustou ate caber. Use um passo\n' +
      '  inteiro da escala tipografica.',
  },
  {
    id: 'L6',
    category: 'DESIGN_TOKEN',
    title: 'Cor literal fora do arquivo de tokens',
    requiresTokens: true,
    appliesTo: isScreenDart,
    test: (line) => /\bColor\(\s*0x[0-9a-fA-F]{6,8}\s*\)/.test(stripStringsAndComments(line)),
    explain:
      'Cor declarada no ponto de uso nao pode ser corrigida de um lugar so, e e\n' +
      '  como o contraste reprovado se espalhou. Declare em FinColors e leia por\n' +
      '  context.fin.<token>.',
  },
  {
    id: 'L7',
    category: 'DESIGN_TOKEN',
    title: 'Cor do Material em vez de token semantico',
    requiresTokens: true,
    appliesTo: isScreenDart,
    // `AppColors.` e `FinColors.` nao casam: nao ha limite de palavra entre a
    // letra anterior e o "C". `Colors.transparent` fica de fora porque nao tem
    // equivalente em token -- e legitimo em Material(color:) e no feedback de
    // Draggable.
    test: (line) => /\bColors\.(?!transparent\b)[a-z]/.test(stripStringsAndComments(line)),
    explain:
      'A paleta do Material nao conhece a semantica financeira desta interface.\n' +
      '  Use context.fin: positive, negative, caution, pending, blocked ou os\n' +
      '  tokens de superficie e texto.',
  },
  {
    id: 'L8',
    category: 'DESIGN_TOKEN',
    title: 'Espacador com medida magica',
    requiresTokens: true,
    appliesTo: isScreenDart,
    // Casa so a forma de espacador: uma dimensao e o parentese fechando na
    // mesma linha. `SizedBox(height: 240, child: LineChart(...))` nao casa,
    // porque ali o numero e altura de contrato, nao espacamento.
    test: (line) =>
      /\bSizedBox\(\s*(?:height|width)\s*:\s*[\d.]+\s*\)/.test(stripStringsAndComments(line)),
    explain:
      'Espacamento fora do grid produz ritmo irregular: dois cartoes vizinhos\n' +
      '  respiram diferente sem razao de conteudo. Use Gap.xs/sm/md/lg/xl, que\n' +
      '  nao tem construtor para numero solto.',
  },
  {
    id: 'L9',
    category: 'DESIGN_TOKEN',
    title: 'EdgeInsets com numero solto',
    requiresTokens: true,
    appliesTo: isScreenDart,
    test: (line) =>
      /\bEdgeInsets\.(?:all|symmetric|only|fromLTRB)\([^)]*\d/.test(stripStringsAndComments(line)),
    explain:
      'Use os passos de FinSpace: xxs 2, xs 4, sm 8, md 12, lg 16, xl 24,\n' +
      '  xxl 32, xxxl 48. O xxs e meio passo, reservado a ajuste optico dentro\n' +
      '  de pastilha -- nao e degrau de layout. Se o valor de que voce precisa\n' +
      '  nao esta na escala, acrescente-o a FinSpace com um nome: a escala\n' +
      '  cresce por decisao, nao por acumulo.',
  },
  {
    id: 'L10',
    category: 'DESIGN_TOKEN',
    title: 'fontSize literal fora do arquivo de tipografia',
    requiresTokens: true,
    appliesTo: isScreenDart,
    // O lookahead impede que `fontSize: 10.5` case aqui: o `\d+` guloso pega
    // "10", ve o ponto e falha; ao retroceder para "1" ve o "0" e falha de
    // novo. O caso fracionario e da L5, que roda sempre.
    test: (line) => /\bfontSize\s*:\s*\d+(?![\d.])/.test(stripStringsAndComments(line)),
    explain:
      'Tamanho declarado no ponto de uso e como a base chegou a 20 tamanhos\n' +
      '  distintos. Use context.finType: caption, label, bodySm, bodyMd, titleSm,\n' +
      '  titleLg -- ou a familia num* para dinheiro, percentual e razao.',
  },
  {
    id: 'L11',
    category: 'DESIGN_TOKEN',
    title: 'Tema semeado por cor em vez dos tokens',
    requiresTokens: true,
    appliesTo: (file) => file.endsWith('.dart') && !file.startsWith(THEME_DIR),
    test: (line) => /\bColorScheme\.fromSeed\s*\(/.test(stripStringsAndComments(line)),
    explain:
      'fromSeed gera uma paleta que nao conhece a marca nem a semantica de\n' +
      '  ganho e perda -- e o que fazia o indicador de progresso girar em azul\n' +
      '  sobre tela verde. Monte o ColorScheme a partir de FinColors.',
  },
];

/**
 * Templates de ambiente. Sao feitos para SER versionados: contem apenas nomes
 * de variavel e valores de exemplo.
 *
 * Esta lista existe porque a primeira versao da regra bloqueou `.env.example`
 * -- um arquivo ja rastreado pelo repositorio. O gate impediu o commit de
 * trabalho legitimo, que e exatamente o defeito que mata um gate.
 */
const ENV_TEMPLATES = /^\.env\.(example|sample|template|dist|defaults)$/;

/** Arquivos que nunca devem entrar em um commit. */
const FORBIDDEN_FILES = [
  {
    pattern: /^\.env(\.|$)/,
    exempt: ENV_TEMPLATES,
    why: 'contem credencial, e `.env` ainda e declarado como asset do Flutter',
  },
  { pattern: /(^|\/)google-services\.json$/, why: 'credencial do Firebase' },
  { pattern: /(^|\/)serviceAccount.*\.json$/, why: 'chave de conta de servico' },
  { pattern: /\.(p12|jks|keystore|pem)$/, why: 'material criptografico' },
];

/**
 * Remove literais de string e comentarios antes de aplicar as regras.
 *
 * Sem isto, um comentario explicando "nunca use == 0.0" acusaria a si mesmo, e
 * uma mensagem de erro contendo o texto viraria falso positivo. Aproximacao
 * suficiente para regex de linha -- nao pretende ser um lexer de Dart.
 */
function stripStringsAndComments(line) {
  return line
    .replace(/\/\/.*$/, '')
    .replace(/'(?:\\.|[^'\\])*'/g, "''")
    .replace(/"(?:\\.|[^"\\])*"/g, '""');
}

/**
 * Largura da mensagem.
 *
 * O diálogo "Commit failed" do GitHub Desktop é estreito e NAO quebra por
 * palavra: ele corta no meio ("do g / it", ".env.exa / mple"). Quebrar por
 * conta propria, curto, e o que mantem a mensagem legivel onde ela e lida.
 */
const WIDTH = 58;

/**
 * `prefix` entra na conta da primeira linha: sem isso, um rotulo como "[L1] "
 * empurra a linha para alem da largura e o dialogo volta a cortar no meio.
 *
 * As quebras de linha ja presentes no texto sao descartadas -- as mensagens
 * das regras vem quebradas para caber em 80 colunas de terminal, e reaproveitar
 * essas quebras aqui produziria linhas orfas de duas palavras.
 */
function wrap(text, prefix = '') {
  const words = text.replace(/\s+/g, ' ').trim().split(' ');
  const out = [];
  let line = prefix;
  let empty = true;

  for (const word of words) {
    if (empty) {
      line += word;
      empty = false;
    } else if (line.length + word.length + 1 <= WIDTH) {
      line += ` ${word}`;
    } else {
      out.push(line);
      line = word;
    }
  }
  if (!empty) out.push(line);
  return out.join('\n');
}

/** Evidencia longa vira ruido no dialogo estreito. */
function truncate(text) {
  const clean = text.trim();
  return clean.length <= WIDTH ? clean : `${clean.slice(0, WIDTH - 3)}...`;
}

function git(args) {
  return execFileSync('git', args, { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
}

/** Percorre o diff em staging e devolve as linhas ADICIONADAS, com arquivo e numero. */
function stagedAddedLines() {
  const diff = git(['diff', '--cached', '--unified=0', '--no-color', '--no-ext-diff']);
  const out = [];
  let file = null;
  let lineNo = 0;

  for (const raw of diff.split(/\r?\n/)) {
    if (raw.startsWith('+++ ')) {
      const path = raw.slice(4).trim();
      file = path === '/dev/null' ? null : path.replace(/^b\//, '');
      continue;
    }
    const hunk = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/.exec(raw);
    if (hunk) {
      lineNo = Number.parseInt(hunk[1], 10);
      continue;
    }
    if (file && raw.startsWith('+') && !raw.startsWith('+++')) {
      out.push({ file, line: lineNo, text: raw.slice(1) });
      lineNo++;
    }
  }
  return out;
}

function stagedFiles() {
  return git(['diff', '--cached', '--name-only', '--diff-filter=ACMR'])
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l !== '');
}

function main() {
  // Escape hatch: o GitHub Desktop nao expoe --no-verify na interface, entao a
  // valvula precisa existir no sistema de arquivos.
  if (existsSync(SKIP_FILE)) {
    process.stderr.write(
      `[qa-local] ${SKIP_FILE} presente -- verificacoes puladas.\n` +
        `[qa-local] Apague o arquivo para reativar o gate.\n`,
    );
    return 0;
  }

  const findings = [];

  for (const file of stagedFiles()) {
    const base = file.split('/').pop() ?? file;
    for (const { pattern, exempt, why } of FORBIDDEN_FILES) {
      if (exempt?.test(base)) continue;
      if (pattern.test(file)) {
        findings.push({
          id: 'L0',
          category: 'SECRET_STAGED',
          file,
          line: 0,
          title: `Arquivo proibido em commit: ${file}`,
          evidence: file,
          explain:
            `Este arquivo ${why}. Uma vez no historico do git, o segredo tem de\n` +
            '  ser considerado vazado mesmo apos remocao. Rode: git restore --staged ' +
            file,
        });
      }
    }
  }

  // `requiresTokens` e constante durante a execucao: filtrar uma vez, fora do
  // laco por linha, evita reavaliar a condicao milhares de vezes num diff
  // grande.
  const activeRules = RULES.filter((rule) => !rule.requiresTokens || TOKENS_ACTIVE);

  for (const { file, line, text } of stagedAddedLines()) {
    for (const rule of activeRules) {
      if (!rule.appliesTo(file)) continue;
      if (!rule.test(text)) continue;
      findings.push({
        id: rule.id,
        category: rule.category,
        file,
        line,
        title: rule.title,
        evidence: text.trim(),
        explain: rule.explain,
      });
    }
  }

  if (findings.length === 0) return 0;

  process.stderr.write(`\nGate local de QA: ${findings.length} bloqueio(s)\n`);
  for (const f of findings) {
    process.stderr.write(
      `\n${wrap(f.title, `[${f.id}] `)}\n` +
        `${f.file}${f.line > 0 ? `:${f.line}` : ''}\n` +
        `> ${truncate(f.evidence)}\n` +
        `${wrap(f.explain)}\n`,
    );
  }
  process.stderr.write(
    '\n' +
      wrap('Commit bloqueado. Verificacoes locais, sem rede.') +
      '\n' +
      wrap('A auditoria com o Gemini roda no git push.') +
      '\n\n' +
      wrap(`Emergencia: crie o arquivo ${SKIP_FILE} na raiz e apague depois.`) +
      '\n\n',
  );
  return 1;
}

process.exitCode = main();
