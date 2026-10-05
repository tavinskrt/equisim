# 8. Como o motor é verificado e validado

Duas perguntas diferentes: **o código faz o que diz?** (verificação) e **o que
ele diz serve?** (validação). Estudo: [guia, cap. 7](../estudo/07-como-o-motor-foi-validado.md).

---

## 8.1 Verificação: o código faz o que diz

| Mecanismo | O que confere | Onde | Quando roda |
|---|---|---|---|
| **Testes do núcleo** | cada regra, com casos de borda; identidade entre as rotas da firma e do acionista; pureza (zero dependências); determinismo | [packages/equisim_core/test/](../../packages/equisim_core/test/) (≈ 850 testes) | a cada mudança (`dart test`) |
| **Testes do aplicativo** | dados, cache, telas, isolate | [test/](../../test/) (≈ 485 testes) | a cada mudança (`flutter test`) |
| **Gate local** | regras determinísticas: segredo em staging, `DateTime.now()` direto em caminho de cálculo, referência quebrada no registro | [scripts/qa-local.mjs](../../scripts/qa-local.mjs), `.githooks/pre-commit` | todo commit |
| **Auditor** | defeito de correção em linha nova (precisão monetária, convenções brasileiras, arredondamento, domínio); só FAIL bloqueia | [scripts/qa/rules.ts](../../scripts/qa/rules.ts), `npm run qa:gemini` | todo push, e antes de concluir tarefa |
| **Conselheiro (sete lentes)** | relação entre coisas: decisão × código, rótulo × tela, premissa × implementação; nunca bloqueia | [scripts/qa/advisor/](../../scripts/qa/advisor/), `npm run conselho` | depois de mudanças |
| **Gabarito da cascata** | a saída completa (resultado **e** rastro) de 376 ativos em nove montagens, sobre entrada congelada; conferido ao bit | [tool/gabarito_cascata.dart](../../tool/gabarito_cascata.dart), [gabarito_cascata.json](../validacao/gabarito_cascata.json) | a cada mudança de método |
| **Conferência cruzada** | recálculo independente em Python de métricas e inferência | [conferencia_python.md](../validacao/conferencia_python.md), [conferencia_inferencia.md](../validacao/conferencia_inferencia.md) | quando o método muda |
| **Casos de estudo** | os números de cinco avaliações, reconferidos linha a linha | [tool/casos_de_estudo.dart](../../tool/casos_de_estudo.dart), [tool/tabelas_casos.py](../../tool/tabelas_casos.py) | quando o motor muda |

As regras do projeto para agentes de codificação (QA obrigatório, pureza do
núcleo, determinismo, credenciais) estão no [CLAUDE.md](../../CLAUDE.md).

### Defeitos achados ao escrever esta documentação

Conferir o código linha a linha contra o que a documentação ia afirmar achou
sete defeitos, todos registrados no [plano](../plano-motor-de-referencia.md):

| Item | Defeito | Estado |
|---|---|---|
| B35 | o rastro da via da firma descrevia o desconto ao WACC, e a conta é ao Ke; a soma mostrada não era a soma das parcelas | corrigido |
| B36 | o cenário de desconto não alcançava o caminho de Ke resolvido na via do acionista | corrigido |
| B37 | sem resolução (bancos), a taxa não seguia a curva ano a ano, embora o aviso dissesse que seguia | corrigido; financeiros −0,4% a −0,5% |
| B38 | o cenário "Otimista" soma crescimento, que destrói valor quando o retorno fica abaixo do custo; sai abaixo do "Pessimista" em 17 de 77 (14 de 90 com o prêmio da decisão 142 e a base de patrimônio da 146) | aguarda decisão |
| B39 | aviso e rastro diziam que a vantagem residual segue barrada pela trava de saúde, regra retirada na decisão 36 | corrigido |
| B40 | o aviso de contagens discordantes nomeava a contagem do valor de mercado quando a ponte usava a oficial | corrigido |
| B41 | a mediana dos pares incluía a própria companhia (e cada classe como um par) | corrigido; pacote de múltiplos refeito |

---

## 8.2 Validação: o que o motor diz serve

O objetivo "motor de referência" tem três condições
([plano](../plano-motor-de-referencia.md), "Os dois objetivos"):

| | Condição | Medida | Estado |
|---|---|---|---|
| **R1** | Nenhum defeito conhecido | nenhum item de defeito com `R1` aberto no plano | ver o plano |
| **R2** | Incerteza calibrada | faixa de 80% com cobertura fora da amostra a até 5 p.p., em 12 e 36 meses, sem viés de sobrevivência | **atingido**: 79,7% e 78,7%, remedidos em 02/10/2026 ([cobertura_banda.md](../validacao/cobertura_banda.md); decisões 100 e 124) |
| **R3** | Habilidade testada, com o poder declarado | potencial condicionado ao book-to-market em 36 meses, pelo critério fixado antes (decisão 96), com o poder do teste declarado | **atingido na definição da decisão 140**: `t` corrigido de 0,05 contra 2,70; efeito mínimo detectável de 0,70 contra 0,010 medido, em 02/10/2026 (nem o book-to-market sozinho passa: `t` de 2,40) ([poder_r3.md](../validacao/poder_r3.md), [habilidade_trimestral.md](../validacao/habilidade_trimestral.md)) |

### O instrumento

| Peça | Como | Evidência |
|---|---|---|
| Coortes | o último dia de cada trimestre de 2018 a 2025, com a montagem do aplicativo **naquela data** (dados *point-in-time*, curva e beta da data) | [tool/backtest_valuation.dart](../../tool/backtest_valuation.dart); [backtest_trimestral.json](../validacao/backtest_trimestral.json) |
| Sobrevivência | as deslistadas entram, com preço do COTAHIST | decisão 93, [b3_deslistadas.md](../validacao/b3_deslistadas.md) |
| Contagem de ações na data | a do Formulário de Referência, conferida contra o salto do preço: a correção de formulário sem o salto correspondente sai (B43) | decisão 143; [contagem_conferida.dart](../../tool/coortes/contagem_conferida.dart) |
| Prêmio de mercado | o de cada coorte: a média de dez anos do prêmio implícito só com os trimestres até a data dela (0,91% a 1,62%) | decisão 142 |
| Desfecho | retorno total (preço + proventos) em 12 e 36 meses | decisão 89; proventos dos emissores com barra no nome desde a decisão 144 |
| Custos | tarifa e meio spread nas duas pontas; não mudam o veredito | decisão 126 |
| Estatística | Fama-MacBeth; `t` corrigido pela sobreposição, com crítico por simulação (splitmix64, semente fixa, igual em Dart e Python) e Newey-West > 2 | decisão 96 |

### A réplica selada (C7)

As previsões de cada trimestre fechado são seladas com o código do dia e o hash
do git de cada arquivo; a leitura só é permitida quando os 36 meses passarem
(`tool/c7_leitura.dart` recusa antes). Coortes seladas: 31/12/2025, 31/03/2026 e
30/06/2026; a próxima é 30/09/2026. É o único caminho para "habilidade
comprovada" (decisões 133, 138 e 140; [validacao/c7/](../validacao/c7/)).

### O que a validação mostrou, em uma frase cada

- O motor é **mais pessimista que o mercado** de forma sistemática (upside
  mediano de −37% com os dados de 14/09/2026, remedido em 02/10/2026), mesmo com
  o prêmio de mercado tirado do preço da bolsa (decisão 142).
- A **faixa calibrada** cumpre o que promete (R2).
- A **ordenação** não foi comprovada, e o teste não teria poder para comprová-la
  com a série disponível (R3, decisão 140).
- Os **cenários** são sensibilidade: contiveram 8% dos resultados (decisão 92).
