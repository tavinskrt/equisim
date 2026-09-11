# A ida e a volta do beta não se cancelavam

Medido em 11/09/2026.

```bash
dart run tool/beta_ida_volta.dart   # grava beta_ida_volta.json
```

---

## 0. Dois defeitos na mesma volta

O beta é desalavancado numa ponta e realavancado na outra. Para que a operação
signifique alguma coisa, a volta tem de desfazer a ida — e não desfazia, por
duas razões independentes.

```
β_U   = β_L / (1 + (1 − τ)·D/E)     ← PrepareValuationInputs
β_L,t = β_U · (1 + (1 − τ)·D_t/E_t) ← LeveredCostOfCapital
```

**Primeiro: as duas usavam dívidas diferentes.** A ida, a dívida **bruta**; a
volta, a **líquida**.

**Segundo: a ida partia do beta errado.** `ShrunkBeta.unlevered` era o
desalavancado do beta **cru**, enquanto `ShrunkBeta.beta` era o **encolhido** —
e o ponto fixo relavanca `unlevered` e nunca toca em `beta`.

## 1. Bruta contra líquida

| fator da ida ÷ fator da volta | valor |
|---|---:|
| p10 | 1,000 |
| **mediana** | **1,092** |
| p90 | 1,396 |
| acima de 1,10 | 60 de 127 |
| acima de 1,50 | 9 |

**O beta que voltava era menor que o medido em 100 dos 127 avaliados.** A conta
não é simétrica: a ida divide por um fator grande e a volta multiplica por um
pequeno, e o que sobra é subestimação sistemática do risco.

**Trinta e duas empresas têm caixa líquido.** Nelas a dívida líquida é negativa,
o fator da volta está no piso, e a ida divide sem que a volta multiplique nada
de volta.

Onde a distância é maior:

| Ativo | D/E bruta | D/E líquida | ida ÷ volta |
|---|---:|---:|---:|
| SAPR4 | 213,0% | 51,4% | **1,873** |
| SAPR11 | 204,9% | 49,5% | 1,849 |
| EVEN3 | 179,6% | 61,9% | 1,634 |
| HAPV3 | 365,7% | 142,2% | 1,574 |
| USIM3 | 71,3% | **−6,2%** | 1,558 |

No custo do capital próprio isso vale **mediana de 0,42 p.p., p90 de 2,66 p.p.**,
com 42 dos 127 acima de um ponto e 11 acima de três.

### Qual das duas é a régua

A líquida, e não por gosto: **é a dívida que o resto do motor usa** — a ponte
`EV − D`, os pesos do WACC, o capital investido. Trocar a régua da
realavancagem exigiria trocar as três, e ainda contradiria a definição de
capital investido.

E é a economicamente correta: caixa é ativo de beta baixo, e o beta do negócio
operacional é maior que o da ação de uma empresa cheia de caixa. A bruta ignora
o caixa.

A régua passou a viver num lugar só —
`FundamentalsSnapshot.debtToMarketEquity` — usada pelas duas pontas da
desalavancagem, com a razão escrita ali.

## 2. O encolhimento não chegava ao preço

`BetaShrinkage.shrink` devolvia `beta` encolhido e `unlevered` derivado do
**cru**. Como o caminho resolvido relavanca `unlevered`, o encolhimento da
[decisão 40](../decisoes/040-beta-encolhido-por-precisao.md) **não alcançava a
maioria do universo**: ela existe para trocar precisão por viés, e a troca não
chegava ao número.

A correção é derivar o desalavancado do próprio beta que sai:

```
encolhido / f = w·(β_L/f) + (1 − w)·β_U,prior = w·β_U + (1 − w)·β_U,prior
```

Encolher em espaço alavancado e desalavancar o resultado é **idêntico** a
encolher em espaço desalavancado, porque o fator é o mesmo dos dois lados. A
identidade `unlevered × fator == beta` passa a valer por construção, e está
travada por teste.

### E o tamanho disso é pequeno — pelo motivo que importa

| peso do próprio ativo no encolhimento | valor |
|---|---:|
| p10 | 0,954 |
| **mediana** | **0,985** |
| p90 | 0,993 |
| abaixo de 0,90 | **1 de 127** |

**O encolhimento é quase inerte neste universo.** A precisão da regressão
individual domina a do prior setorial em praticamente todo ativo, porque a
dispersão setorial dos betas é grande. A diferença entre desalavancar o cru e
desalavancar o encolhido é de **0,5% na mediana** e 2,5% no p90.

Isso não torna a correção dispensável — uma identidade que vale por acidente de
calibragem não vale —, mas é o registro honesto de que a decisão 40 move pouco
o preço, e de que o defeito grande dos dois é o da §1.

## 3. O efeito no universo

| | antes | depois |
|---|---:|---:|
| potencial mediano | −31,8% | **−37,5%** |
| potencial p25 | −65,0% | −67,9% |
| potencial p75 | +11,4% | **+4,5%** |
| potenciais positivos | 40 | **35** |
| **preços justos alterados** | — | **96 de 127** |
| variação mediana | — | **−7,2%** |
| **sobem** | — | **0** |

**Noventa e seis caem e nenhum sobe.** A direção é a esperada e não podia ser
outra: corrigir a ida eleva o beta desalavancado, a volta o realavanca sobre um
número maior, o custo do capital próprio sobe e o valor cai. EVEN3 −39,0%,
KLBN3 −25,1%, GOAU4 −22,2%, USIM3 −22,2%.

Isto desfaz parte do que rodadas anteriores tinham somado, e não há nada a
lamentar nisso: o que somava era um beta subestimado.

## 4. O que fica declarado

**O confinamento de `D/E` em `[0; 3]` continua**, e com caixa líquido ele leva
o fator ao piso — de modo que `β_U = β_L` para as 32 empresas nessa situação.
A Hamada com dívida líquida negativa daria `β_U > β_L`, e o piso é a leitura
conservadora. A ida e a volta se cancelam de qualquer forma, porque o mesmo
piso vale nos dois lados.

**O beta continua medido sobre retorno diário de cotação não ajustada**, e é o
item que a lente `metodo` reincidiu em cinco rodadas. Ele é independente deste,
e continua aberto.

---

## 5. E a janela: desalavancar cinco anos com a foto de um dia

Corrigida a régua da dívida, sobra a **data**. O beta é covariância de **cinco
anos** de retorno diário — carrega a estrutura de capital daqueles cinco —, e a
alavancagem que o desalavancava era a do último exercício.

| fator da janela ÷ fator de hoje | valor |
|---|---:|
| p10 | 0,695 |
| mediana | 0,984 |
| p90 | 1,112 |
| **distante mais de 10%** | **50 de 124** |
| distante mais de 25% | 24 |
| a janela é mais alavancada | 28 de 124 |

**A mediana é quase um e as caudas são grossas**: metade do universo passa
perto, e um quinto está a mais de 25% de distância. Em 96 dos 124 a empresa
está mais alavancada hoje do que esteve na janela — alavancaram no período, e
desalavancar o beta pela foto de hoje divide por um fator grande demais.

| Ativo | D/E hoje | D/E na janela |
|---|---:|---:|
| MILS3 | **168.056,3%** | 13,5% |
| ANIM3 | 1.655,1% | 269,8% |
| COGN3 | 842,8% | 87,4% |
| CPLE3 | 386,1% | 49,8% |
| CSNA3 | 401,6% | 142,4% |

### A MILS3 é um achado de dado, não de alavancagem

Dívida líquida de R$ 1,28 bi contra valor de mercado de **R$ 762 mil**. O
`marketCap` corrente que a fonte publica para ela está errado por três ordens
de grandeza, e o D/E saturava no teto de 3,0 da
[decisão 40](../decisoes/040-beta-encolhido-por-precisao.md).

A medida por janela a conserta de lado: ela reconstrói o valor de mercado de
cada exercício por **preço do pregão × ações daquele exercício**, sem tocar no
campo publicado. Mas o campo continua errado onde mais nada o substitui — fica
declarado.

### A correção

`MarketLeverage.overWindow` devolve a **mediana** de `dívida líquida ÷ valor de
mercado` nos exercícios da janela, com o valor de mercado de cada um
reconstruído pelo pregão mais próximo do fechamento e pela contagem de ações
**daquele exercício**.

Mediana e não média: um exercício de valor deprimido domina a média e não a
mediana, e o que se quer é a estrutura típica, não a pior. Com menos de três
exercícios utilizáveis, recua para a foto — o comportamento anterior.

### O efeito

| | antes | depois |
|---|---:|---:|
| potencial mediano | −37,5% | **−41,8%** |
| potencial p25 | −67,9% | −71,4% |
| potenciais positivos | 35 | 34 |
| **preços justos alterados** | — | **88 de 127** |
| variação mediana | — | −4,0% |
| **caem / sobem** | — | **65 / 23** |

**Agora vai nos dois sentidos**, ao contrário da correção da §1: a janela pode
ser mais ou menos alavancada que hoje, e o beta acompanha. CSAN3 −68,2%,
MILS3 −50,0%, KLBN11 −40,6% de um lado; UGPA3 +32,2%, ENEV3 +26,6%, JHSF3
+20,3% do outro.

---

## 6. A terceira assimetria: o escudo fiscal

Corrigidas a régua da dívida e a data, sobrou a **alíquota**. A ida usava a
estrutural do ativo; a volta, a estatutária.

```
β_U   = β_L / (1 + (1 − τ_estrutural)·D/E)   ← ida
β_L,t = β_U · (1 + (1 − τ_estatutária)·D/E)  ← volta
```

O `(1 − τ)` de Hamada **é o escudo fiscal do juro**, e o projeto já tinha
decidido que ele fica na estatutária — está escrito em `nopatAtRate`, da
[decisão 37](../decisoes/037-aliquota-estrutural-no-fluxo-da-firma.md):

> Não confundir com o escudo fiscal do WACC, que continua na estatutária e deve
> continuar: a dedutibilidade do juro vale na margem, e a margem é a alíquota
> cheia.

A estrutural é a alíquota do **fluxo**. As duas medem coisas diferentes, e a
ida estava usando a errada.

Com a mediana estrutural do universo em 18,6% contra 34%, o termo da dívida saía
**23% maior na ida do que na volta**.

| | antes | depois |
|---|---:|---:|
| potencial mediano | −41,8% | −41,0% |
| **preços justos alterados** | — | **76 de 127** |
| variação mediana | — | −2,1% |
| caem / sobem | — | 75 / 1 |

CSAN3 −65,9%, YDUQ3 −16,7%, ANIM3 −14,2%, LOGG3 −12,7%.

---

## 7. Três assimetrias, uma volta

| Dimensão | A ida usava | A volta usa | Onde ficou |
|---|---|---|---|
| **qual dívida** | bruta | líquida | líquida, nas duas |
| **qual data** | foto de hoje | caminho do modelo | mediana da janela do beta |
| **qual alíquota** | estrutural | estatutária | estatutária, nas duas |
| **qual beta** | cru | — | encolhido |

Nenhuma delas era visível de fora: cada ponta estava certa isoladamente, e o
defeito só existe na composição. É o mesmo formato do que a
[decisão 45](../decisoes/045-estrutura-de-capital-recusada.md) encontrou entre
recusa e recuo, e do que a [51](../decisoes/051-ponto-fixo-do-veredito-e-referencia-do-terminal.md)
encontrou entre veredito e taxa — **o motor erra nas costuras, não nas peças**.
