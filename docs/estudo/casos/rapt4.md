# Caso RAPT4 — Randon: quando o motor se recusa a dar um preço

> **O que este caso mostra.** Nem toda empresa recebe preço justo. A Randon
> passa pelas portas, mas a conta da via da firma diz que, com o custo de
> capital que ela tem e o retorno que ela entrega hoje, **o valor da operação
> não cobre a dívida**. Em vez de mudar de caminho até algum dar número, o motor
> recusa e diz por quê. No caminho, o caso mostra também a **trava de saúde**
> segurando a normalização para cima.
>
> **Data:** 14/09/2026, entrada congelada, com o motor de 03/11/2026
> ([dados/RAPT4.json](dados/RAPT4.json)).
>
> **Resultado:** **recusa** — "o fluxo do acionista de RAPT4, derivado do da
> firma, não sustenta capital próprio positivo: a dívida líquida consome o valor
> que a operação gera".

---

## 1. Os dados de partida

| Grandeza | 2021 | 2026 anualizado |
|---|---:|---:|
| Receita | R$ 9,06 bi | R$ 12,78 bi |
| EBIT | R$ 1,10 bi | R$ 1,12 bi |
| Capital investido | R$ 5,09 bi | R$ 9,71 bi |
| Dívida líquida | R$ 1,81 bi | **R$ 5,14 bi** |
| Minoritários | R$ 0,75 bi | R$ 1,55 bi |
| Lucro líquido | R$ 0,88 bi | **−R$ 0,06 bi** |
| Preço de mercado | — | R$ 5,04 |

De 2021 para cá, o capital investido quase dobrou, financiado em grande parte
com dívida: a dívida líquida quase triplicou. O EBIT ficou no mesmo lugar, e o
lucro líquido virou prejuízo em 2025 (−R$ 59,8 mi) e no primeiro semestre de
2026, anualizado (−R$ 57,7 mi). Os minoritários são grandes porque a Randon
consolida controladas com outros sócios: a parte deles no patrimônio é quase
o valor de mercado da própria Randon.

---

## 2. Os passos que o motor completou

| Passo | Resultado |
|---|---|
| Unit | `349.724.670 × R$ 5,04 ÷ R$ 1,20 bi = 1,47` → 1 ação por papel |
| Contagem | oficial da B3: 348.687.672 papéis (a fonte dava 237,3 milhões pelo valor de mercado e 349,7 milhões pelas demonstrações) |
| Portas | não financeira; NOPAT positivo em ≥ 60% dos anos → **via da firma** |
| CAPM | `Ke = 14,05% + 1,1592 × 1,21% = 14,05% + 1,40% = 15,45%` — beta alto (1,16; desalavancado 0,67: é a dívida que o levanta) |
| Base | ROIC atual 7,74% contra 14,64% do ciclo: destoa, mas a **trava de saúde** segura o fator em 1,00 (seção 3) |
| Capital externo | Φ = 0,97: quase todo o capital novo da janela veio de fora; abaixo de 1,0, a base ainda é comparável |
| Crescimento | mediana 14,52% × regressão 10,54%: discordam 3,1 erros-padrão → **não identificado**; a âncora de inflação (4,96%) é financiável (exige reter 33,9%, e a empresa reteve tudo) → g = 4,96% |
| Custo da dívida | alavancagem 3,15× (dívida líquida ÷ EBITDA) → prêmio de 4,0%; a despesa financeira não está publicada no ponto anualizado → Kd = 18,05% |
| WACC de hoje | 0,2550 × 15,45% + 1,3280 × 18,05% × 0,66 − 0,5829 × 14,05% × 0,66 = 3,94% + 15,82% − 5,40% ≈ **14,35%** (a soma das parcelas arredondadas dá 14,36%) |
| Perpetuidade | barrada: crescimento inorgânico (Φ = 0,97, acima do teto de 0,60), e o retorno do ciclo (14,64%) mal empata com o custo de equilíbrio (14,60%) |

Os pesos do WACC passam de 1 porque a dívida bruta (R$ 9,15 bi) é maior que o
capital próprio a preço de mercado mais a dívida líquida (R$ 6,89 bi): a preço
de mercado, o capital próprio é só 25,5% do valor da firma.

---

## 3. A trava de saúde

```
alíquota estrutural = 28,9%   (mediana das efetivas)
NOPAT 2026 = 1.119,6 × (1 − 28,9%) = R$ 795,8 mi
ROIC 2026  = 795,8 ÷ capital investido 2025 (10.277,3) = 7,74%
ROIC do ciclo = mediana de 2018–2025 = 14,64%
```

Os oito retornos do ciclo, em ordem: 6,8%, 12,0%, 12,6%, 14,3%, 14,9%, 17,5%,
20,5% e 23,6%; a mediana é `(14,33% + 14,94%) ÷ 2 = 14,64%`.

Sem tendência (+0,28 p.p. ao ano, `t` = 0,71) e com o último ponto fora da banda
(razão 0,53), a normalização pediria um fator de `14,64% ÷ 7,74% = 1,89`. **Mas
o lucro líquido caiu 108,7% no triênio** — de R$ 663,5 mi em 2023 para o
prejuízo de R$ 57,7 mi —, acima do máximo de 50%, e a Randon é de bens
industriais, não de commodity. O fator fica em **1,00**: o motor não supõe que
uma empresa que perdeu o lucro volta sozinha ao retorno do passado. A base é o
NOPAT de 2026 anualizado, R$ 795,8 mi.

Compare com a [Unipar](unip6.md), em que uma queda de 59% não trava nada,
porque ali a queda é o ciclo do preço do produto.

---

## 4. Onde a conta para

O motor resolve o custo de capital ano a ano contra a dívida que a própria
avaliação produz (capítulo 3, seção 3.10), e aqui o ponto fixo **fecha**: 30
iterações, WACC de 13,8% no ano 1 a 14,6% no ano 10, e o capital próprio indo
de 4,4% a 16,1% do valor da firma. O problema aparece depois, ao descontar:

| | R$ mi |
|---|---:|
| Valor presente do fluxo do acionista dos dez anos | −287,4 |
| Valor presente do terminal do acionista | 243,3 |
| **Capital próprio antes dos minoritários** | **−44,0** |
| Minoritários | −1.550,5 |
| **Capital próprio da Randon** | **−1.594,5** |
| ÷ 348,7 milhões de papéis | **−R$ 4,57 por ação** |

A conferência pelo outro lado dá o mesmo: o valor da firma é de R$ 5.091,1 mi, e
a dívida líquida, de R$ 5.135,2 mi; `5.091,1 − 5.135,2 = −44,0`. Preço por ação
negativo não é preço: o motor **recusa**, e a mensagem diz por quê.

**A ordem de grandeza do primeiro ano, à mão:**

```
NOPAT₁ = 795,8 × 1,0496 = 835,4
crescer 4,96% com ROIC de 7,74% exige reter 4,96 ÷ 7,74 = 64% do NOPAT
fluxo da firma₁ = 835,4 × (1 − 0,64) ≈ 300

juro da dívida      = 9.153,2 × (13,67% + 4,0%) × (1 − 34%) = 1.067,6
rendimento do caixa = 4.018,0 × 13,67% × (1 − 34%)          =   362,6
dívida nova         = 5.135,2 × 4,96%                        =   254,9
serviço da dívida   = 1.067,6 − 362,6 − 254,9                =   450,1

fluxo do acionista₁ ≈ 300 − 450 = −150
```

O fluxo do acionista **começa negativo**: a operação gera R$ 300 mi livres, e os
juros depois do imposto, descontado o que o caixa rende e a dívida nova, levam
R$ 450 mi. Ele melhora à medida que o ROIC sobe em direção ao custo de capital,
mas os dez anos somados ainda valem −R$ 287,4 mi a valor presente, e o terminal
não compensa.

**Traduzindo:** a operação da Randon rende hoje 7,7% sobre o capital, e o motor
diz que esse capital custa cerca de 14,5%. Nessa conta, a empresa inteira vale
menos que o que ela deve — e, depois da parte dos sócios das controladas, nada
sobra para o acionista da Randon.

---

## 5. Por que recusar, e não dar um número?

Três alternativas foram consideradas e rejeitadas pelo projeto:

1. **Dar o número negativo, ou zero.** Um preço justo de R$ 0 diria "a ação não
   vale nada", o que é mais forte do que o método sustenta. O que a conta diz é
   que **este método, com estas premissas, não avalia esta estrutura de
   capital**.
2. **Trocar para a via do acionista.** Ela parte do lucro líquido, e daria algum
   número. Mas escolher o modelo **porque** o primeiro recusou faria o preço
   justo depender de qual conta alcançou um resultado — e aí qualquer ativo
   sempre teria preço.
3. **Usar a taxa de um ano só, sem realavancar.** Esconderia o problema: com
   alavancagem alta, a taxa de hoje e a de daqui a cinco anos não são a mesma.

Também não se afrouxa a trava de saúde para a conta fechar. O fator de 1,89
quase dobraria o lucro de partida, mas a trava decide a base antes de qualquer
resultado, e vale igual para todos os ativos fora de commodity.

A recusa aparece na tela com o motivo, e o painel de logs mostra todos os passos
até ela.

---

## 6. O que o mercado vê e o motor não

O mercado paga R$ 1,76 bi pelas ações da Randon. Para isso, ele precisa
acreditar em pelo menos uma destas coisas, que o motor não supõe:

- o retorno sobre o capital volta ao nível de 2020 a 2022 (acima de 17%) — o
  motor vê a queda do lucro e mantém a base onde está;
- a Randon capta mais barato que 18% ao ano — o motor usa o prêmio de crédito
  da alavancagem, que é alta (3,15×);
- a parte dos sócios das controladas vale menos que o patrimônio contábil
  dela — o motor subtrai os minoritários pelo valor do balanço.

Qualquer uma delas pode ser verdade. O motor não tem como saber qual, e por isso
não dá preço.

---

## 7. O que este caso ensina

- **Recusar é um resultado.** Em 14/09/2026, o motor recusou 258 dos 379 ativos
  que chegaram a ele — a maioria por liquidez (195) ou falta de histórico (34),
  e três, como a Randon, porque o fluxo do acionista não sustenta capital
  próprio positivo (as outras são a ANIM3 e a CSAN3; ver
  [a cascata e as portas](../../motor/02-cascata-e-portas.md)).
- **Alavancagem alta torna o preço por ação frágil.** Quando o capital próprio é
  uma fatia pequena do valor da firma, pequenos erros no valor da operação viram
  erros enormes no valor da ação. Aqui a diferença entre o valor da firma e a
  dívida é de 0,9% do valor da firma. É por isso que existe a ressalva "ponte
  frágil" (capital próprio abaixo de 35% do valor da firma).
- **A trava de saúde muda o resultado.** Ela aparece aqui, na
  [Sanepar](sapr11.md) e, isenta, na [Unipar](unip6.md). A regra é a mesma nos
  três casos; muda o setor e o tamanho da queda.
