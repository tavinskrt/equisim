# O minoritário nos pesos do WACC — item B23

> **Medido em 21/09/2026**, sobre a entrada congelada do gabarito da cascata.
>
> ```bash
> dart run tool/gabarito_cascata.dart   # congela a entrada
> dart run tool/minoritario.dart        # grava minoritario.json
> ```
>
> Montagem de hoje conferida contra o gabarito ativo a ativo: **zero
> divergências**.

## 0. A acusação

Da lente `metodo`, em 21/09/2026: o fluxo que o WACC desconta é o
**consolidado**, e o peso do capital próprio é `divisor × preço`, que é o valor
de mercado da **controladora**. A fatia dos não controladores fica fora do
denominador `E + D`, o que infla a participação da dívida e achata o WACC.

A acusação está certa sobre a fórmula. **O que ela não diz é onde isso morde.**

## 1. O escopo é menor que a acusação, e é medível

**O caminho resolvido não tem o problema.** A realavancagem do ponto fixo
pondera por `E_t = V_t − D_t`, onde `V` é o valor da firma sobre um fluxo
**consolidado**: esse `E` já inclui a fatia dos não controladores. Só o WACC
**estático** — que é o recuo — usa o valor de mercado da controladora.

E a via do acionista não tem WACC nenhum: ela desconta o fluxo do acionista ao
`Ke`, e não há peso onde o minoritário pudesse faltar.

**Então a exposição exige três condições ao mesmo tempo.** Nos 97 avaliados:

| | |
|---|---:|
| avaliados | 97 |
| pela via da firma (têm WACC) | 77 |
| recuam ao WACC estático | 19 |
| **via da firma E estático** | **0** |
| têm minoritário publicado | 64 |
| com fatia ≥ 1% do consolidado | 33 |
| **firma, estático E material** | **0** |

**A interseção é vazia.** Os 19 que recuam ao estático são todos da via do
acionista — bancos, seguradoras e o que a Porta 1 roteia —, e os 77 da via da
firma resolvem as taxas sem exceção.

E o minoritário não é pequeno: **31,6% do consolidado** no extremo, 10,9% no p90.
O defeito não morde por causa do **caminho**, e não por causa do tamanho.

## 2. E impor o minoritário no peso não move nada

Duas formas, as duas medidas:

- **contábil puro** — soma `minorityInterest` ao `E` de mercado, e o
  denominador passa a ter duas unidades;
- **pelo `P/VP` do controlador** — `PL_min × (E_mercado ÷ PL_contr)`, que supõe
  que o minoritário negocia à mesma razão preço/patrimônio. Não mistura
  unidades, e é a defensável das duas.

| forma | avaliados | preço justo | Δ desconto | postos |
|---|---:|---:|---:|---:|
| contábil | 97 | **0,00%** | — | 1,0000 |
| pelo `P/VP` | 97 | **0,00%** | — | 1,0000 |

**Zero, ao centavo, nos 97.** É a confirmação numérica do §1: o peso estático
nunca chega ao resultado quando as taxas resolvem — nem pela porta dos fundos,
já que o ponto fixo é independente da partida desde a
[decisão 110](../decisoes/110-o-ponto-fixo-e-tentado-de-duas-partidas-e-a-recusa-deixa-de-ser-do-chute.md).

## 3. Vazia hoje não é vazia sempre

**Um ativo da via da firma pode recuar ao estático** — sem beta desalavancado, ou
com o ponto fixo não convergindo —, e nesse dia, com minoritário material, o
desconto sai achatado sem que nada diga.

Por isso o que entrou no motor não foi o ajuste, e sim a **condição**: quando as
três se encontrarem, a avaliação declara, com a fatia medida.

Nas montagens de diagnóstico do gabarito — `curva`, `doisPontos` e `impostos`,
que desligam o caminho resolvido de propósito — o aviso já aparece em **64
montagens**, e **nenhum preço justo muda**. É a prova de que ele mede o que diz
medir.

## 4. O que se decidiu

[Decisão 120](../decisoes/120-o-minoritario-fica-fora-do-peso-e-a-condicao-de-exposicao-e-declarada.md):
**o ajuste é recusado, e a condição de exposição é declarada.**

- Recusado porque **o dado não existe**: o valor de **mercado** do minoritário
  não é observável, e as duas formas de contorná-lo ou misturam unidades no
  mesmo denominador, ou supõem que ele negocia ao `P/VP` do controlador — que é
  premissa sem evidência.
- E recusado porque **não muda nada**: 0,00% nos 97, postos de 1,0000.
- Declarado porque o motor não pode depender de a interseção continuar vazia.

## 5. O que isto não diz

- **Não mede o `P/VP` real do minoritário.** Ele não é negociado, e por isso a
  forma (b) é suposição, e não medição. Se um dia houver participação relevante
  negociada em bolsa dentro da mesma consolidação, a suposição vira testável.
- **A ponte continua devolvendo a parcela** (decisão 49): o minoritário sai do
  valor do acionista ao final, e isso nunca esteve em questão. O que este
  documento examina é só o **peso da taxa**.
- **A interseção vazia é do universo de 14/09/2026.** Outro universo, outra
  data, ou uma mudança que faça a via da firma recuar mais podem preenchê-la —
  e é por isso que o aviso existe.
