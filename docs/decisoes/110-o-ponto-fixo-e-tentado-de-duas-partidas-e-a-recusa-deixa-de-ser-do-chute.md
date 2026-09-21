---
numero: 110
titulo: O ponto fixo do custo de capital é tentado de duas partidas, e a recusa de estrutura deixa de ser do chute
status: aceita
origem: voce
data: 2026-09-21
citacao: >
  Seus itens de escopo para esta rodada são B17, B18, B19, B8 e B2.
afeta:
  - packages/equisim_core/lib/src/services/valuation/levered_rates.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - docs/validacao/prior_no_aplicativo.md
substitui: []
---

## Contexto

A [decisão 45](045-estrutura-de-capital-recusada.md) recusa o ativo quando a
realavancagem não tem sentido econômico — o capital próprio desaparece dentro da
projeção. Ao ligar o prior do beta
([decisão 105](105-o-aplicativo-resolve-o-prior-do-beta-e-o-custo-de-capital.md)),
14 ativos saíram do aplicativo por essa recusa, **todos no ano zero da primeira
iteração**: o valor da firma, descontado à interpolação de dois pontos de que o
ponto fixo parte, não cobria a dívida líquida.

**O veredito era do chute.** A interpolação é o recuo que a
[decisão 41](041-custo-de-capital-realavancado-ano-a-ano.md) substituiu, e um
ponto fixo que recusa antes de iterar não recusou nada — ele nem começou. É a
mesma forma de defeito que o B10 mediu na fronteira das vias: a resposta depende
de qual conta o motor alcançou primeiro.

## Decisão

**O ponto fixo é tentado de duas partidas**, e a recusa só vale quando nenhuma
delas fecha:

1. a **interpolação de dois pontos**, que é o recuo e era a única;
2. o **custo de capital desalavancado** — `Rf_t + β_U · prêmio` —, que é o mesmo
   caminho no limite de dívida zero, e portanto partida tão legítima quanto a
   primeira.

E, porque **um ponto fixo é um ponto fixo**:

- quando as duas convergem, elas têm de convergir para o mesmo lugar.
  `LeveredCostOfCapital.startIndependence` mede isso em um décimo de por cento
  do capital próprio do ano zero — o critério de parada é de `1e-10`, de modo
  que duas convergências legítimas ficam muito abaixo disso. Divergir é
  **ressalva do método**, e a avaliação a declara;
- quando só uma converge, vale ela, e a avaliação diz de qual partida veio;
- quando nenhuma converge, a recusa diz que **foi tentada das duas** — dizer só
  que a interpolação não fechou deixaria em pé a leitura de que o veredito é do
  chute.

O mesmo vale para o ponto fixo da via do acionista (`solveEquity`), pela mesma
razão: deixar uma via dependente da partida e a outra não seria trocar um defeito
por metade dele.

## O que foi medido

Sobre a entrada congelada do gabarito, em 21/09/2026:

- **Um dos 14 volta**: a CAML3, que a interpolação recusava e o ponto fixo, a
  partir do desalavancado, avalia. A cobertura vai de 102 a **103**.
- **Os outros 13 continuam recusados**, agora das duas partidas: a recusa é do
  método.
- **Nenhum preço justo se move** — 0 de 102 — e as duas montagens do gabarito
  ficam idênticas fora da CAML3.
- **Zero divergências entre partidas** em todo o universo, nas duas montagens: o
  ponto fixo é independente de onde começa onde ele converge.

## Consequências aceitas

**A conta é feita duas vezes.** O custo é de processamento, e ele é pago em toda
avaliação com taxas resolvidas — 83 das 103 no aplicativo. É o preço de a
resposta não depender do chute, e o gabarito de 376 ativos e nove montagens
continua rodando em minutos.

**A segunda partida é uma escolha, e não a única possível.** O desalavancado foi
escolhido por ser o mesmo caminho do modelo no limite de dívida zero — não é um
chute arbitrário posto ali para resgatar ativo. Se um terceiro ponto de partida
achasse um terceiro resultado, a ressalva de independência o acusaria.

**A ressalva de divergência não dispara hoje**, e é assim que ela deve ser lida:
ela existe para o dia em que disparar. Um ponto fixo com dois atratores é
resultado que não pode sair sem aviso.
