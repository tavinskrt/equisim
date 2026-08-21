# Binários do Drift para o alvo web

Estes dois arquivos **não são gerados pelo build** — precisam ser colocados aqui
manualmente, e suas versões têm de casar com as do `pubspec.lock`.

| Arquivo | Origem | Versão |
|---|---|---|
| `sqlite3.wasm` | [releases do `sqlite3.dart`](https://github.com/simolus3/sqlite3.dart/releases/tag/sqlite3-3.5.2) | pacote `sqlite3` 3.5.2 |
| `drift_worker.js` | cache do pub: `.../hosted/pub.dev/drift-2.34.3/drift_worker.js` | pacote `drift` 2.34.3 |

## Para que servem

O cache local usa SQLite. Em plataformas nativas isso vem do
`sqlite3_flutter_libs`; no navegador, o SQLite roda compilado para WebAssembly e
o Drift o executa num *web worker*. Sem os dois arquivos servidos junto da
aplicação, o banco não abre.

## O que acontece sem eles

Nada quebra. O `cacheDatabaseProvider` degrada para `null` e a aplicação passa a
buscar tudo da rede a cada consulta — mais lenta, e sem a reprodutibilidade que
o cache garante. Foi decisão de projeto: cache é otimização, não requisito.

## Ao atualizar `drift` ou `sqlite3`

Refaça os dois:

```bash
cp "$LOCALAPPDATA/Pub/Cache/hosted/pub.dev/drift-<versao>/drift_worker.js" web/
```

E baixe o `sqlite3.wasm` da release correspondente à versão do pacote `sqlite3`
que o `pubspec.lock` fixar. Versões desencontradas entre os dois arquivos fazem
o banco falhar na abertura.
