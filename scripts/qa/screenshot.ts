/**
 * Suporte a auditoria visual multimodal.
 *
 * Regras de responsividade em codigo (R10-R16) preveem estouro por leitura da
 * arvore de widgets. Isso pega o previsivel -- largura fixa, Row sem Expanded --
 * mas nao pega o que so aparece renderizado: sobreposicao de rotulo de eixo no
 * fl_chart, contraste insuficiente no tema escuro, texto cortado por fonte
 * escalada. Para esses, a captura de tela e a unica evidencia.
 *
 * A API multimodal recebe a imagem como parte inline em base64, junto do
 * texto -- ver o uso de `inlineData` em `providers/api.ts`.
 */
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { basename, extname, join } from 'node:path';

/** Tipos aceitos pela API multimodal do Gemini. */
const MIME_BY_EXT: Record<string, string> = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.heic': 'image/heic',
  '.heif': 'image/heif',
};

/**
 * Teto por imagem. A API aceita mais, porem uma captura de tela de app nao
 * chega perto disso -- passar do teto quase sempre significa arquivo errado
 * (video, PSD, print de monitor 4K inteiro) e so queima token.
 */
const MAX_BYTES = 7 * 1024 * 1024;

/** Imagem no formato inline que a API do Gemini aceita. */
export interface ScreenshotPart {
  inlineData: { mimeType: string; data: string };
}

/** Uma captura carregada, com o que o relatorio precisa exibir. */
export interface LoadedScreenshot {
  /** A imagem, pronta para entrar na requisicao. */
  part: ScreenshotPart;
  /** Nome do arquivo, para o cabecalho do relatorio. */
  label: string;
  /** Tamanho em bytes, ja em base64. */
  bytes: number;
}

/**
 * Carrega capturas de tela e as codifica em base64 inline.
 *
 * @param paths Caminhos das imagens, na ordem em que devem ser enviadas.
 * @returns Uma entrada por caminho, na mesma ordem.
 * @throws Se a extensao nao for suportada (aceitos: PNG, JPEG, WebP, HEIC), se
 *   o arquivo nao existir, ou se exceder o teto de 7 MB. O teto e deliberado:
 *   captura de interface nao chega perto disso, e passar dele quase sempre
 *   significa arquivo errado.
 *
 * So o backend `api` transmite imagem; com `agy` as capturas sao ignoradas.
 */
/**
 * Teto de arquivos por varredura.
 *
 * Nao e limite tecnico: e defesa contra apontar para o diretorio errado. Varrer
 * `~/Imagens` inteiro por engano consumiria a cota do dia antes de qualquer
 * pessoa perceber. Estourar o teto falha com o numero encontrado, para que a
 * pessoa veja que apontou para o lugar errado.
 */
const MAX_SWEEP = 200;

/**
 * Expande diretorios em arquivos de imagem, recursivamente.
 *
 * Caminhos de arquivo passam intactos. Diretorios viram a lista de imagens
 * suportadas dentro deles, em ordem alfabetica -- ordem estavel importa porque
 * o lote e formado por fatiamento, e ordem instavel mudaria a composicao dos
 * lotes entre execucoes.
 */
export function expandScreenshotPaths(paths: string[]): string[] {
  const out: string[] = [];

  for (const path of paths) {
    let stats;
    try {
      stats = statSync(path);
    } catch {
      throw new Error(`Caminho nao encontrado: ${path}`);
    }

    if (!stats.isDirectory()) {
      out.push(path);
      continue;
    }

    const found = sweep(path);
    if (found.length === 0) {
      throw new Error(
        `Nenhuma imagem suportada em ${path}.
` +
          `Aceitos: ${Object.keys(MIME_BY_EXT).join(', ')}`,
      );
    }
    out.push(...found);
  }

  if (out.length > MAX_SWEEP) {
    throw new Error(
      `A varredura encontrou ${out.length} imagens, acima do teto de ` +
        `${MAX_SWEEP}.
Confira se o caminho aponta para o diretorio certo.`,
    );
  }
  return out;
}

function sweep(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...sweep(full));
    } else if (MIME_BY_EXT[extname(entry.name).toLowerCase()]) {
      out.push(full);
    }
  }
  return out.sort();
}

export function loadScreenshots(paths: string[]): LoadedScreenshot[] {
  return paths.map((path) => {
    const ext = extname(path).toLowerCase();
    const mimeType = MIME_BY_EXT[ext];
    if (!mimeType) {
      throw new Error(
        `Formato de imagem nao suportado: "${ext || path}".\n` +
          `Aceitos: ${Object.keys(MIME_BY_EXT).join(', ')}`,
      );
    }

    let stats;
    try {
      stats = statSync(path);
    } catch {
      throw new Error(`Captura de tela nao encontrada: ${path}`);
    }
    if (!stats.isFile()) {
      throw new Error(`Nao e um arquivo: ${path}`);
    }
    if (stats.size > MAX_BYTES) {
      throw new Error(
        `A imagem ${basename(path)} tem ${(stats.size / 1024 / 1024).toFixed(1)} MB, ` +
          `acima do teto de ${MAX_BYTES / 1024 / 1024} MB.\n` +
          'Recorte a area relevante da tela em vez de enviar o monitor inteiro.',
      );
    }

    return {
      part: {
        inlineData: { mimeType, data: readFileSync(path).toString('base64') },
      },
      label: basename(path),
      bytes: stats.size,
    };
  });
}

/**
 * Instrucoes especificas da auditoria visual.
 *
 * Sao separadas do rulebook de codigo porque mudam o tipo de evidencia
 * aceitavel: aqui `evidence` descreve o que esta VISIVEL na imagem, nao um
 * trecho de codigo. Sem isso o modelo tenta citar codigo que nao recebeu.
 */
export function screenshotInstructions(labels: string[]): string {
  return [
    '',
    '## Auditoria visual (multimodal)',
    '',
    `Voce recebeu ${labels.length} captura(s) de tela: ${labels.join(', ')}.`,
    'Elas mostram a interface renderizada do aplicativo.',
    '',
    'Para achados baseados na imagem:',
    '- `file` deve ser o nome do arquivo de imagem;',
    '- `line` deve ser 0;',
    '- `evidence` deve descrever o que esta VISIVEL e ONDE ("rotulos do eixo X',
    '  sobrepostos no canto inferior esquerdo", "valor R$ 1.234.567,89 cortado',
    '  em ...67,8"). NAO cite codigo: voce nao o recebeu junto da imagem;',
    '- `failure_scenario` deve dizer em qual largura o problema ocorre ou',
    '  ocorreria, entre 320, 375, 768, 1024 e 1440 dp.',
    '',
    'Procure especificamente:',
    '- texto truncado, sobreposto ou estourando o container;',
    '- a listra amarela e preta de overflow do Flutter;',
    '- rotulos de eixo de grafico ilegiveis ou colididos;',
    '- contraste insuficiente entre texto e fundo;',
    '- alvos de toque visivelmente menores que a polpa de um dedo;',
    '- valores monetarios formatados de forma inconsistente entre si',
    '  (separador de milhar, casas decimais, simbolo da moeda).',
    '',
    'Se a imagem estiver correta, nao invente achado. Uma tela bem construida',
    'e o caso comum.',
  ].join('\n');
}
