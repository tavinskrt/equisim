---
numero: 148
titulo: A sensibilidade é nomeada pelas premissas, num cartão só, e a inversão é declarada
status: aceita
origem: voce
data: 2026-10-14
citacao: >
  Pode implementar os rótulos e juntar os cartões
afeta:
  - lib/presentation/shared/domain_copy.dart
  - lib/presentation/valuation/valuation_page.dart
  - packages/equisim_core/lib/src/services/valuation/scenario_engine.dart
substitui: []
---

## Contexto

A tela de avaliação mostrava dois cartões sobre a mesma conta. "Cenários" trazia
três valores rotulados «Pessimista», «Base» e «Otimista»; "Sensibilidade", logo
abaixo, os mesmos dois extremos em barra. A conta por trás é deslocamento de
premissa: o crescimento do primeiro ano 3 pontos para baixo e as duas taxas de
desconto 2 pontos para cima, e o contrário.

O nome prometia mais do que a conta faz. A decisão 92 já mediu que a faixa é
sensibilidade, e não cenário — ela conteve 8% do que aconteceu nas coortes —, e
o item B38 achou o caso em que o nome mente: com a empresa rendendo abaixo do
custo de capital, crescer destrói valor, e o «Otimista» sai abaixo do
«Pessimista» — 14 dos 90 ativos da via da firma em 14/09/2026. O B38 deixou
três caminhos ao usuário: manter os rótulos e declarar, nomear pelas premissas,
ou separar as duas sensibilidades. Em 14/10/2026 o usuário perguntou que
rótulos pôr no lugar e, depois da sugestão, pediu os rótulos novos e a fusão dos
cartões.

## Decisão

**Os três conjuntos fixos são nomeados pelas premissas — «Premissas mais
duras», «Premissas do motor», «Premissas mais brandas» —, com o quanto foi
mexido em nota, num cartão "Sensibilidade" só. A definição dos conjuntos não
muda.**

1. **O rótulo diz o que foi mexido; a nota diz quanto**: «crescimento −3 p.p.,
   taxa +2 p.p.» e o contrário. Os dois números vêm de
   `DiscreteScenarios.defaultGrowthDelta` e `defaultDiscountDelta`, os mesmos
   que a conta usa.
2. **A cor sai do valor, e não do nome**: acima do preço justo, a cor de alta;
   abaixo, a de baixa. Com o crescimento destruindo valor, as premissas mais
   brandas aparecem abaixo e na cor de baixa.
3. **A inversão é declarada.** Quando as premissas mais brandas dão preço menor
   que as mais duras, o cartão diz por quê — a empresa rende abaixo do custo de
   capital, e crescer destrói valor — e que não é erro da conta.
4. **Um cartão só**, com o alternador de Monte Carlo, os valores, o aviso, a
   barra e a lembrança de que isto é sensibilidade, e que a incerteza medida é
   a faixa calibrada. No Monte Carlo, as notas «pessimista» e «otimista» de P5 e
   P95 viram «5% dos sorteios abaixo» e «5% dos sorteios acima».

**O B38 fecha pelo segundo caminho.** Mudar o que os conjuntos são — separar a
sensibilidade do crescimento da do desconto, por exemplo — seria mudança de
método, e não está decidido aqui.

## Consequências aceitas

- **"Mais brandas" continua sendo juízo sobre as premissas** — crescer mais e
  descontar menos —, e não sobre o preço. É o que o aviso da inversão cobre.
- **Os nomes internos `bear` e `bull` ficam**: são do núcleo, e o rótulo é da
  tela (decisão 125).
- **O texto que citava os rótulos antigos** — o guia de estudo, o capítulo 6 do
  motor, as limitações e as perguntas do orientador — passa a citar os novos e o
  B38 fechado.
