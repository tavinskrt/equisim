---
numero: 116
titulo: O prêmio de mercado fica em 5,5%, por medição das duas alternativas — e o implícito de −3,9% diz que o desacordo de nível não é dele
status: aceita
origem: voce
data: 2026-09-21
citacao: >
  Seus itens de escopo para esta rodada são B6, B7, B3, B4 e B5.
afeta:
  - tool/premio_de_mercado.dart
  - tool/validation/congelado.dart
  - packages/equisim_core/lib/src/services/valuation/cost_of_capital.dart
  - docs/validacao/premio_de_mercado.md
substitui: []
---

## Contexto

O prêmio de risco de mercado é **5,5% fixo**, ponto médio de uma faixa de 5–6%
adotada como parâmetro do projeto. O item B3 pedia que ele deixasse de ser
parâmetro, e nomeava duas saídas: **histórico com encolhimento** ou
**implícito**, com efeito medido.

## O que foi medido

Sobre a entrada congelada do gabarito
([premio_de_mercado.md](../validacao/premio_de_mercado.md)), com a montagem de
5,5% conferida ativo a ativo contra ele.

**O histórico não estima.** Ibovespa contra CDI em cinco anos: **0,39%**, com
erro-padrão de **7,85 p.p.** e intervalo de 95% de −15,0% a +15,8%. A janela de
dez anos das âncoras do projeto diz 1,70%, com erro-padrão de 5,5 p.p. **São
precisos 308 anos de série para um erro-padrão de um ponto percentual.**

**O encolhimento devolve o parâmetro.** Com peso amostral `τ² ÷ (τ² + σ²)`:

| `τ` | peso da amostra | prêmio encolhido |
|---:|---:|---:|
| 0,25% | 0,10% | **5,49%** |
| 1,00% | 1,60% | 5,42% |
| 2,00% | 6,10% | 5,19% |

**O implícito é −3,9%.** O prêmio que põe o potencial mediano do universo em zero
exige que o acionista aceite quase quatro pontos **abaixo do CDI**.

## Decisão

**5,5% fica, e deixa de ser convenção: passa a ser o resultado das duas
alternativas que o item pedia.**

1. **A saída "histórico" foi tentada, e o resultado dela é o parâmetro.** Não
   por teimosia: por álgebra. Um estimador com erro-padrão de 7,85 p.p. recebe
   peso de 0,1% contra uma faixa a priori de meio ponto, e o encolhimento
   honesto devolve 5,49%. **Adotar 0,39% seria adotar ruído**, e adotar 5,5% sem
   este cálculo seria adotar convenção. Agora é nenhum dos dois.
2. **A saída "implícito" foi tentada, e o resultado dela é uma recusa.** Um
   prêmio negativo não descreve mercado nenhum. Adotá-lo faria o motor concordar
   com o preço **por construção**, o que é o oposto do que um avaliador serve
   para fazer.
3. **O prêmio continua parametrizado e declarado.** `MarketPremiumSource`
   continua em `parameterized`, e o valor continua onde está, com este registro
   ao lado.

**O motor não muda.** O que muda é que 5,5% deixa de ser número herdado.

## O que a medição resolveu de passagem

**O desacordo de nível entre o motor e o mercado não é do prêmio de risco.** A
§0 do plano mediu o potencial mediano em −38%, e a suspeita desde então era um
custo de capital alto demais. **Zerar o prêmio move o potencial mediano de
−44,7% para apenas −29,9%**: dois terços do desacordo sobrevivem a um prêmio
**nulo**.

Isso fecha uma hipótese que estava aberta desde a §0, e empurra a explicação
para onde a [decisão 112](112-a-rentabilidade-reverte-a-mediana-do-mercado-e-nao-ao-custo-de-capital.md)
já apontou: a rentabilidade das companhias abertas brasileiras vive abaixo do
custo de capital delas, e um terminal honesto sobre essa amostra tem de dizê-lo.

**E o prêmio é botão de nível, não de ordenação.** Postos de 0,996 ou mais entre
4% e 7%, e 0,97 com prêmio zero — a previsão da §3 do plano, agora medida. **Mas
move a cobertura**: 87 avaliados a 10%, 97 a 5,5%, 110 a −2%.

## Consequências aceitas

**A janela do histórico é de cinco anos**, que é o que a entrada congelada
guarda do Ibovespa. Série desde 1995 daria outro número, e ainda com erro-padrão
de 3 p.p. — a conclusão não depende da janela, e sim da volatilidade de 17,6% ao
ano.

**O implícito foi buscado pela mediana do potencial**, e não pelo agregado
ponderado pelo valor de mercado: ponderar exigiria a contagem de papéis de cada
ativo, que é a grandeza que a ponte arbitra (decisão 83), e o resultado passaria
a depender dela.

**Não há prêmio variável no tempo.** O implícito de Damodaran é recalculado a
cada data e varia com o ciclo; aqui há uma data só, e a conclusão é sobre o
nível. As coortes do backtest continuam usando o mesmo 5,5% em toda data, que é
limitação já declarada e não muda com esta decisão.
