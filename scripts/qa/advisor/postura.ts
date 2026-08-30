/**
 * POSTURA: como o conselheiro trata o que ja existe.
 *
 * Duas posturas, incompativeis por natureza:
 *
 *   PRESERVACAO   o codigo funciona, ninguem pediu para mexer, e o risco de
 *                 tocar supera o ganho. Divergencia e divida a inventariar, e
 *                 so a REGRESSAO -- o que passou a divergir depois da decisao
 *                 -- vira tarefa.
 *
 *   RECONSTRUCAO  decidiu-se refazer aquela superficie. Dentro da fronteira,
 *                 tudo e acionavel, e "divida herdada" deixa de ser categoria
 *                 util: a decisao de refazer ja foi tomada.
 *
 * A FRONTEIRA NAO E CONFIGURACAO -- E DECISAO REGISTRADA. Uma postura de
 * reconstrucao existe quando ha um arquivo em `docs/decisoes/` com
 * `postura: reconstrucao`, `status: aceita` e os caminhos em `afeta`. Isso nao
 * e cerimonia: sem data e sem autor, nao ha como saber depois por que meio
 * repositorio virou "acionavel", nem quando aquilo deveria ter fechado.
 *
 * E ela e TEMPORARIA. Cumprida a EAP correspondente, a decisao recebe
 * `status: cumprida`, a superficie volta a preservacao, e a linha de base da
 * lente e redesenhada a partir do estado novo.
 */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

/** Uma fronteira de reconstrucao aberta. */
export interface Fronteira {
  /** Numero da decisao que a abriu. */
  numero: number;
  titulo: string;
  data: string;
  /** Caminhos sob reconstrucao, relativos a raiz. */
  escopo: string[];
}

/**
 * Leitor de frontmatter suficiente para `docs/decisoes/`.
 *
 * Nao e YAML e nao pretende ser -- entende escalar e lista de `- `. Um formato
 * que exigisse mais ja seria formato demais para um registro escrito a mao.
 */
function lerCampos(texto: string): Record<string, string | string[]> {
  const m = /^---\r?\n([\s\S]*?)\r?\n---/.exec(texto);
  if (!m) return {};

  const campos: Record<string, string | string[]> = {};
  let lista: string[] | null = null;

  for (const linha of (m[1] ?? '').split(/\r?\n/)) {
    const item = /^\s+-\s+(.+?)\s*$/.exec(linha);
    if (item && lista !== null) {
      lista.push((item[1] ?? '').replace(/^["']|["']$/g, ''));
      continue;
    }
    const par = /^([a-z_]+):\s*(.*)$/i.exec(linha);
    if (!par) continue;

    const chave = par[1] ?? '';
    const valor = (par[2] ?? '').trim();
    if (valor === '' || valor === '[]' || valor === '[ ]') {
      // Guarda a referencia da lista em vez de reindexar a cada item: e o que
      // dispensa a checagem de tipo a cada linha e evita que um `- ` orfao,
      // antes de qualquer chave, seja anexado a coisa nenhuma.
      const nova: string[] = [];
      campos[chave] = nova;
      lista = valor === '' ? nova : null;
    } else {
      campos[chave] = valor;
      lista = null;
    }
  }
  return campos;
}

/**
 * Fronteiras de reconstrucao abertas no repositorio.
 *
 * So `status: aceita` conta. Uma decisao `cumprida` ou `revogada` documenta uma
 * reconstrucao que ja aconteceu -- reabri-la por engano faria a lente tratar
 * como acionavel uma superficie que voltou a ser preservada.
 */
export function fronteirasAbertas(root: string): Fronteira[] {
  const dir = join(root, 'docs', 'decisoes');
  if (!existsSync(dir)) return [];

  const out: Fronteira[] = [];
  for (const arquivo of readdirSync(dir).filter((f) => /^\d{3}-.*\.md$/.test(f))) {
    const campos = lerCampos(readFileSync(join(dir, arquivo), 'utf8'));
    if (campos.postura !== 'reconstrucao') continue;
    if (campos.status !== 'aceita') continue;

    const escopo = Array.isArray(campos.afeta) ? campos.afeta : [];
    if (escopo.length === 0) continue; // fronteira sem escopo nao e fronteira

    out.push({
      numero: Number(campos.numero),
      titulo: String(campos.titulo ?? '(sem titulo)'),
      data: String(campos.data ?? ''),
      escopo,
    });
  }
  return out.sort((a, b) => a.numero - b.numero);
}

/**
 * Bloco injetado na instrucao de sistema quando ha reconstrucao aberta.
 *
 * Devolve string vazia quando nao ha -- e o caso normal, e o silencio importa:
 * um bloco dizendo "nao ha reconstrucao aberta" so gastaria contexto para
 * lembrar o modelo de nao fazer o que ele nao ia fazer.
 */
export function blocoDePostura(fronteiras: Fronteira[]): string {
  if (fronteiras.length === 0) return '';

  const linhas = [
    '',
    '## Postura: RECONSTRUCAO DECLARADA',
    '',
    'Ha reconstrucao aberta sobre parte deste repositorio. Dentro da fronteira',
    'abaixo, e SOMENTE dentro dela:',
    '',
    '- A distincao entre divida herdada e regressao esta SUSPENSA. Nao adie',
    '  tensao alegando que o codigo "ja era assim" -- a decisao de refazer ja',
    '  foi tomada, e e por isso que a fronteira existe.',
    '- Proposta de mudanca estrutural e bem-vinda, inclusive mover elemento de',
    '  lugar, fundir telas ou renomear rotulo de navegacao.',
    '',
    'FORA da fronteira, a preservacao continua valendo INTEGRALMENTE: ali o que',
    'existe e para ser respeitado, e so regressao vira tarefa. Nao aproveite a',
    'reconstrucao de uma superficie para propor reescrita de outra.',
    '',
    'Fronteira aberta:',
  ];

  for (const f of fronteiras) {
    linhas.push(`  decisao no ${f.numero} (${f.data}) -- ${f.titulo}`);
    for (const caminho of f.escopo) linhas.push(`    ${caminho}`);
  }
  linhas.push('');
  return linhas.join('\n');
}
