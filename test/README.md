# Testes

Toda a suíte de testes do Equisim mora aqui, separada pelo que ela testa. Fora
desta pasta, o repositório é só código, documentação e dados.

| Pasta | Testa | Código correspondente |
|---|---|---|
| `core/` | o núcleo de domínio: valuation, custo de capital, guardas, carteira, métricas, auditoria — e a pureza do pacote | `packages/equisim_core/lib/` |
| `data/` | fontes (brapi, Banco Central, Tesouro), cache, repositórios e os pacotes de dados versionados | `lib/data/`, `assets/` |
| `ui/` | telas, componentes, textos de tela, tema e controladores | `lib/presentation/`, `lib/views/`, `lib/controllers/` |
| `tool/` | os scripts de medição e validação | `tool/` |
| `fixtures/` | respostas reais das fontes, gravadas, para os testes rodarem sem rede | — |
| `qa_fixtures/` | casos financeiros conferidos, consultados pelo auditor de QA | — |

Arquivos sem o sufixo `_test.dart` não são testes: são apoio dos testes
(`data/fixture_adapter.dart`, `ui/populated_state.dart`) ou a captura de telas
(`ui/golden_capture.dart`, que roda só por `npm run ui:capturar`).

## Como rodar

```bash
flutter test               # a suíte inteira
flutter test test/ui       # uma pasta só
dart test test/core        # só o núcleo, na VM do Dart puro, em segundos
```

Os testes do núcleo não importam nada do Flutter — usam o `test` do Dart —, e é
isso que permite rodá-los também com `dart test`. O teste de pureza
(`core/purity_test.dart`) lê `packages/equisim_core/` pelo caminho explícito e
confere que o pacote lido é mesmo o núcleo.

A pasta se chama `test/`, e não `tests/`, porque é o nome que o Dart define para
os testes de um pacote e o único que o `flutter test` varre sem argumentos.
