# Por que τ = 0,5 na normalização do fluxo-base

> **⚠ Superado pela [decisão 25](../decisoes/025-reconstrucao-do-motor-de-avaliacao.md).**
> A winsorização descrita aqui **não existe mais**: `base_flow.dart` foi removido em
> 07/09/2026 e a banda `τ` não é mais aplicada. O que a substituiu é a convergência de
> retorno — o fluxo-base deixa de ser aparado contra uma mediana e passa a ser derivado do
> retorno sobre a base de capital, com o reinvestimento amarrado ao crescimento por
> `b_t = g_t / retorno`. Ver a §5 do [refinamento](../refinamento-do-valuation.md).
>
> A medição que justificou `τ = 0,5` continua válida como registro do problema que motivou a
> troca, e é por isso que o documento fica. O código que ele cita não existe mais — o link
> abaixo está morto de propósito, e não deve ser restaurado.

Medições feitas em 28/08/2026 sobre os 18 ativos das carteiras de teste,
exercícios de 2010 a 2025 (fonte: brapi.dev, `/v2/stocks/cash-flow`,
`mode=history`). Código: `base_flow.dart`, removido.

```
F₀ = min( max( F_obs , m·(1−τ) ) , m·(1+τ) )
```

`F_obs` é o fluxo do exercício mais recente, `m` a mediana dos cinco últimos
exercícios publicados e `τ` a meia-largura da banda, em fração da mediana.

---

## 1. O que τ realmente controla

O DCF por FCFF é **exatamente homogêneo de grau 1 no fluxo-base**. Dobrar `F₀`
dobra o valor da firma, sem resto — o crescimento, o desconto e a perpetuidade
entram todos como fatores multiplicativos.

Verificado executando `DcfCalculator.fcff` com `r = 13%`, `g = 8%`,
`g∞ = 4,5%`, `N = 5`:

| `F₀` | EV | razão |
|---|---|---|
| `m` | 6,6356 bi | 1,000000 |
| `1,5·m` | 9,9534 bi | **1,500000** |
| `2,0·m` | 13,2712 bi | **2,000000** |

A dívida líquida entra depois, por subtração, e **amplifica** o efeito no preço
por ação: com `D_liq = 1,7 bi` no exemplo acima, `EV/(EV−D) = 1,206`, e uma
folga de +33,3% em `F₀` (τ de 0,5 para 1,0) vira **+40,2% no preço justo**.

Logo τ não é um detalhe de limpeza de dados. Ele responde a uma pergunta de
política, não de estatística:

> **Quanto se autoriza um único exercício a mover a avaliação inteira da
> empresa?**

Com τ = 0,5, a resposta é: no máximo 1,5× — e no mínimo 0,5× — o que a empresa
entrega num exercício típico.

---

## 2. Por que não é um critério de detecção de atípico

A tentação é apresentar τ como "o ponto onde o exercício deixa de ser normal".
**Os dados não sustentam essa leitura, e afirmá-la na defesa seria frágil.**

Sobre as 151 janelas de cinco exercícios com mediana positiva das 18 séries:

| Critério robusto clássico | τ implícito (p25 / mediana / p75) |
|---|---|
| `2·MAD / m` (≈ 1,35 σ) | 0,45 / **0,80** / 1,43 |
| `3·MAD / m` | 0,68 / **1,19** / 2,14 |
| Cerca de Tukey superior, `(Q₃+1,5·IQR)/m − 1` | 0,79 / **1,30** / 2,38 |
| Cerca de Tukey inferior, `1 − (Q₁−1,5·IQR)/m` | 0,83 / **1,39** / 3,00 |

Todos os critérios clássicos pediriam bandas **mais largas** que 0,5 — entre
1,6× e 2,8× mais largas na mediana. O valor 0,5 fica perto do **primeiro
quartil** deles.

Dito de outro modo: fluxo de caixa de empresa brasileira é volátil o bastante
para que `±50% da mediana` seja uma banda apertada. Apenas **58% de todas as
observações** das janelas caem dentro dela.

**A justificativa correta é, portanto, a da seção 1: τ = 0,5 é um teto
deliberadamente conservador sobre a influência de um exercício, escolhido
porque a perpetuidade amplifica o erro em vez de diluí-lo — não uma fronteira
estatística entre "normal" e "atípico".**

---

## 3. O que τ = 0,5 faz nas carteiras de teste

Onze dos dezoito ativos chegam ao DCF por FCFF com banda válida (`F_obs > 0` e
`m > 0`). Fator de desvio `F_obs/m` medido:

| Ativo | `F_obs/m` | τ=0,3 | τ=0,5 | τ=0,75 | τ=1,0 |
|---|---|---|---|---|---|
| VALE3 | 0,30 | apara ↑ | **apara ↑** | — | — |
| PETR4 | 0,65 | apara ↑ | — | — | — |
| VIVT3 | 1,00 | — | — | — | — |
| ABEV3 | 1,03 | — | — | — | — |
| WEGE3 | 1,12 | — | — | — | — |
| TOTS3 | 1,40 | apara ↓ | — | — | — |
| BBSE3 | 1,49 | apara ↓ | — | — | — |
| RADL3 | 1,54 | apara ↓ | **apara ↓** | — | — |
| AZZA3 | 2,34 | apara ↓ | **apara ↓** | apara ↓ | apara ↓ |
| KLBN11 | 3,71 | apara ↓ | **apara ↓** | apara ↓ | apara ↓ |
| SAPR11 | 9,51 | apara ↓ | **apara ↓** | apara ↓ | apara ↓ |
| **total aparado** | | 8/11 | **5/11** | 3/11 | 3/11 |

Efeito sobre o fluxo-base dos aparados, em `F₀/F_obs`:

| τ | VALE3 | RADL3 | AZZA3 | KLBN11 | SAPR11 |
|---|---|---|---|---|---|
| 0,3 | 2,31× | 0,84× | 0,56× | 0,35× | 0,14× |
| **0,5** | **1,65×** | **0,97×** | **0,64×** | **0,40×** | **0,16×** |
| 0,75 | — | — | 0,75× | 0,47× | 0,18× |
| 1,0 | — | — | 0,86× | 0,54× | 0,21× |

### Por que não apertar para 0,3

Aparia 8 de 11. Uma banda que morde a maioria dos casos deixa de ser tratamento
de exceção e vira **encolhimento em direção à mediana**: o modelo passaria a
reportar, na prática, "1,3× a mediana" para quase toda empresa em crescimento.
BBSE3 (1,49×) e TOTS3 (1,40×) não têm exercício atípico — têm crescimento —, e
seriam cortadas.

### Por que não afrouxar para 1,0

Não resolve o caso que motivou o mecanismo. Com τ = 1,0 a SAPR11 entra na
perpetuidade com `2·m` em vez de `1,5·m` — 33% a mais de valor de firma, para
um exercício em que o caixa operacional (R$ 7,06 bi) superou o EBITDA
(R$ 2,34 bi), o que caracteriza variação de capital de giro, não geração
recorrente.

---

## 4. Consequências que precisam estar declaradas

**A banda é de mão dupla, e o lado de baixo é o menos intuitivo.** VALE3 teve
`F_obs = 0,30·m`: a winsorização **elevou** o fluxo-base em 1,65×, aumentando o
preço justo. É o comportamento pretendido — um exercício ruim isolado também
não deve definir a perpetuidade —, mas quem lê o painel precisa saber que a
normalização pode subir o preço, não só descê-lo.

**Mediana não positiva desliga o tratamento.** EQTL3, PRIO3 e RENT3 têm mediana
de cinco anos negativa (investindo acima da geração de caixa). Nesses casos o
normalizador devolve `F_obs` intacto — justamente os ativos de fluxo mais
errático são os que ficam sem banda. É deliberado (não há banda relativa em
torno de mediana negativa), mas é uma lacuna real, e o painel emite o aviso
correspondente.

**A janela pode não ser contígua.** A série alimentada ao normalizador descarta
exercícios sem valor publicado, então "os cinco últimos" podem alcançar um ano
mais antigo do que aparenta. O painel agora rotula cada ponto com o ano fiscal
e emite um aviso explícito quando detecta a descontinuidade.

---

## 5. Como mudar, se a orientação for outra

`τ` é `BaseFlowNormalizer.defaultTolerance`, e `normalize` já aceita
`tolerance:` por parâmetro nomeado — não há valor mágico espalhado pelo código.
Alterá-lo exige atualizar os testes de
[`usecases_test.dart`](../../packages/equisim_core/test/usecases_test.dart)
que fixam a borda em `1,5·m`, e **este documento**, que é a justificativa que
acompanha a escolha.

Os números desta página são reprodutíveis: a série de fluxo de caixa vem de
`/v2/stocks/cash-flow?mode=history` e a mediana é a dos cinco últimos
exercícios publicados de cada ativo.
