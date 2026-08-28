/**
 * Suporte a auditoria visual multimodal.
 *
 * Regras de responsividade em codigo (R10-R16) preveem estouro por leitura da
 * arvore de widgets. Isso pega o previsivel -- largura fixa, Row sem Expanded --
 * mas nao pega o que so aparece renderizado: sobreposicao de rotulo de eixo no
 * fl_chart, contraste insuficiente no tema escuro, texto cortado por fonte
 * escalada. Para esses, a captura de tela e a unica evidencia.
 *
 * Disponivel apenas no backend `api`: a agentapi do Antigravity recebe prompt
 * de texto, sem canal para anexar imagem.
 */
import { readFileSync, statSync } from 'node:fs';
import { basename, extname } from 'node:path';

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

export interface ScreenshotPart {
  inlineData: { mimeType: string; data: string };
}

export interface LoadedScreenshot {
  part: ScreenshotPart;
  label: string;
  bytes: number;
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
