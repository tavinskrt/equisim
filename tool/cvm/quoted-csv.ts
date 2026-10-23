import { readLatin1, splitLines } from '../lib/files';

/**
 * Lê um CSV da CVM: `latin-1`, separador `;`, primeira linha de cabeçalho.
 *
 * **Não usa divisão ingênua por `;`** — os campos podem vir entre aspas com
 * separador dentro, e `DENOM_CIA` traz vírgula e ponto e vírgula em razão
 * social. O analisador respeita aspas (sem aspas dobradas, que a CVM não
 * usa), e a linha com outro número de campos que o cabeçalho é descartada.
 *
 * É o leitor da ponte e da conferência do plano de contas; os pacotes leem
 * pelo `readCvmCsv`, que é o da ingestão.
 */
export function readQuotedCsv(path: string): Record<string, string>[] {
  const rows = splitLines(readLatin1(path));
  if (rows.length === 0) return [];
  const headerRow = fields(rows[0]!);
  const out: Record<string, string>[] = [];
  for (let i = 1; i < rows.length; i++) {
    if (rows[i]!.trim() === '') continue;
    const c = fields(rows[i]!);
    if (c.length !== headerRow.length) continue;
    const row: Record<string, string> = {};
    headerRow.forEach((h, j) => {
      row[h] = c[j]!;
    });
    out.push(row);
  }
  return out;
}

function fields(row: string): string[] {
  const out: string[] = [];
  let current = '';
  let inQuotes = false;
  for (const ch of row) {
    if (ch === '"') {
      inQuotes = !inQuotes;
    } else if (ch === ';' && !inQuotes) {
      out.push(current);
      current = '';
    } else {
      current += ch;
    }
  }
  out.push(current);
  return out;
}
