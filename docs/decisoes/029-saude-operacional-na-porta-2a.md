---
numero: 29
titulo: A saúde operacional proíbe normalizar a base para cima, e a decisão 25 se encerra
status: aceita
origem: orientador
data: 2026-09-07
citacao: >
  O filtro de saúde operacional (queda > 50% de Lucro ou EBITDA no triênio
  recente) deve atuar também na normalização da base na Porta 2a. Ativos
  reprovados no teste de saúde operacional ficam proibidos de receber fator de
  normalização de base para cima (fator travado em f <= 1,00). Aprovada a
  inclusão de docs/validacao/ no EXCLUDED de collect.ts. Substitua a igualdade
  estrita por comparação com tolerância de ponto flutuante. Manter o registro
  formal da limitação da brapi sobre netIncome de instituições financeiras. Com
  essas alterações finais, a Decisão 025 pode ter seu status transicionado para
  'cumprida'.
afeta:
  - packages/equisim_core/lib/src/services/valuation/growth_guards.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - scripts/qa/collect.ts
  - tool/validation/out_of_sample.dart
  - docs/validacao/limitacoes.md
substitui: []
---

## Contexto

A [decisão 28](028-travas-de-ciclo-saturacao-e-saude.md) resolveu SUZB3 e MBRF3 e
tirou a QUAL3 da vantagem competitiva residual. **Não resolveu o potencial da
QUAL3**, que ficou em +477,3% — o maior do universo. A §14.5 do
[refinamento](../refinamento-do-valuation.md) registrou por quê: o número não
vinha da perpetuidade, vinha da **base**. A mediana de ROIC de oito anos ainda
carregava os exercícios anteriores à queda, e a Porta 2a normalizava a base
corrente por 2,10x na direção dela.

Barrar só o *moat* tratava metade do sintoma. A afirmação que faltava é anterior:
quando uma empresa perde mais da metade do resultado em três anos, a janela do
ciclo **deixou de descrevê-la**, e usá-la para levantar a base atribui a ela um
retorno que não vai se repetir.

Restavam ainda três pendências de governança: o escopo do gate diluído por
artefato gerado, um achado de linter sobre comparação de ponto flutuante, e o
encerramento formal da decisão 25.

## Decisão

**1. A saúde operacional trava o teto do fator de normalização em 1,00.** O mesmo
teste que barra o *moat* — queda de lucro ou EBITDA acima de 50% no triênio
recente — passa a valer na Porta 2a. Ativo reprovado nele não recebe base
normalizada **para cima**.

**Só o teto cai; o piso de 0,33 continua valendo.** Quem deteriorou e ainda assim
teve um exercício acima do ciclo é normalizado para baixo normalmente, que é a
direção conservadora. O parâmetro deixa de se chamar `moatMaxProfitDecline` e
passa a `maxOperationalDecline`, porque agora governa duas guardas.

**2. `docs/validacao/` sai do escopo da auditoria.** Os dumps do executor de
validação são saída gerada por `dart run tool/validate.dart`, não código de
produção. O `validacao_fora_da_amostra.json` tem 162 KB e entrava por `*.json`:
numa auditoria de diff ele consumia a atenção do modelo inteira, e o veredito
saiu descrevendo o dump sem tocar no código que mudou junto.

**3. A comparação das taxas de desconto passa a ter tolerância.**
`(desconto − descontoTerminal).abs() > 1e-7` no lugar da desigualdade estrita. A
banda é muito menor que qualquer diferença de taxa que valha ser declarada e
maior que qualquer ruído de IEEE-754.

**4. A [decisão 25](025-reconstrucao-do-motor-de-avaliacao.md) passa a
`status: cumprida`.** As quatro condições de encerramento que ela declara foram
conferidas uma a uma:

| Condição | Como foi verificada |
|---|---|
| Roteamento coberto por teste | Porta 0, Porta 2 e Porta 3 já tinham grupo próprio; **a Porta 1 não tinha**, e o grupo foi escrito nesta rodada — inclusive o caso que a isola de fato, com NOPAT positivo para que a via da firma seja a alternativa real |
| Base acionária conciliada | `FundamentalsSnapshot.reconciledShares` arbitra por `N = lucro ÷ LPA`, com teste sobre o caso MILS3 |
| Validação fora da amostra sem exceção não tratada | 373 papéis, toda saída nomeada; o balde `sem exercício` não disparava por um `não` a mais no teste da mensagem, e foi corrigido |
| Curva de desconto homologada | Homologada pelo orientador na citação acima |

Marcar o status **não edita a decisão 25**: o corpo dela segue imutável, e o que
terminou é o trabalho que ela autorizava. A superfície do `afeta` dela volta à
preservação.

## Consequências aceitas

- **A trava alcança 13 ativos, e quatro deles são cíclicos pesados.** VALE3,
  GGBR4, GOAU4 e DXCO3 reprovam na saúde porque o resultado de commodity caiu
  mais de 80% do pico de 2022 para 2025 — que é um vale de ciclo, não
  deterioração de modelo de negócio. **A determinação previa não penalizar
  empresas cíclicas normais, e nessa medida ela penaliza.** Fica registrado como
  efeito medido, não como acerto: a VALE3 saiu de −14,5% para −70,3% de
  potencial, e a GGBR4 para −92,7%.

- **As duas regras se cruzam justamente onde a decisão 28 tinha atuado.** A
  precedência do ciclo em commodity existe para forçar a convergência à mediana;
  a trava de saúde a proíbe na direção de cima, que é a que importa num vale. Um
  recorte que isentasse o setor cíclico da trava — ou que medisse a queda contra
  a mediana do ciclo em vez do exercício de três anos antes — resolveria, e não
  foi adotado aqui porque é decisão nova.

- **A distribuição inteira desceu.** A mediana do potencial foi de −39,3% para
  −46,4% e o p75 de −8,8% para −19,5%. A trava não é cirúrgica sobre a QUAL3: ela
  desloca o nível de todo o conjunto de treze, e o efeito agregado é
  conservador.

- **O que se pretendia foi obtido.** A QUAL3 saiu de +477,3% para **+68,0%**, e o
  máximo do universo passou a ser +336,4%, da MOVI3 — que não é caso de
  normalização, tem fator 1,00.

- **A alternativa descartada** era tratar a QUAL3 pela Porta 0, excluindo do
  universo quem deteriorou. Recusada porque a Porta 0 filtra quem não é
  analisável, e uma empresa em queda **é** analisável: o que ela não sustenta é
  uma base normalizada para cima, que é exatamente o que esta decisão nega.

- **Com a decisão 25 cumprida, o motor volta à preservação.** Divergência na
  cascata de avaliação volta a ser dívida a inventariar, e não tarefa acionável;
  mudança de método ali passa a exigir decisão nova que o declare.
