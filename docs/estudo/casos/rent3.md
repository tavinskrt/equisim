# Caso RENT3 — Localiza: quando o motor se recusa a dar um preço

> **O que este caso mostra.** Nem toda empresa recebe preço justo. A Localiza
> passa pelas portas, mas a conta da via da firma diz que, com o custo de
> capital que ela tem e o retorno que ela entrega, **o valor da operação não
> cobre a dívida**. Em vez de mudar de caminho até algum dar número, o motor
> recusa e diz por quê.
>
> **Data:** 14/09/2026 ([dados/RENT3.json](dados/RENT3.json)).
>
> **Resultado:** **recusa** — "a estrutura de capital de RENT3 não sustenta a via
> da firma".
>
> **E o R$ 0,10 que apareceu na tela em 27/09?** Com os dados vivos daquele dia
> (e não os congelados de 14/09), a conta ficou no limite: o capital próprio
> sobreviveu por pouco, e o preço justo foi o resíduo de uma subtração de dois
> números enormes e quase iguais. É o mesmo diagnóstico, do outro lado da borda
> (item B34 do plano).

---

## 1. Os dados de partida

| Grandeza | 2021 | 2025 |
|---|---:|---:|
| EBIT | R$ 3,22 bi | R$ 7,81 bi |
| Capital investido | R$ 15,0 bi | R$ 58,5 bi |
| Dívida bruta | R$ 12,4 bi | R$ 43,6 bi |
| Caixa | R$ 5,0 bi | R$ 10,6 bi |
| **Dívida líquida** | R$ 7,4 bi | **R$ 33,0 bi** |
| Lucro líquido | R$ 2,04 bi | R$ 1,87 bi |
| Preço de mercado | — | R$ 35,59 |

Em 2022 a Localiza incorporou a Unidas. O capital investido quase quadruplicou,
financiado em grande parte com dívida; o lucro líquido não acompanhou.

---

## 2. Os passos que o motor completou

| Passo | Resultado |
|---|---|
| Unit | 1 ação por papel |
| Contagem | oficial da B3: 1.095.040.871 papéis (a fonte divergia: 1,13 bi pelo mercado, 2,0 bi pelas demonstrações) |
| Portas | não financeira; NOPAT positivo em ≥ 60% dos anos → **via da firma** |
| CAPM | `Ke = 14,09% + 1,45 × 1,21% = 15,84%` — beta alto (1,45; desalavancado 1,23) |
| Base | ROIC atual 9,69% contra 13,83% do ciclo, mas com **tendência de queda** significante (−0,58 p.p./ano, `t` = −2,65): **base mantida** |
| Capital externo | Φ = 5,64: o capital cresceu 5,6 vezes a base inicial com dinheiro de fora — **crescimento inorgânico** declarado |
| Crescimento | mediana 15,33% × regressão 28,70%: discordam 5,8 erros-padrão → **não identificado**; a âncora de inflação (4,92%) é financiável (exige reter 36%, e a empresa retém 100%) → g = 4,92% |
| Custo da dívida | alavancagem 2,4× daria prêmio de 2,4%; a cobertura (EBIT ÷ juros = 1,24) está na faixa em que fala, e dá **9,0%**; vale o maior → Kd = 23,09% |
| WACC de hoje | 0,5415 × 15,84% + 0,6057 × 23,09% × 0,66 − 0,1472 × 14,09% × 0,66 = **16,4%** |
| Perpetuidade | barrada: crescimento inorgânico, e retorno do ciclo (13,83%) abaixo do custo de equilíbrio (16,6%) |

---

## 3. Onde a conta para: o ponto fixo

Com beta desalavancado, o motor resolve o custo de capital ano a ano contra a
dívida que a própria avaliação produz (capítulo 3, seção 3.10). Para isso ele
precisa do valor do capital próprio de cada ano:

```
capital próprio_t = valor da operação_t − dívida líquida_t
```

Já na **primeira volta**, no **ano zero**, esse número deu **negativo**. O motor
tentou de novo partindo do custo desalavancado (item B18, decisão 110) e também
não fechou. Recusa.

**A ordem de grandeza, à mão** (aproximada, só para ver o tamanho):

```
alíquota estrutural ≈ 26%;  NOPAT 2025 ≈ 7,81 × 0,74 ≈ R$ 5,8 bi
ROIC ≈ 9,7%;  para crescer 4,9% é preciso reter 4,9 ÷ 9,7 ≈ 51% do NOPAT
fluxo livre do ano 1 ≈ 5,8 × 1,049 × (1 − 0,51) ≈ R$ 3,0 bi
valor da operação ≈ 3,0 ÷ (0,164 − 0,049) ≈ R$ 26 bi
dívida líquida = R$ 33 bi   →   capital próprio ≈ 26 − 33 < 0
```

(A conta do motor é mais completa — dez anos, retorno convergindo, meio de ano,
realavancagem —, mas a conclusão é a mesma.)

**Traduzindo:** a operação da Localiza rende cerca de 10% sobre o capital, e o
motor diz que esse capital custa cerca de 16,4%. Nessa conta, cada real investido
vale menos que um real, e a empresa inteira vale menos que o que ela deve.

---

## 4. Por que recusar, e não dar um número?

Três alternativas foram consideradas e rejeitadas pelo projeto:

1. **Dar o número negativo, ou zero.** Um preço justo de R$ 0 diria "a ação não
   vale nada", o que é mais forte do que o método sustenta. O que a conta diz é
   que **este método, com estas premissas, não avalia esta estrutura de
   capital**.
2. **Trocar para a via do acionista.** Ela parte do lucro líquido (R$ 1,87 bi) e
   daria algum número. Mas escolher o modelo **porque** o primeiro recusou faria
   o preço justo depender de qual conta alcançou um resultado — e aí qualquer
   ativo sempre teria preço (decisão 102).
3. **Usar a taxa de um ano só, sem realavancar.** Esconderia o problema: com
   alavancagem alta, a taxa de hoje e a de daqui a cinco anos não são a mesma.

A recusa aparece na tela com o motivo, e o painel de logs mostra todos os passos
até ela.

---

## 5. O que o mercado vê e o motor não

O mercado paga R$ 39 bi pelas ações da Localiza. Para isso, ele precisa
acreditar em pelo menos uma destas coisas, que o motor não supõe:

- o retorno sobre o capital volta ao nível anterior à fusão (acima de 13%) —
  o motor vê uma tendência de queda estatisticamente clara e mantém a base;
- a Localiza capta mais barato que 23% ao ano — o motor usa o prêmio da
  cobertura de juros, que é baixa (1,24);
- o capital de uma locadora (os carros) vale mais na revenda do que o fluxo
  descontado diz — o motor não avalia ativos, só fluxos.

Qualquer uma delas pode ser verdade. O motor não tem como saber qual, e por isso
não dá preço.

---

## 6. O que este caso ensina

- **Recusar é um resultado.** Em 14/09/2026, o motor recusou 268 dos 376 ativos
  que chegaram a ele — a maioria por liquidez ou falta de histórico, e algumas,
  como a Localiza, porque a conta não fecha.
- **Alavancagem alta torna o preço por ação frágil.** Quando o capital próprio é
  uma fatia pequena do valor da firma, pequenos erros no valor da operação viram
  erros enormes no valor da ação. É por isso que existe a ressalva "ponte frágil"
  (capital próprio abaixo de 35% do valor da firma) e o item B34 do plano, que
  propõe mostrar o tamanho dessa fragilidade.
