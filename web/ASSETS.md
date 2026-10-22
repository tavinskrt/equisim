# Arquivos do cache local na web

O aplicativo guarda o que busca das fontes num banco SQLite local (Drift). No
build web, esse banco roda em WebAssembly dentro de um *web worker*, e precisa
de dois arquivos servidos junto com o aplicativo. **O build não os gera**: eles
ficam versionados nesta pasta.

| Arquivo | De onde vem | Tem de casar com |
|---|---|---|
| `sqlite3.wasm` | release do [sqlite3.dart](https://github.com/simolus3/sqlite3.dart/releases) da mesma versão do pacote | pacote `sqlite3` do `pubspec.lock` (hoje 3.5.2) |
| `drift_worker.js` | cache do pub: `hosted/pub.dev/drift-<versão>/drift_worker.js` | pacote `drift` do `pubspec.lock` (hoje 2.34.3) |

Quem os carrega é o `cacheDatabaseProvider`
([providers.dart](../lib/di/providers.dart)), pelos nomes `sqlite3.wasm` e
`drift_worker.js`.

**Sem eles, nada quebra:** o provider devolve `null`, avisa no console, e o
aplicativo busca tudo da rede a cada consulta — mais lento, e sem a garantia de
que a mesma consulta devolve o mesmo dado. Cache é otimização, não requisito.

**Ao atualizar `drift` ou `sqlite3`**, troque os dois arquivos pelas versões que
o novo `pubspec.lock` fixar. Versões desencontradas fazem o banco falhar na
abertura (e o aplicativo cair no modo sem cache):

```bash
cp "$LOCALAPPDATA/Pub/Cache/hosted/pub.dev/drift-<versao>/drift_worker.js" web/
```
