# 8. Como o motor é verificado e validado

Duas perguntas diferentes: **o código faz o que diz?** (verificação) e **o que
ele diz serve?** (validação). Estudo: [guia, cap. 7](../estudo/07-como-o-motor-foi-validado.md).

---

## 8.1 Verificação: o código faz o que diz

| Mecanismo | O que confere | Onde | Quando roda |
|---|---|---|---|
| **Testes do núcleo** | cada regra, com casos de borda; identidade entre as rotas da firma e do acionista; pureza (zero dependências); determinismo | [test/core/](../../test/core/) (930 testes em 03/11/2026) | a cada mudança (`npm test`; só o núcleo: `npm run test:core`) |
| **Paridade com o motor Dart** | o núcleo TypeScript contra o gabarito gravado pelo núcleo Dart antes da remoção: 371 ativos, treze montagens, igualdade exata de número, texto e rastro | [test/parity/](../../test/parity/) | a cada mudança (`npm run test:parity`) |
| **Testes do aplicativo** | dados, cache, rede, auditoria, telas, worker de avaliação e ferramentas | [test/data/](../../test/data/), [test/app/](../../test/app/), [test/audit/](../../test/audit/), [test/ui/](../../test/ui/) e [test/tool/](../../test/tool/) (372 testes) | a cada mudança (`npm test`) |
| **Gate local** | regras determinísticas: segredo em staging, `DateTime.now()` direto em caminho de cálculo, arquivo novo de registro de decisões | [scripts/qa-local.mjs](../../scripts/qa-local.mjs), `.githooks/pre-commit` | todo commit |
| **Auditor** | defeito de correção em linha nova (precisão monetária, convenções brasileiras, arredondamento, domínio); só FAIL bloqueia | [scripts/qa/rules.ts](../../scripts/qa/rules.ts), `npm run qa:gemini` | todo push, e antes de concluir tarefa |
| **Conselheiro (sete lentes)** | relação entre coisas: documentação × código, rótulo × tela, premissa × implementação; nunca bloqueia | [scripts/qa/advisor/](../../scripts/qa/advisor/), `npm run conselho` | depois de mudanças |
| **Gabarito da cascata** | a saída completa (resultado **e** rastro) de 376 ativos em nove montagens, sobre entrada congelada; conferido ao bit | [tool/cascade-golden.ts](../../tool/cascade-golden.ts), [gabarito_cascata.json](../validacao/gabarito_cascata.json) | a cada mudança de método |
| **Cálculo do usuário** | sem troca, a tela Simular minhas premissas dá o preço do motor bit a bit em cada avaliado; taxa mais alta, preço mais baixo; os degraus de "onde você discorda" somam a diferença; a taxa que o preço de hoje supõe devolve o preço de mercado | [tool/manual-calculation-check.ts](../../tool/manual-calculation-check.ts), [manual-valuation.test.ts](../../test/core/manual-valuation.test.ts) | a cada mudança de método ou da tela |
| **Conferência cruzada** | recálculo independente em Python de métricas e inferência | [conferencia_python.md](../validacao/conferencia_python.md), [conferencia_inferencia.md](../validacao/conferencia_inferencia.md) | quando o método muda |
| **Casos de estudo** | os números de cinco avaliações, reconferidos linha a linha | [tool/study-cases.ts](../../tool/study-cases.ts), [tool/tabelas_casos.py](../../tool/tabelas_casos.py) | quando o motor muda |

As regras do projeto para agentes de codificação (QA obrigatório, pureza do
núcleo, determinismo, credenciais) estão no [CLAUDE.md](../../CLAUDE.md).

---

## 8.2 Validação: o que o motor diz serve

O motor é tratado como **motor de referência** quando três condições valem ao
mesmo tempo:

| | Condição | Medida | Estado |
|---|---|---|---|
| **R1** | Nenhum defeito conhecido | nenhum defeito de correção aberto; o que o motor ainda não resolve fica declarado como limitação | as limitações conhecidas e o que o projeto faz com cada uma estão em [limitacoes.md](../validacao/limitacoes.md) |
| **R2** | Incerteza calibrada | faixa de 80% com cobertura fora da amostra a até 5 p.p., em 12 e 36 meses, sem viés de sobrevivência | **atingido**: 79,0% e 79,1%, remedidos em 03/11/2026 ([cobertura_banda.md](../validacao/cobertura_banda.md)) |
| **R3** | Habilidade testada, com o poder declarado | potencial condicionado ao book-to-market em 36 meses, pelo critério fixado antes de medir (`t` de Fama-MacBeth corrigido pela sobreposição acima do crítico simulado, e Newey-West acima de 2), com o poder do teste declarado | **atingido no sentido de "testada, com o poder declarado"** (não no de "comprovada"): `t` corrigido de 0,25 contra 2,70; efeito mínimo detectável de 0,48 contra 0,034 medido, em 03/11/2026 (nem o book-to-market sozinho passa: `t` de 2,15) ([poder_r3.md](../validacao/poder_r3.md), [habilidade_trimestral.md](../validacao/habilidade_trimestral.md)) |

### O instrumento

| Peça | Como | Evidência |
|---|---|---|
| Coortes | o último dia de cada trimestre de 2018 a 2025, com a montagem do aplicativo **naquela data** (dados *point-in-time*, curva e beta da data) | [tool/backtest-valuation.ts](../../tool/backtest-valuation.ts); [backtest_trimestral.json](../validacao/backtest_trimestral.json) |
| Sobrevivência | as deslistadas entram, com preço do COTAHIST | [b3_deslistadas.md](../validacao/b3_deslistadas.md) |
| Contagem de ações na data | a do Formulário de Referência, conferida contra o salto do preço: a correção de formulário sem o salto correspondente sai | [checked-count.ts](../../tool/cohorts/checked-count.ts) |
| Prêmio de mercado | o de cada coorte: a média de dez anos do prêmio implícito só com os trimestres até a data dela (0,91% a 1,62%) | [premio_implicito.md](../validacao/premio_implicito.md) |
| Desfecho | retorno total (preço + proventos) em 12 e 36 meses | [proventos.md](../validacao/proventos.md); os proventos dos emissores com barra no nome entram |
| Custos | tarifa e meio spread nas duas pontas; não mudam o veredito | [custos_transacao.md](../validacao/custos_transacao.md) |
| Estatística | Fama-MacBeth; `t` corrigido pela sobreposição, com crítico por simulação (splitmix64, semente fixa, igual em TypeScript, no núcleo Dart que o precedeu e em Python) e Newey-West > 2 | [conferencia_inferencia.md](../validacao/conferencia_inferencia.md), [poder_r3.md](../validacao/poder_r3.md) |

### A réplica selada

As previsões de cada trimestre fechado são seladas com o código do dia e o hash
do git de cada arquivo; a leitura só é permitida quando os 36 meses passarem
(`tool/c7-reading.ts` recusa antes). **O motor pré-registrado continua sendo o
núcleo Dart do commit selado**: `tool/c7-preregistered.ts` o roda naquele
commit, com o SDK do Flutter no PATH, e a impressão digital do núcleo é
procurada nas duas árvores, a Dart da selagem e a TypeScript atual. Coortes seladas: 31/12/2025, 31/03/2026 e
30/06/2026; a próxima é 30/09/2026. É o único caminho para "habilidade
comprovada" ([validacao/c7/](../validacao/c7/)).

### O que a validação mostrou, em uma frase cada

- O motor é **mais pessimista que o mercado** de forma sistemática (upside
  mediano de −36,2% nos 121 avaliados com os dados de 14/09/2026, remedido em
  03/11/2026), mesmo com
  o prêmio de mercado tirado do preço da bolsa ([premio_implicito.md](../validacao/premio_implicito.md)).
- A **faixa calibrada** cumpre o que promete (R2).
- A **ordenação** não foi comprovada, e o teste não teria poder para comprová-la
  com a série disponível (R3; [poder_r3.md](../validacao/poder_r3.md)).
- Os **cenários** são sensibilidade: contiveram 8% dos resultados ([cenario.md](../validacao/cenario.md)).
