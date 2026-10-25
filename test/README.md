# Testes

Toda a suíte de testes do Equisim mora aqui, separada pelo que ela testa. Fora
desta pasta, o repositório é só código, documentação e dados.

| Pasta | Testa | Código correspondente |
|---|---|---|
| `core/` | o núcleo de domínio: valuation, custo de capital, guardas, carteira, métricas, auditoria — e a pureza do módulo | `src/core/` |
| `parity/` | o núcleo TypeScript contra o gabarito gravado pelo núcleo Dart original, número a número (ver o [README](parity/README.md)) | `src/core/` |
| `data/` | fontes (brapi, Banco Central, Tesouro), rede, cache, repositórios e os pacotes de dados versionados | `src/data/`, `public/assets/` |
| `app/` | a camada de aplicativo: serviços, sessão, estudo, valuations salvos, backtest e textos | `src/app/`, `src/copy/` |
| `audit/` | o barramento do painel de logs e o interceptor de rede | `src/audit/` |
| `ui/` | telas renderizadas, contraste da paleta e unidades da tela de premissas | `src/features/`, `src/ui/`, `src/styles.css` |
| `tool/` | os scripts de medição e validação | `tool/` |
| `fixtures/` | respostas reais das fontes, gravadas, para os testes rodarem sem rede | — |
| `qa_fixtures/` | casos financeiros conferidos, consultados pelo auditor de QA | — |

Arquivos sem o sufixo `.test.ts` (ou `.test.tsx`) não são testes: são apoio
dos testes (`core/fakes.ts`, `core/helpers.ts`, `app/harness.ts`,
`parity/oracle.ts`). A captura de telas para o conselheiro não mora aqui: é
`scripts/capture-screens.ts`, que roda só por `npm run ui:capturar`.

## Como rodar

```bash
npm test                     # a suíte inteira (Vitest)
npx vitest run test/ui       # uma pasta só
npm run test:core            # só o núcleo
npm run test:parity          # só a paridade com o motor Dart original
npm run test:watch           # modo de observação, enquanto se edita
```

O Vitest roda tudo no Node, com o fuso do processo fixado em UTC
(`vitest.config.ts`), para a serialização de data ser a mesma em qualquer
máquina. As telas são renderizadas em `ui/screens.test.tsx` pelo Testing
Library sobre o `jsdom`, um DOM em JavaScript, sem navegador.

O teste de pureza (`core/purity.test.ts`) lê `src/core/` arquivo por arquivo e
confere que nenhum importa o que está fora dele, nem rede, navegador, Firebase
ou módulo do Node.

As ferramentas que leem o cache da validação (`tool/lib/sqlite-cache.ts`) usam
o `node:sqlite`, que pede Node 22.13 ou mais recente; o teste delas
(`tool/sqlite-cache.test.ts`) imprime um aviso de recurso experimental, que é
do Node e não do teste.
