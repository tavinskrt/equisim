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
import { existsSync, readdirSync, readFileSync } from 'node:fs';

const SKIP_FILE = '.qa-skip';

/**
 * Arquivo que declara os tokens de cor. Sua existencia LIGA as regras de
 * sistema de design (L6-L10).
 *
 * POR QUE UM GATILHO E NAO UM INTERRUPTOR MANUAL: as regras nasceram quando a
 * interface era Flutter e ainda nao tinha tokens. Liga-las antes de o sistema
 * existir bloquearia todo commit de interface -- inclusive os da propria
 * refatoracao, que precisa declarar cor literal em algum lugar. Seria repetir o
 * defeito que a lista ENV_TEMPLATES abaixo documenta: um gate que impede
 * trabalho legitimo e um gate que sera arrancado.
 *
 * Na web (decisao 152) a casa dos tokens e `src/styles.css`: o bloco `@theme`
 * do Tailwind v4 e as variaveis `--*` dos dois temas. Enquanto ele existir,
 * todo literal NOVO em codigo de tela e regressao -- porque existe para onde
 * apontar.
 *
 * LIMITACAO CONHECIDA: mover uma linha de lugar faz o git registra-la como
 * adicionada, e a regra dispara sobre literal antigo. Isso e desconforto, nao
 * defeito: troque o literal pelo token no mesmo commit.
 */
const TOKEN_SYSTEM_ANCHOR = 'src/styles.css';

const TOKENS_ACTIVE = existsSync(TOKEN_SYSTEM_ANCHOR);

/** Codigo TypeScript, de qualquer camada. */
function isTs(file) {
  return /\.(ts|tsx|mts)$/.test(file) && !file.endsWith('.d.ts');
}

/**
 * Codigo de tela: componentes e telas, onde cor, espaco e tipo sao lidos dos
 * tokens. `src/core`, `src/data` e `src/audit` ficam de fora por construcao --
 * nao ha cor nem componente la para julgar.
 */
const SCREEN_DIRS = ['src/features/', 'src/ui/'];

function isScreenCode(file) {
  return /\.(ts|tsx)$/.test(file) && SCREEN_DIRS.some((dir) => file.startsWith(dir));
}

/**
 * O eixo dos graficos e SVG do Recharts, que recebe `fontSize` em numero e nao
 * aceita classe do Tailwind. O tamanho do eixo mora num lugar so,
 * `axisProps` deste arquivo, que e para a tipografia dos graficos o que
 * `src/styles.css` e para o resto.
 */
const CHART_TYPE_HOME = 'src/ui/charts/chart-frame.tsx';

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
    appliesTo: isTs,
    test: (line) => /[=!]==?\s*-?\d+\.\d+/.test(stripStringsAndComments(line)),
    explain:
      'Em IEEE-754, 0.1 + 0.2 !== 0.3. Comparar dinheiro com === falha de\n' +
      '  forma silenciosa e intermitente. Compare centavos inteiros, ou use\n' +
      '  epsilon proporcional a escala do valor.',
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
    title: 'Relogio de parede dentro do nucleo de dominio puro',
    // `src/core/lang/` e o runtime que imita o Dart -- e ali que
    // `DateTime.now()` e implementado sobre `new Date()`, e nao pode ser reu.
    appliesTo: (file) => isTs(file) && file.startsWith('src/core/') && !file.startsWith('src/core/lang/'),
    // `asOf ?? DateTime.now()` e o padrao CORRETO -- relogio injetavel com
    // fallback. So o uso direto, sem injecao, torna o calculo irreproduzivel
    // e o teste nao-deterministico. `new Date()` sem argumento e `Date.now()`
    // sao o mesmo relogio, pela porta do JavaScript.
    test: (line) => {
      const code = stripStringsAndComments(line);
      const dartClock = /DateTime\.now\(\)/.test(code) && !/\?\?\s*DateTime\.now\(\)/.test(code);
      const jsClock = /\bnew\s+Date\(\s*\)|\bDate\.now\(\)/.test(code);
      return dartClock || jsClock;
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
    appliesTo: isTs,
    test: (line) => {
      const code = stripStringsAndComments(line);
      return (
        /\b(?:Number|parseFloat|parseDouble)\s*\(/.test(code) &&
        /\.toFixed\s*\(|\btoStringAsFixed\s*\(/.test(code)
      );
    },
    explain:
      'toFixed formata a representacao binaria, nao arredonda em half-up\n' +
      '  decimal: (2.675).toFixed(2) devolve "2.67". Converter de volta para\n' +
      '  numero propaga o erro como se fosse valor arredondado. Arredonde em\n' +
      '  centavos inteiros.',
  },

  // --- Sistema de design ---------------------------------------------------
  //
  // Da L6 em diante as regras tem `requiresTokens: true` e so valem enquanto
  // `src/styles.css` existe. Ver TOKEN_SYSTEM_ANCHOR.
  //
  // Na web a cor e o espaco moram em string -- `className="text-red-500"`,
  // `style={{ color: '#fff' }}` --, entao estas regras leem a linha SEM os
  // comentarios, mas COM o conteudo das strings. Todas operam na forma de UMA
  // LINHA: o que se espalha por varias escapa de proposito, e fica com a regra
  // R17 do Gemini, que le o arquivo inteiro no pre-push.

  {
    id: 'L5',
    category: 'DESIGN_TOKEN',
    title: 'Tamanho de fonte com valor fracionario',
    // Sem gatilho: meio pixel nao e degrau de escala em regime nenhum. Os oito
    // tamanhos fracionarios da interface Flutter (9.5, 10.5, 11.5, 12.5...)
    // nasceram de empurrar o numero ate caber, e nao de uma decisao
    // tipografica.
    appliesTo: (file) => isTs(file) || file.endsWith('.css'),
    test: (line) => {
      const code = stripComments(line);
      return (
        /\bfontSize\s*[:=]\s*\{?\s*\d+\.\d+/.test(code) ||
        /\btext-\[\d+\.\d+(?:px|rem|em)\]/.test(code) ||
        /\bfont-size\s*:\s*\d+\.\d+px/.test(code)
      );
    },
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
    appliesTo: isScreenCode,
    // `&#123456;` e entidade HTML, nao cor; o lookbehind a deixa de fora.
    // `rgb(var(--x))` e `color-mix(...)` leem token e nao casam: so o
    // componente numerico denuncia o literal.
    test: (line) => {
      const code = stripComments(line);
      return (
        /(?<![&\w])#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6})\b/.test(code) ||
        /\b(?:rgba?|hsla?|oklch|oklab)\(\s*\d/.test(code)
      );
    },
    explain:
      'Cor declarada no ponto de uso nao pode ser corrigida de um lugar so, e e\n' +
      '  como o contraste reprovado se espalha. Declare em src/styles.css e leia\n' +
      '  pela classe do token (text-fg, bg-surface, text-positive...) ou por\n' +
      '  var(--token).',
  },
  {
    id: 'L7',
    category: 'DESIGN_TOKEN',
    title: 'Cor da paleta do Tailwind em vez de token semantico',
    requiresTokens: true,
    appliesTo: isScreenCode,
    // So a paleta numerada (`red-500`). `bg-black/50` do veu de dialogo e
    // `bg-white` do polegar do interruptor ficam de fora: nao tem equivalente
    // semantico, como o `Colors.transparent` do Flutter nao tinha.
    test: (line) =>
      /\b(?:text|bg|border(?:-[trblxy])?|ring|ring-offset|outline|fill|stroke|from|via|to|divide|decoration|accent|caret|shadow|placeholder)-(?:slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-(?:50|[1-9]00|950)\b/.test(
        stripComments(line),
      ),
    explain:
      'A paleta do Tailwind nao conhece a semantica financeira desta interface.\n' +
      '  Use os tokens: positive, negative, caution, pending, blocked e os de\n' +
      '  superficie e texto (surface, fg, fg-2, fg-3...).',
  },
  {
    id: 'L8',
    category: 'DESIGN_TOKEN',
    title: 'Espacamento com medida magica',
    requiresTokens: true,
    appliesTo: isScreenCode,
    // So o valor arbitrario em px ou rem. `pl-[2ch]` (recuo por caractere da
    // arvore JSON) e `pb-[env(safe-area-inset-bottom)]` nao casam: ali a
    // medida e de contrato, nao de ritmo.
    test: (line) =>
      /(?<![\w-])-?(?:p|px|py|pt|pb|pl|pr|ps|pe|m|mx|my|mt|mb|ml|mr|ms|me|gap|gap-x|gap-y|space-x|space-y)-\[-?\d+(?:\.\d+)?(?:px|rem)\]/.test(
        stripComments(line),
      ),
    explain:
      'Espacamento fora do grid produz ritmo irregular: dois cartoes vizinhos\n' +
      '  respiram diferente sem razao de conteudo. Use os passos da escala do\n' +
      '  Tailwind (p-1 4px, p-2 8px, p-3 12px, p-4 16px, p-6 24px, p-8 32px).\n' +
      '  Se o valor de que voce precisa nao esta na escala, acrescente-o a\n' +
      '  src/styles.css com um nome: a escala cresce por decisao, nao por\n' +
      '  acumulo.',
  },
  {
    id: 'L9',
    category: 'DESIGN_TOKEN',
    title: 'Padding ou margin numerico em style inline',
    requiresTokens: true,
    appliesTo: isScreenCode,
    // `margin={{ top: 8 }}` do Recharts nao casa: ali o valor e o respiro do
    // SVG dentro do quadro, e o objeto vem depois de `margin=`, nao de
    // `margin:`.
    test: (line) =>
      /\b(?:padding|margin)(?:Top|Bottom|Left|Right|Inline|Block|InlineStart|InlineEnd|BlockStart|BlockEnd)?\s*:\s*['"`]?-?\d/.test(
        stripComments(line),
      ),
    explain:
      'Espaco em style inline escapa da escala e do modo escuro de uma vez so.\n' +
      '  Use a classe do passo (p-4, mt-2, gap-3) no className.',
  },
  {
    id: 'L10',
    category: 'DESIGN_TOKEN',
    title: 'Tamanho de fonte literal fora dos arquivos de tipografia',
    requiresTokens: true,
    appliesTo: (file) => isScreenCode(file) && file !== CHART_TYPE_HOME,
    // O lookahead impede que `fontSize: 10.5` case aqui: o `\d+` guloso pega
    // "10", ve o ponto e falha; ao retroceder para "1" ve o "0" e falha de
    // novo. O caso fracionario e da L5, que roda sempre.
    test: (line) => {
      const code = stripComments(line);
      return (
        /\bfontSize\s*[:=]\s*\{?\s*\d+(?![\d.])/.test(code) ||
        /\btext-\[\d+(?:px|rem|em)\]/.test(code)
      );
    },
    explain:
      'Tamanho declarado no ponto de uso e como a interface Flutter chegou a 20\n' +
      '  tamanhos distintos. Use a escala de src/styles.css: text-caption,\n' +
      '  text-label, text-body-sm, text-body, text-title-sm, text-title -- e,\n' +
      '  no eixo de grafico, axisProps de src/ui/charts/chart-frame.tsx.',
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
    why: 'contem credencial: o BRAPI_TOKEN das ferramentas e as `VITE_*` que o Vite embarca no bundle',
  },
  { pattern: /(^|\/)google-services\.json$/, why: 'credencial do Firebase' },
  { pattern: /(^|\/)serviceAccount.*\.json$/, why: 'chave de conta de servico' },
  { pattern: /\.(p12|jks|keystore|pem)$/, why: 'material criptografico' },
];

/**
 * Varre UMA linha de TypeScript separando codigo, string e comentario.
 *
 * Foi regex antes (`//.*$` primeiro, strings depois), e a regex cortava a linha
 * no `//` de uma URL dentro de string -- `'https://brapi.dev'` sumia com tudo o
 * que vinha depois. A varredura respeita as aspas: `//` e `/*` so abrem
 * comentario fora de string. Aproximacao suficiente para regra de linha -- nao
 * pretende ser um lexer de TypeScript (regex literal e template com `${}`
 * aninhado ficam de fora).
 *
 * `keepStrings` decide o que sobra das strings: vazias (`''`) para as regras de
 * correcao, que julgam codigo; intactas para as de sistema de design, porque na
 * web a cor e o espaco moram em `className="..."` e `style={{ color: '...' }}`.
 */
function scan(line, keepStrings) {
  // Linha de continuacao de bloco `/** ... */`: comentario inteiro. Em codigo
  // formatado pelo Prettier nenhuma linha de codigo abre com `*`, porque o
  // operador binario fica no fim da linha anterior.
  if (/^\s*\*/.test(line)) return '';
  let out = '';
  let quote = null;
  let body = '';
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (quote !== null) {
      if (c === '\\' && i + 1 < line.length) {
        body += c + line[i + 1];
        i++;
        continue;
      }
      if (c === quote) {
        out += quote + (keepStrings ? body : '') + quote;
        quote = null;
        body = '';
        continue;
      }
      body += c;
      continue;
    }
    if (c === "'" || c === '"' || c === '`') {
      quote = c;
      continue;
    }
    if (c === '/' && line[i + 1] === '/') break;
    if (c === '/' && line[i + 1] === '*') {
      const close = line.indexOf('*/', i + 2);
      if (close === -1) break;
      i = close + 1;
      continue;
    }
    out += c;
  }
  // String que nao fecha na linha (template multilinha): o resto e string.
  if (quote !== null) out += quote + (keepStrings ? body : '');
  return out;
}

/**
 * Remove literais de string e comentarios antes de aplicar as regras de
 * correcao.
 *
 * Sem isto, um comentario explicando "nunca use === 0.0" acusaria a si mesmo, e
 * uma mensagem de erro contendo o texto viraria falso positivo.
 */
function stripStringsAndComments(line) {
  return scan(line, false);
}

/** So os comentarios saem: as regras de sistema de design leem as strings. */
function stripComments(line) {
  return scan(line, true);
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

/**
 * Teto de 512 MB para a saida do git. Os 32 MB de antes estouraram em
 * 24/09/2026 (`ENOBUFS`): regerar o backtest e o gabarito juntos da um diff de
 * 33 MB, e o hook caia antes de verificar qualquer coisa, travando o commit no
 * GitHub Desktop. Das regras por linha, so a do marcador de conflito le JSON;
 * as outras filtram pela extensao, e o laco segue barato.
 */
function git(args) {
  return execFileSync('git', args, { encoding: 'utf8', maxBuffer: 512 * 1024 * 1024 });
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

// ---------------------------------------------------------------------------
// Integridade do registro de decisoes
// ---------------------------------------------------------------------------

/**
 * Verificacoes de referencia quebrada em `docs/decisoes/`.
 *
 * SO REFERENCIA QUEBRADA BLOQUEIA. Defasagem -- decisao que o codigo deixou de
 * respeitar, promessa nao cumprida, medicao vencida -- NAO entra aqui, e a
 * distincao e deliberada: um gate que trava o push porque um documento
 * envelheceu e um gate arrancado na primeira semana. Defasagem e semantica e
 * cabe a lente `registro` do conselheiro, que aconselha e nao bloqueia.
 *
 * O escopo tambem e estreito de proposito: so decisao citando decisao, dentro
 * de `docs/decisoes/`. Conferir citacao em prosa pelo repositorio inteiro
 * bloquearia o parecer historico, que cita numeros cuja extracao ainda nao
 * aconteceu -- exatamente o falso positivo que o criterio de admissao deste
 * arquivo proibe.
 */
const DECISIONS_DIR = 'docs/decisoes/';

/** Le a versao EM STAGING do arquivo, nao a do disco. */
function stagedContent(file) {
  try {
    return git(['show', `:${file}`]);
  } catch {
    return null;
  }
}

/**
 * Extrator de lista do frontmatter, por leitura linha a linha.
 *
 * Foi regex antes, e a regex errava justamente no caso mais comum: a lista que
 * fecha o bloco. O terminador exigia uma linha seguinte que nao existe no fim,
 * entao o ultimo campo passava sem ser conferido -- um gate que so verifica os
 * campos do meio e pior que nenhum, porque da confianca falsa.
 */
function listOf(block) {
  const lines = block.split(/\r?\n/);
  return (key) => {
    const out = [];
    let inside = false;
    for (const line of lines) {
      if (new RegExp(`^${key}:\\s*$`).test(line)) {
        inside = true;
        continue;
      }
      if (inside) {
        const item = /^\s+-\s+(.+?)\s*$/.exec(line);
        if (item) {
          out.push(item[1]);
          continue;
        }
        // Qualquer coisa que nao seja item encerra a lista.
        inside = false;
      }
    }
    return out;
  };
}

/** Numeros de decisao que ja tem arquivo, vindos do disco e do staging. */
// As decisoes 0 a 18 nao tem arquivo: moram na tabela congelada do
// PLANO_ARQUITETURA.md, de onde o registro por arquivo so comeca em 19. Sem
// le-las, `substitui: - 14` era acusado de referencia quebrada, e uma decisao
// nova ficava impedida de derrubar formalmente uma antiga -- que e exatamente o
// mecanismo que o registro existe para garantir.
const FROZEN_PLAN = 'PLANO_ARQUITETURA.md';

function frozenPlanDecisions() {
  const numbers = new Set();
  if (!existsSync(FROZEN_PLAN)) return numbers;
  let text;
  try {
    text = readFileSync(FROZEN_PLAN, 'utf8');
  } catch {
    return numbers;
  }
  // Linhas de tabela markdown que abrem com o numero da decisao -- com ou sem
  // negrito, e com ou sem citacao: a tabela grafa `> | **0** |`, `> | 1 |` e
  // `| **18** |`. Sem aceitar os dois, as decisoes 0 a 8 e a 18 ficavam de
  // fora, e a decisao 85 era bloqueada por citar a 18.
  const decisionLine = /^(?:>\s*)?\|\s*(?:\*\*)?(\d{1,2})(?:\*\*)?\s*\|/gm;
  for (const m of text.matchAll(decisionLine)) {
    numbers.add(Number.parseInt(m[1], 10));
  }
  return numbers;
}

function knownDecisions(staged) {
  const numbers = frozenPlanDecisions();
  const register = (name) => {
    const m = /(?:^|\/)(\d{3})-[^/]*\.md$/.exec(name);
    if (m) numbers.add(Number.parseInt(m[1], 10));
  };
  if (existsSync(DECISIONS_DIR)) {
    for (const f of readdirSync(DECISIONS_DIR)) register(f);
  }
  for (const f of staged) register(f);
  return numbers;
}

function checkRegistry(staged) {
  const targets = staged.filter(
    (f) => f.startsWith(DECISIONS_DIR) && f.endsWith('.md') && !f.endsWith('README.md'),
  );
  if (targets.length === 0) return [];

  const known = knownDecisions(staged);
  const findings = [];

  for (const file of targets) {
    const text = stagedContent(file);
    if (text === null) continue;
    const fm = /^---\r?\n([\s\S]*?)\r?\n---/.exec(text);
    if (!fm) {
      findings.push({
        id: 'L12',
        category: 'DECISION_MALFORMED',
        file,
        line: 0,
        title: 'Decisao sem frontmatter',
        evidence: text.split(/\r?\n/)[0] ?? '(vazio)',
        explain:
          'Toda decisao abre com bloco `---` contendo numero, titulo, status,\n' +
          '  origem, data e afeta. Sem ele a decisao nao e enderecavel, que e a\n' +
          '  unica coisa que este registro existe para garantir. Ver\n' +
          '  docs/decisoes/README.md.',
      });
      continue;
    }
    const block = fm[1];
    const items = listOf(block);

    // (a) `afeta` apontando para caminho que nao existe.
    {
      for (const raw of items('afeta')) {
        const filePath = raw.replace(/^["']|["']$/g, '');
        if (!existsSync(filePath)) {
          findings.push({
            id: 'L13',
            category: 'DECISION_BROKEN_PATH',
            file,
            line: 0,
            title: `Decisao governa caminho inexistente: ${filePath}`,
            evidence: raw,
            explain:
              'O campo `afeta` lista os caminhos que a decisao governa, e este\n' +
              '  nao existe no repositorio. Ou o caminho esta errado, ou a decisao\n' +
              '  perdeu objeto e precisa ser revogada explicitamente.',
          });
        }
      }
    }

    // (b) `status: substituida-por-NNN` e `substitui:` apontando para o vazio.
    const cited = new Set();
    const sub = /^status:\s*substituida-por-(\d+)/m.exec(block);
    if (sub) cited.add(Number.parseInt(sub[1], 10));
    for (const raw of items('substitui')) {
      const n = /^(\d+)/.exec(raw);
      if (n) cited.add(Number.parseInt(n[1], 10));
    }
    for (const number of cited) {
      if (!known.has(number)) {
        findings.push({
          id: 'L14',
          category: 'DECISION_DANGLING_REF',
          file,
          line: 0,
          title: `Referencia a decisao inexistente: no ${number}`,
          evidence: `decisao no ${number}`,
          explain:
            `Nao ha docs/decisoes/${String(number).padStart(3, '0')}-*.md. Uma\n` +
            '  decisao que substitui ou revoga outra precisa que a outra exista --\n' +
            '  senao a cadeia de substituicao fica sem inicio e ninguem consegue\n' +
            '  reconstruir por que o rumo mudou.',
        });
      }
    }
  }
  return findings;
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
  const staged = stagedFiles();

  for (const file of staged) {
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

  findings.push(...checkRegistry(staged));

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
