---
numero: 102
titulo: Nenhuma avaliação muda de via, e a via da firma avalia o capital próprio pelo fluxo do acionista derivado
status: aceita
origem: voce
data: 2026-09-16
citacao: >
  Seus itens de escopo para esta rodada são B1 (siga sua recomendação), B10 e
  B13.
afeta:
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/services/valuation/dcf.dart
  - packages/equisim_core/lib/src/services/valuation/cost_of_capital.dart
  - packages/equisim_core/lib/src/services/valuation/growth_guards.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - packages/equisim_core/lib/src/entities/valuation.dart
  - tool/gabarito_cascata.dart
  - docs/validacao/monotonia_vias.json
substitui:
  - 34
  - 38
  - 39
  - 45
---

## Contexto

A via da firma migrava para a via do acionista sobre LPA por dois caminhos:

- **a ponte fina** — a participação do capital próprio, medida na taxa
  estrutural ([decisão 34](034-fronteira-das-vias-medida-na-taxa-estrutural.md)),
  abaixo de 35% misturava as duas vias, e abaixo de 20% ficava só a do acionista
  ([decisão 38](038-transicao-continua-entre-as-vias.md));
- **a estrutura recusada** — quando a realavancagem recusava a estrutura de
  capital, a via do acionista carregava o ativo
  ([decisão 45](045-estrutura-de-capital-recusada.md)).

A [decisão 39](039-as-duas-vias-sao-modelos-independentes.md) mediu que as duas
vias são modelos independentes — discordam por até 28× no mesmo ativo — e
declarou que, enquanto isso não fosse fechado ou substituído por caminho único, o
motor não podia ser descrito como sem defeito conhecido. É o B13. O B10 é o
sintoma: a PRIO3, com a curva mais alta, migrava e o potencial **subia**.

**Medido em 16/09/2026**, sobre a entrada congelada do gabarito da cascata, com o
nível da taxa livre de risco — a corrente, a de equilíbrio e a curva inteira —
deslocado de −3 a +3 p.p. ([monotonia_vias_antes.json](../validacao/monotonia_vias_antes.json)):

- dos 109 não financeiros avaliados pelo aplicativo, **42 tinham o preço, inteiro
  ou em parte, da via do acionista**: 37 migrados e 5 mesclados;
- **25 de 128 avaliados** tinham o preço justo subindo com a taxa em algum ponto
  da grade; 18 deles trocavam de via na grade;
- **os outros 7 subiam sem trocar de via**, e a causa era outra: a regra que
  decide se a cobertura de juros entra no prêmio de crédito compara o custo da
  dívida observado com a faixa `[Rf, Rf + 10 p.p.]`, e a faixa andava com a taxa
  suposta. Na SMTO3, 25 pontos-base de taxa tiravam a cobertura da conta, e o
  desconto caía 2,3 p.p.

A [decisão 43](043-capital-proprio-pela-rota-derivada.md) já tinha a rota que
dispensa a ponte — o capital próprio pelo fluxo do acionista derivado do da
firma —, mas só com as taxas resolvidas, que o aplicativo não resolve (B11).

## Decisão

**Nenhuma avaliação muda de via no meio da conta.** A via sai do roteamento — o
setor (Porta 1) e a sustentação do lucro operacional (Porta 3), fatos de longo
prazo que não dependem da taxa nem do resultado da própria conta —, e a conta que
ela começa é a que ela termina.

1. **A via da firma avalia o capital próprio sempre pelo fluxo do acionista
   derivado**, `FCFE = FCFF − juros(1−τ) + ΔDívida`: com o caminho de taxas
   resolvido, ao `Ke` dele (decisão 43, sem mudança); sem ele, ao `Ke` do CAPM, da
   taxa corrente à de equilíbrio, com o custo da dívida que o WACC aplica. O
   deslocamento que um cenário impõe ao desconto da firma é aplicado ao `Ke`.
2. **Saem a pós-condição dos 20%, a mescla e as duas migrações.** O capital
   próprio fino continua declarado, pela ressalva `ponteFragil`. Capital próprio
   não positivo e estrutura recusada viram recusa nomeada.
3. **A via do acionista sobre LPA fica para o que o roteamento manda para ela**: a
   instituição financeira e o lucro operacional não sustentado
   ([decisão 64](064-a-porta-3-fica-e-a-medicao-e-a-razao.md)). **A discordância
   entre as duas vias deixa de ser defeito do motor**, porque nenhum ativo tem o
   preço escolhido entre elas: cada uma avalia uma população que o roteamento
   separa por fato, e não pela conta.
4. **A faixa do crédito é medida na taxa da data** (`creditReferenceRiskFree`),
   e não na taxa suposta: é pergunta sobre o dado do exercício. O WACC corrente e
   o de equilíbrio passam a ler o mesmo veredito.
5. **O terminal do contrato, na rota derivada, é a perpetuidade do acionista
   truncada**, com o capital devolvido menos a dívida no fim: coincide com o de
   antes no contrato que acaba no horizonte e tende à perpetuidade no contrato
   sem fim. O de antes — o terminal da firma menos a dívida — só era coerente com
   as taxas resolvidas, e sem elas punha o contrato de 21 anos acima do perpétuo.

## Consequências aceitas

**O B10 fecha no aplicativo.** Na mesma varredura, depois das duas correções
([monotonia_vias.json](../validacao/monotonia_vias.json)): **nenhum dos 114
avaliados sobe com a taxa**, nenhum troca de via e nenhum alterna entre avaliado
e recusado no meio da grade. Só a correção do crédito tirava os 7 que subiam sem
trocar de via ([monotonia_vias_so_credito.json](../validacao/monotonia_vias_so_credito.json)).
A PRIO3 sai de −17,9%, migrada e não monótona, para **−72,3%**, pela via da firma
e monótona. Dois testes travam: o nível da curva inteira deslocado sobre um
fixture que atravessava a faixa que migrava, e a faixa do crédito na taxa da
data; os dois reprovam no código de antes.

**Na montagem com o prior do beta** — a do caminho resolvido, que o aplicativo
não usa —, sobram 2 não monótonos de 104 (RADL3 e SEER3), pela alternância do
veredito da perpetuidade entre passes do ponto fixo. É o caminho que o B11 decide
levar ou não ao aplicativo, e fica registrado lá.

**A cobertura cai.** No aplicativo, de 128 para 114 avaliados: saem 16 — 15 que
estavam migrados, com a CSNA3 (+42%), a CSAN3 (+21%) e a MRVE3 (+10%) entre eles,
e a GOAU4 — e entram 2, a AMER3 e a DASA3. Nos que saem, o fluxo do acionista
derivado do da firma não sustenta capital próprio positivo. **É a via da firma
dizendo o que ela diz**: a do acionista via lucro positivo onde a firma via dívida
consumindo o valor, e escolher a que avalia era o defeito. Na montagem com o prior,
saem as 23 de estrutura recusada.

**O preço justo muda.** Nos 65 que eram avaliados só pela firma, a rota derivada
sem taxas resolvidas dá 5,5% a menos na mediana (p10 −26,8%, p90 +11,5%): WACC de
pesos de mercado e `Ke` do CAPM não são as taxas coerentes que a decisão 43 exige
para as duas rotas coincidirem. Nos 22 migrados que seguem avaliados, o preço vai
à metade na mediana. A correlação de postos do potencial com o de antes, nos
comuns, é de 0,83; o potencial mediano vai de −42,4% a −52,8%. **Todas as medições
de validação que dependem do preço justo precisam ser refeitas** — o backtest foi
reexecutado nesta rodada, e a medição final é a da Fase 4.

**A rota derivada sem taxas resolvidas não é a identidade.** Ela é o modelo do
fluxo do acionista com o `Ke` do beta observado, que é o livro-texto; a coincidência
exata com `FCFF/WACC − D` exige o caminho resolvido, e é o B11.

**Alternativas descartadas.**

- *Manter a ponte e só tirar a migração*, recusando abaixo de 20%: tirava o degrau
  do preço e deixava o da cobertura, e a ponte fina continuaria sendo a subtração
  de dois números grandes medidos por taxas diferentes.
- *Deixar a via do acionista só para instituição financeira*, que é a primeira
  saída do B13: tiraria a Porta 3, que a decisão 64 manteve por medição. Com a
  migração fora, a Porta 3 não produz degrau, porque não depende da taxa.
- *Resolver as taxas no aplicativo*: é o B11, fora do escopo desta rodada.

**O gabarito da cascata foi regravado** sobre o motor novo, depois de conferido
idêntico no motor de antes com a entrada congelada — que passou a congelar também
o universo, que vinha da rede.
