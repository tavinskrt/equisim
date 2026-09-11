# A discordância entre as duas vias

Medida em 10/09/2026, sobre os 92 ativos em que as duas vias são avaliáveis.

```bash
dart run tool/vias.dart   # grava vias.json
```

> **Remedida.** As §§0 a 7 registram a discordância contra a via da firma
> anterior às decisões 41 a 44 e a transição contínua que a decisão 38 criou;
> a §8 registra a remedição depois delas — a discordância continua, e deixou
> de decidir.

---

## 0. Por que esta medição

A pós-condição da ponte de equity escolhia entre a via da firma e a do
acionista por um limiar de 20% de participação do capital próprio. A
[decisão 37](../decisoes/037-aliquota-estrutural-no-fluxo-da-firma.md) mostrou
o quanto essa escolha decide: nove ativos trocaram de via ao receber a alíquota
correta, e caíram de 58,9% a 92,1%.

A [decisão 34](../decisoes/034-fronteira-das-vias-medida-na-taxa-estrutural.md)
já havia registrado o problema sem resolvê-lo — *"Isto não concilia as duas
vias, que seguem discordando por medirem crescimento e base em séries de
capital diferentes"*. Conciliar exige primeiro saber o tamanho e a forma da
discordância.

**Em teoria as duas não deveriam discordar.** `FCFF/WACC` e `FCFE/Ke` são a
mesma avaliação vista de dois lados, e coincidem quando os insumos são
consistentes. A distância entre elas mede **inconsistência interna do motor**,
não diferença de método.

A medição exigiu avaliar as duas vias no mesmo ativo, o que o roteamento impede
por construção — daí a costura `laneOverride`, que força a via e desliga a
migração, declarando a imposição no resultado.

---

## 1. O tamanho da discordância

Razão entre o preço justo da firma e o do acionista:

| p10 | p25 | mediana | p75 | p90 |
|---:|---:|---:|---:|---:|
| 0,35× | 0,64× | **1,04×** | 1,75× | 2,44× |

**A mediana é 1,04× — em agregado as duas vias concordam.** A dispersão é que
não: **55 dos 92 discordam além de 1,5×**, e **33 além de 2×**.

Não é viés sistemático de uma via contra a outra. É ruído de especificação, e
ele é grande.

## 2. De onde vem

As três fontes que a decisão 34 nomeou, medidas:

| Fonte | mediana | dispersão |
|---|---:|---|
| crescimento (firma − acionista) | 0,0% | \|dif\| > 3 p.p. em **43 de 92** |
| fator de base (firma ÷ acionista) | 1,00× | fora de [0,8; 1,25] em **34 de 92** |
| desconto (WACC − Ke) | **−2,7 p.p.** | \|dif\| > 2 p.p. em **59 de 92** |

O desconto é a fonte mais frequente, e a única com mediana deslocada — o que é
esperado e correto: com dívida, o WACC fica abaixo do Ke. As outras duas têm
mediana nula e caudas largas: o crescimento e a normalização medidos sobre
capital investido e sobre patrimônio líquido divergem em quase metade do
universo, sem direção preferencial.

## 3. Nenhuma das duas é mais próxima do mercado

| | firma | acionista |
|---|---:|---:|
| fica mais perto do preço | 39 | 53 |
| erro mediano \|justo/preço − 1\| | 59,1% | 53,3% |

O mercado não arbitra. Não há base empírica para preferir uma via à outra em
geral — o que existe é a razão estrutural da pós-condição: com a dívida líquida
consumindo o valor da firma, o preço por papel vira resíduo de subtração, e o
erro relativo chega amplificado por `1/s`.

## 4. A faixa exposta

Dezessete ativos têm participação entre 5% e 35%, e é neles que o limiar
decidia:

| Ativo | s | firma | acionista | razão |
|---|---:|---:|---:|---:|
| ENGI11 | 9,5% | 7,11 | 94,13 | **0,08×** |
| VBBR3 | 13,9% | 2,65 | 33,71 | **0,08×** |
| PRIO3 | 20,6% | 7,46 | 53,88 | 0,14× |
| AGRO3 | 13,2% | 1,72 | 8,99 | 0,19× |
| SBFG3 | 13,3% | 1,51 | 6,14 | 0,25× |
| MULT3 | 19,4% | 2,19 | 6,25 | 0,35× |
| KLBN3 | 11,2% | 0,52 | 1,33 | 0,39× |
| HYPE3 | 27,3% | 4,08 | 10,32 | 0,40× |
| YDUQ3 | 26,4% | 5,57 | 2,44 | **2,28×** |
| QUAL3 | 22,5% | 0,89 | 0,17 | **5,24×** |

Na faixa baixa a via da firma entrega sistematicamente menos — é a amplificação
que a pós-condição existe para conter. Mas YDUQ3 e QUAL3 mostram que a direção
não é lei.

---

## 5. A correção

Implementada pela [decisão 38](../decisoes/038-transicao-continua-entre-as-vias.md).

**O peso da via da firma passa a ser contínuo na participação**, percorrendo a
faixa que o projeto **já declarava frágil**:

```
s ≤ 0,20            → 0    (só o acionista, como antes)
0,20 < s < 0,35     → (s − 0,20) / 0,15
s ≥ 0,35            → 1    (só a firma, como antes)
```

Os dois cortes existem desde antes: `minEquityShare = 0,20` marca onde a ponte
deixa de ser utilizável, e `fragileEquityShare = 0,35` marca onde ela deixa de
ser frágil. **Nenhum parâmetro novo** — o que muda é que os dois passam a
delimitar uma transição em vez de um degrau.

**Combina o número, não os cenários.** Duas vias que discordam por múltiplos não
têm banda comum, e apresentar a da firma em torno de um ponto que é média das
duas afirmaria uma dispersão que nenhuma mediu. A banda sai; os dois valores de
origem e o peso viajam no aviso, e a ressalva `viasMescladas` marca o resultado.

### O efeito

| | antes | depois |
|---|---:|---:|
| potencial mediano | −42,3% | **−40,0%** |
| potencial p25 | −72,3% | −70,3% |
| potenciais positivos | 28 | 28 |
| preços justos alterados além de 0,5% | — | **11 de 122** |

Os onze são exatamente os da faixa exposta:

| Ativo | variação |
|---|---:|
| VBBR3 | **+760,4%** |
| SBFG3 | +251,0% |
| AGRO3 | +227,9% |
| PRIO3 | +149,3% |
| KLBN3 | +111,5% |
| KLBN4 | +101,9% |
| KLBN11 | +96,7% |
| MULT3 | +71,7% |
| MYPK3 | +27,8% |
| MOTV3 | +4,3% |
| QUAL3 | **−23,6%** |

**São os mesmos que a decisão 37 tinha derrubado.** Não porque aquela decisão
estivesse errada — a alíquota estrutural continua valendo —, e sim porque o que
os derrubava era o degrau que ela fez cruzar. Removido o degrau, o valor deles
deixa de depender de onde a participação cai em relação a um corte.

A QUAL3 é o caso contrário e por isso vale registrá-lo: com `s = 22,5%` ela
entra na transição, e a via do acionista dá 0,17 contra 0,89 da firma. Ela
**perde** 23,6%. A regra não é "restaurar valor", é "não saltar".

---

## 6. O que a correção não faz

**Não concilia as duas vias.** A VBBR3 continua valendo R$ 2,65 por uma e
R$ 33,71 pela outra; o que mudou é que a resposta não salta mais entre as duas
quando um parâmetro se move. Na faixa de transição, o preço justo é média
ponderada de dois números que discordam por ordem de grandeza — e a ressalva
`viasMescladas` existe para dizer exatamente isso.

Conciliar de verdade exige que crescimento, normalização da base e
reinvestimento saiam de um único conjunto de premissas, com a alavancagem
ligando `Ke` e `WACC`. Isso é reconstrução da Porta 2, não ajuste de fronteira.

## 7. O que fica em aberto

1. **A inconsistência interna continua**, e agora está medida: 55 de 92 além de
   1,5×, 33 além de 2×. É a maior pendência de método do motor.
2. **A faixa de transição é linear**, e a forma é escolha. Uma ponderação por
   precisão — o erro da firma escala com `1/s` — teria fundamento mais forte, e
   exigiria estimar a variância de cada via.
3. **Ativos fora da faixa continuam com uma via só**, e para eles a
   discordância permanece invisível no resultado.

---

## 8. D2 — remedida depois das decisões 41 a 44 (10/09/2026)

A §7 mediu a discordância contra a via da firma **antiga**: interpolação de
dois pontos e ponte `EV − D`. As decisões 41 a 44 trocaram as duas coisas. A
pergunta do D2 é outra, e mais estreita que a original:

> A discordância ainda **decide** alguma coisa?

Discordância que não escolhe nada é fato registrado. Discordância que escolhe é
defeito.

### 8.0 A primeira medição estava medindo o motor velho

`_porVia` reconstrói o `ValuationInputs` campo a campo para impor a via, e não
copiava `unleveredBeta`. Sem ele a via da firma cai na interpolação — de modo
que a rodada comparava **o motor de antes da decisão 42** contra a via do
acionista, e devolvia mediana de 1,03×, praticamente a mesma de §1.

Fica o aviso, que vale para toda costura de diagnóstico: **quem reconstrói o
insumo herda a obrigação de copiar tudo**, e um campo esquecido não falha —
mede outra coisa em silêncio.

### 8.1 O que a medição correta encontrou

Com `β_U` no lugar, 96 ativos tinham as duas vias avaliáveis. Noventa recebiam
o caminho resolvido. **Os seis restantes eram exatamente os seis que ainda
eram mesclados e migrados** — e a coincidência não é acidente:

| Ativo | por que o solucionador recusou |
|---|---|
| AGRO3, MYPK3, PRIO3 | capital próprio não positivo **no ano zero** |
| KLBN3, KLBN4, KLBN11 | WACC de equilíbrio abaixo do crescimento perpétuo |

Em todos a recusa vem na **segunda ou terceira iteração** — depois de a
realavancagem corrigir a taxa, e não por o ponto fixo ter passeado. A primeira
iteração parte da interpolação; sobreviver a ela e morrer na seguinte é a
definição de "a interpolação não enxergava o problema".

E o que o motor fazia com essa recusa: **recuava para a interpolação**, que
produz preço porque desconta pela taxa que a realavancagem acabara de
rejeitar — e então mesclava esse preço com o da via do acionista. A recusa mais
explícita do motor virava insumo de média ponderada.

### 8.2 A correção

Decisão 45. O solucionador passa a ter duas maneiras distintas de não
entregar caminho:

| | o que significa | o que o motor faz |
|---|---|---|
| **não convergir** | falha de método | recuo para a interpolação |
| **recusar** | a estrutura não fecha | a via da firma não vale |

Recusada a estrutura, a via do acionista é o que sobra, a migração é declarada,
e **não há mescla** — não há segundo número a mesclar.

### 8.3 O efeito no universo

| | antes | depois |
|---|---:|---:|
| potencial mediano | −36,1% | −36,1% |
| potencial p25 | −69,3% | **−66,5%** |
| potenciais positivos | 31 | 30 |
| preços justos alterados | — | **6** |
| ativos que deixam de ser avaliados | — | **2** |

Os seis que se movem: PRIO3 +463,0%, AGRO3 +68,0%, KLBN11 +23,4%, KLBN4
+22,9%, MYPK3 +19,9%, KLBN3 +19,8%.

**Os dois que saem são AMER3 e BHIA3**, com a mesma recusa nomeada — capital
próprio não positivo no ano zero, e a via do acionista não avalia. A BHIA3
aparecia com **+230,4% de potencial**: o motor anunciava que a ação valia 3,3
vezes o preço de tela enquanto a própria conta dizia que, reprecificado o custo
do capital próprio pela alavancagem que ele tem, não sobra capital próprio.

Perder um potencial positivo aqui é ganho, não perda.

### 8.4 A discordância, remedida sobre os 90

| | via da firma antiga (§1) | firma nova, recuo silencioso | **firma nova, recuo recusado** |
|---|---:|---:|---:|
| ativos com as duas vias | 92 | 96 | **90** |
| p10 | 0,35× | 0,39× | **0,59×** |
| mediana | 1,04× | 1,12× | **1,21×** |
| p90 | 2,44× | 3,08× | **3,34×** |
| discordam além de 1,5× | 55 | 56 | **50** |
| discordam além de 2× | 33 | 37 | **32** |
| **ainda mesclados** | — | 6 | **0** |
| **ainda migrados** | — | 6 | **0** |

**A discordância não encolheu, e não era para encolher.** Ela deixou de
decidir: nos 90 ativos em que as duas vias são calculáveis, o preço vem de um
estimador só, e nenhum resultado mescla ou migra.

### 8.5 O mercado mudou de lado

| | firma antiga | **firma nova** | acionista |
|---|---:|---:|---:|
| fica mais perto do preço | 39 de 92 | **47 de 90** | 43 |
| erro mediano \|justo/preço − 1\| | 59,1% | **52,6%** | 53,8% |

A via da firma era a pior das duas contra o mercado e passou a ser, por margem
estreita, a melhor. Não é prova de acerto — o mercado não arbitra método —, mas
é o sinal na direção certa: a via que mudou foi a que melhorou.

### 8.6 O que fica em aberto

1. **A via do acionista sobre LPA continua como modelo independente**, e é o
   que avalia instituição financeira, o roteamento da Porta 3 e todo ativo cuja
   estrutura de capital a firma recusa. A discordância da decisão 39 continua
   inteira **dentro dela** — 50 de 90 além de 1,5× —, só não escolhe mais nada.
   Decidir o destino dela é o D2b.
2. **A recusa é mais forte do que a evidência exige em um ponto.** Capital
   próprio não positivo no ano zero é conclusão sobre a estrutura *dada a
   projeção de dívida crescendo a `g`* — que é premissa da rota (b), não fato
   observado. Amarrar a dívida ao valor, a saída (a) da §4, produziria outra
   resposta para os mesmos seis ativos.
3. **Quatorze ativos continuam na faixa exposta** (participação entre 5% e
   35%), agora sem mescla: para eles o preço é o da via da firma sozinha, com a
   condição numérica que a rota derivada melhorou mas não elimina.
