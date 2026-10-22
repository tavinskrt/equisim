---
numero: 143
titulo: A contagem de ações por data é conferida contra o salto do preço, com âncora na mais recente
status: aceita
origem: voce
data: 2026-10-01
citacao: >
  Depois de analisar todas essas variáveis, decidimos implementar somente a
  mudança no prêmio de risco para implementar a média dos 10 anos. Pode
  realizar a implementação no código, corrigindo e implementando todos os itens
  relacionados a esta implementação.
afeta:
  - tool/coortes/contagem_conferida.dart
  - tool/backtest_valuation.dart
  - tool/coortes/deslistadas.dart
  - tool/premio_implicito.dart
substitui: []
---

## Contexto

O item B43 do plano foi aberto em 29/09/2026, ao medir o prêmio implícito
([premio_implicito.md](../validacao/premio_implicito.md) §3.1): a contagem de
ações por data que as coortes leem do Formulário de Referência
(`data/b3/listadas_contagem.json` e `deslistadas_contagem.json`) erra de escala
nos dois sentidos.

- **A correção que repete a contagem velha.** A Ampla agrupou as ações de
  40.000 para 1 em dezembro de 2015, e a correção do formulário de maio de 2016
  voltou aos 3,9 trilhões de ações — vezes o preço de depois do grupamento, R$
  142 trilhões de valor de mercado. A Hapvida (2025) e o IRB (2024) fazem o
  mesmo: no backtest, a HAPV3 de 2025 entrava com quinze vezes o valor de
  mercado real, e a IRBR3 de 2024 com trinta.
- **A correção que é o único registro do evento.** A Magazine Luiza agrupou 10
  para 1 em maio de 2024, e a contagem só cai de 7,39 bilhões para 739 milhões
  na correção de maio de 2025. A MGLU3 de 31/03/2025 foi avaliada com dez vezes
  as ações que tinha: preço justo de R$ 2,46 e potencial de −75,8%, contra R$
  24,52 no trimestre seguinte, com a contagem certa.

A primeira regra tentada — descartar a correção que move a contagem mais de
cinco vezes — quebrava os casos do segundo tipo (TIMS3, MGLU3). A fonte da
entrada não separa os dois.

Pesou também o pedido do usuário de corrigir os itens relacionados ao prêmio
implícito: a série dele soma o valor de mercado da bolsa com a mesma contagem,
e as coortes do backtest que a decisão 142 remede também.

## Decisão

**A contagem é conferida contra o preço** (`conferirContagem`, em
`tool/coortes/contagem_conferida.dart`), nas listadas e nas deslistadas do
backtest e na série do prêmio implícito:

1. Parte da contagem mais recente até a data de corte e anda para trás.
2. Diferença de até **três vezes** em relação à última aceita vale como veio
   (emissão, recompra, conversão).
3. Na maior, o preço decide. **Com o salto correspondente** no preço bruto de
   algum papel da companhia — grupamento de dez para um, preço dez vezes maior,
   com folga de 1,4 vez — entre a data da entrada e **400 dias** depois da
   aceita (o prazo do B30: a aprovação do desdobramento vem meses antes da data
   ex, como na PRIO), é evento de ações, e a aceita passa a valer **no dia do
   salto**, para ação e preço mudarem de base juntos.
4. **Sem o salto**, não é evento de ações: é emissão ou incorporação grande, e
   vale como veio — **a menos que a entrada seja uma correção de formulário**
   (`filingCorrection`). A correção sem salto é a que repete a contagem de
   antes do evento (Ampla, Hapvida, IRB, Eletro Aço Altona), e é descartada; o
   trecho dela fica com a contagem anterior.

O evento que o formulário não registrou continua entrando depois, pela regra
do B30 (decisão 137).

**Uma versão anterior foi desfeita na mesma rodada.** Ela descartava toda
mudança grande sem salto no preço, e com isso tirava das coortes, antes da
emissão, as companhias que se capitalizaram em crise ou se fundiram — Dasa,
Light, Azul, Gol, Sequoia —: 283 entradas descartadas, contra 36 da regra que
ficou, e um viés de seleção na validação.

## Consequências aceitas

- **A âncora é a contagem mais recente**, que é a que o formulário de hoje
  confirma. Conferir a contagem de uma data com a de depois é limpeza de dado,
  e não informação de mercado: a contagem aceita numa data é a que a companhia
  tinha nela.
- **A entrada primária errada passa.** A TIM começa em julho de 2020 com 423
  milhões de ações — a contagem da TIM S.A. antes da incorporação da
  controladora —, contra os 2,42 bilhões que a ação tem desde então; é um evento
  de ações registrado, sem salto no preço, e fica como veio, como antes desta
  decisão.
- **A regra vive nas ferramentas de validação**, e não no núcleo: o aplicativo
  lê a contagem oficial da B3 de hoje (decisão 83), que não tem o problema.
