// Executa o oráculo compilado: entrega os pacotes ao Dart e grava o que ele emite.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const [, , compiled, repo, outDir, limitArg, traceDir] = process.argv;
const limit = Number(limitArg ?? '0');
fs.mkdirSync(outDir, { recursive: true });
if (traceDir) fs.mkdirSync(traceDir, { recursive: true });
globalThis.self = globalThis;
globalThis.equisimRead = (name) => fs.readFileSync(path.join(repo, name), 'utf8');
globalThis.equisimLimit = () => limit;
const rows = {};
const traces = {};
let header = null;
globalThis.equisimEmit = (name, text) => {
  if (name === 'header') header = JSON.parse(text);
  else if (name === 'services') globalThis.__services = text;
  else if (name.startsWith('row:')) rows[name.substring(4)] = JSON.parse(text);
  else if (name.startsWith('trace:')) {
    const key = name.substring(6);
    traces[key] = crypto.createHash('sha256').update(text, 'utf8').digest('hex');
    if (traceDir) fs.writeFileSync(path.join(traceDir, key.replace('/', '__') + '.json'), text);
  } else if (name === 'done') {
    for (const [key, sha] of Object.entries(traces)) {
      const [t, a] = key.split('/');
      rows[t][a].rastro = sha;
    }
    fs.writeFileSync(path.join(outDir, 'header.json'), JSON.stringify(header, null, 1));
    fs.writeFileSync(path.join(outDir, 'cascade.json'), JSON.stringify(rows));
    if (globalThis.__services) fs.writeFileSync(path.join(outDir, 'services.json'), globalThis.__services);
    console.log(`oráculo: ${text} ativos`);
  }
};
require(path.resolve(compiled));
