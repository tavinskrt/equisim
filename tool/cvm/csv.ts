// Leitor dos CSVs de dados abertos da CVM com campo aspado.
import { readFileSync } from 'node:fs';

/**
 * CSV da CVM: `;`, aspas duplas, e quebra de linha dentro de campo aspado —
 * o quadro de intangíveis tem 24.543 linhas físicas e 24.540 registros.
 *
 * O arquivo vem em ISO-8859-1; o `latin1` do `Buffer` é esse mapeamento exato
 * (o `TextDecoder('latin1')` do navegador seria o Windows-1252).
 */
export function readCvmCsv(path: string): Record<string, string>[] {
  const text = readFileSync(path).toString('latin1');
  const records: string[][] = [];
  let field = '';
  let row: string[] = [];
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i]!;
    if (quoted) {
      if (c === '"') {
        if (i + 1 < text.length && text[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          quoted = false;
        }
      } else {
        field += c;
      }
    } else if (c === '"') {
      quoted = true;
    } else if (c === ';') {
      row.push(field);
      field = '';
    } else if (c === '\n' || c === '\r') {
      if (c === '\r' && i + 1 < text.length && text[i + 1] === '\n') i++;
      row.push(field);
      field = '';
      if (row.length > 1 || row[0]!.length > 0) records.push(row);
      row = [];
    } else {
      field += c;
    }
  }
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    records.push(row);
  }
  if (records.length === 0) return [];
  const header = records[0]!;
  return records.slice(1).map((r) => {
    const out: Record<string, string> = {};
    for (let k = 0; k < header.length && k < r.length; k++) out[header[k]!] = r[k]!;
    return out;
  });
}
