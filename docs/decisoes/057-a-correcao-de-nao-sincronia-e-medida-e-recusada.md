---
numero: 57
titulo: A correção de negociação não síncrona no beta é medida e recusada, e a cotação suja fica declarada como bloqueio de dado
status: aceita
origem: conselheiro
data: 2026-09-11
citacao: >
  Acumular observações de cotações em janelas agregadas semanais ou mensais (ou
  usar estimadores não-síncronos) na regressão.
afeta:
  - packages/equisim_core/lib/src/services/metrics/beta.dart
  - tool/beta_sincronia.dart
  - docs/validacao/beta_sincronia.md
  - docs/validacao/limitacoes.md
substitui: []
---

## Contexto

A lente `metodo` voltou em **sete rodadas seguidas** ao mesmo ponto: o beta sai
de regressão de retorno diário sobre cotação não ajustada por provento. São
dois apontamentos distintos, e cada um termina de um jeito.

## Decisão

**A correção de não sincronia não entra.** Três estimadores foram medidos na
mesma janela de cinco anos, sobre os 127 ativos que o motor avalia:

| | mediana ÷ diário | erro-padrão mediano |
|---|---:|---:|
| diário (produção) | — | **0,0490** |
| Dimson (defasado + contemporâneo + adiantado) | **0,978** | 0,0853 |
| semanal | 0,991 | 0,1073 |

**A correção reduz o beta em 2,2% na mediana, e não o eleva** — o contrário do
que a teoria prevê. E custa 74% mais erro-padrão; o semanal, 119%.

**A razão é a Porta 0.** As duas metades do universo, ordenadas por liquidez,
negociam **250 pregões por ano** — todos eles. O corte de liquidez da
[decisão 25](025-reconstrucao-do-motor-de-avaliacao.md) já removeu 162 ativos e
com eles a condição que produz o viés. No universo cru, antes da porta, a razão
Dimson ÷ diário vai a 1,411 no p90 e aparecem casos como a USIM6, com 20
pregões por ano.

**A cotação suja fica declarada como bloqueio de dado.** Corrigi-la exige a
série de retorno total da fonte, e a limitação 1.2 já mediu que ela é
inutilizável: 9,1% de desvio mediano, 38,5% de máximo. Trocar um viés de
tamanho desconhecido por um erro medido de 9,1% não é correção.

## Consequências aceitas

**Nenhum preço muda.** Esta decisão registra uma medição e o que ela recusa.

**O encolhimento é o que torna o custo do erro-padrão relevante.** A
[decisão 40](040-beta-encolhido-por-precisao.md) pondera por `1/SE²`; adotar
Dimson transferiria peso do ativo para o prior setorial, trocando precisão por
viés numa direção em que **não há viés a trocar**.

**Se o corte de liquidez for afrouxado, este item volta**, e volta com o tamanho
que o universo cru mostra. Está escrito no `dartdoc` de `BetaCalculator`, onde
quem mexer no corte vai ler.

**A alternativa descartada** era adotar Dimson por rigor teórico, já que a
correção é padrão na literatura. Recusada porque o projeto mede antes de
adotar, e a medição diz que aqui ela não corrige nada — é o mesmo desfecho da
correção de viés de Kendall na persistência do excedente, tentada e desfeita
pela mesma razão.
