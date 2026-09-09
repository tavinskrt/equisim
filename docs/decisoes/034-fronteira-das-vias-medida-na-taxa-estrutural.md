---
numero: 34
titulo: A pós-condição da ponte de equity é medida na taxa estrutural
status: aceita
origem: voce
data: 2026-09-09
citacao: >
  Pode corrigir essa não-monotonia na fronteira de vias. Deixe as demais para
  avaliação posterior
afeta:
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
substitui: []
---

## Contexto

A pós-condição da ponte de equity, criada pela
[decisão 25](025-reconstrucao-do-motor-de-avaliacao.md), migra a avaliação para
o fluxo do acionista quando o capital próprio responde por menos de 20% do valor
da firma. O motivo é sólido: abaixo disso o preço por papel é resíduo de uma
subtração entre números próximos, e o erro relativo do valor da firma chega
amplificado por `1/participação`.

Ela era medida na taxa de desconto **corrente**. Como a participação depende do
valor da firma, e o valor da firma depende da taxa, o degrau andava com o ciclo
monetário — e o preço justo deixava de ser monótono na taxa de desconto.

Medido na KLBN11, varrendo a taxa livre de risco:

```
  Rf      Ke        justo    via
 9.00%   11.72%  R$   7.98   acionista
 8.75%   11.47%  R$   5.36   firma      <- cai 33% ao baratear o capital
```

Baixar o custo do capital em 25 pontos-base derrubava o preço justo em 33%. O
mecanismo: taxa menor → valor da firma maior → participação cruza os 20% → a
migração deixa de disparar → o ativo fica na via da firma, que para aquela
empresa devolve menos. Capital mais barato produzindo empresa menos valiosa
contradiz a definição de fluxo descontado.

Não era caso isolado à espera: **33 dos 124 ativos avaliados migram hoje**, e
todos atravessam essa fronteira conforme a Selic cede.

## Decisão

**A participação que decide a via passa a ser medida na taxa estrutural** — a
mesma taxa de equilíbrio que a [decisão 31](031-escala-do-preco-tributo-e-invariancia-das-guardas.md)
já usa na perpetuidade —, e não na corrente. Sem medida estrutural utilizável,
vale a da taxa corrente: ausência de medida não é motivo para deixar de aplicar
a pós-condição.

O fundamento é que a estrutura de capital de um ativo é fato de longo prazo, e
qual das duas vias a descreve não pode depender de onde a Selic está hoje.
Dentro de cada via o preço justo continua monótono na taxa; o que a medida
remove é a travessia induzida pelo ciclo.

Dois testes fixam o comportamento em
[valuation_guards_test.dart](../../packages/equisim_core/test/valuation_guards_test.dart):
baratear o capital nunca derruba o preço justo, e a via não muda com a taxa
livre de risco corrente. Ambos falham sem a correção, com queda medida de
R$ 7,77 para R$ 3,89.

## Consequências aceitas

- **Cinco ativos passam a publicar número da via da firma cuja participação na
  taxa corrente está abaixo dos 20%.** Medidos: ANIM3 (16,1%), COGN3 (12,1%),
  CYRE4 (16,4%), MYPK3 (17,6%) e PNVL3 (16,5%). O preço justo deles cai — de
  0,903 para 0,638 da cotação na ANIM3, de 0,527 para 0,080 na CYRE4. **Os cinco
  carregam a ressalva `ponteFragil`**, de modo que a fragilidade é declarada e
  não escondida; e o erro que sobra é o conservador. Em taxa muito alta a
  participação corrente pode ficar bem abaixo disso, e ali a ressalva é a única
  proteção.

- **O nível do universo não se move.** Mediana de `justo ÷ preço` em 0,545 antes
  e depois, 15 de 124 subavaliados nos dois. A correção é de forma, não de
  calibragem — o que era o requisito: as travas de nível ficaram para avaliação
  posterior.

- **As duas vias continuam discordando.** Elas medem crescimento e base em
  séries de capital diferentes: na KLBN11, 5,0% contra 10,16% de crescimento e
  fator de base 0,665 contra 1,000. Esta decisão não concilia isso — apenas
  impede que o ciclo monetário escolha entre elas. A conciliação, se for
  desejável, exige decisão própria.

- **A alternativa descartada foi `max(firma, acionista)` no ramo de ponte
  sadia.** Ela também produz monotonia, e foi medida: mexe em **37 dos 124**
  ativos e move a mediana de 0,545 para 0,658 — mudança de nível do tamanho das
  maiores travas, embutida numa correção de forma. Foi rejeitada por isso, não
  por ser indefensável.

- **Custa uma projeção a mais por ativo da via da firma**, para medir a
  participação na taxa de equilíbrio. É função pura sobre dados já carregados.
