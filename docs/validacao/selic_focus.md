# A Selic prevista no lugar da taxa livre de risco — o pedido do orientador

Medido em 27/09/2026 por `dart run tool/selic_focus.dart`, sobre a entrada
congelada do gabarito (14/09/2026), com a montagem de referência conferida
ativo a ativo contra ele. Dados em [selic_focus.json](selic_focus.json).
Pedido em [2026-09-27-voce.md](../apontamentos/2026-09-27-voce.md); item B33 do
plano.

## 0. A pergunta

O orientador pediu que a projeção deixasse de usar «a mediana da Selic do
passado» e passasse a usar «a mediana da Selic prevista para os próximos cinco
anos», com a expectativa de que isso **subisse** os valuations e os encaixasse
melhor no mercado brasileiro. As perguntas são duas: se isso melhora o motor, e
se é recomendado.

## 1. O que o motor usa hoje

**A média do passado não é mais a taxa do motor.** Até 14/09/2026 a taxa livre
de risco de cada ano ia, em linha reta, do CDI corrente até a **média decenal do
CDI** no ano 10, e a perpetuidade era descontada nela — é a «Selic do passado»
do pedido. A [decisão 74](../decisoes/074-a-taxa-livre-de-risco-segue-a-curva-observada.md)
pôs no núcleo a curva dos títulos prefixados do Tesouro. A
[decisão 84](../decisoes/084-a-curva-e-o-padrao-do-aplicativo.md) a fez padrão:
**a taxa de cada ano é o forward de um ano da curva**, e a da perpetuidade, o
forward depois do ano 10. A média decenal ficou só como **recuo**, quando falta
curva de até sete dias.

**E o recuo está acontecendo na web.** Lá, a curva vem só do pacote do build
([decisão 86](../decisoes/086-na-web-a-curva-vem-so-do-pacote.md)). O pacote
versionado é de 10/09/2026, e desde 17/09 ele passou dos sete dias. **O
aplicativo web de hoje desconta pela média decenal do CDI** — exatamente a taxa
que o orientador quer trocar —, e o aviso da avaliação diz «sem curva de juros
observada». No nativo, o aplicativo lê a curva do dia no Tesouro.

## 2. As taxas

| em 14/09/2026 | ano 1 | ano 10 | perpetuidade |
|---|---:|---:|---:|
| curva do Tesouro (o motor de hoje) | 13,62% | 14,29% | 14,29% |
| Focus: CDI corrente → mediana das expectativas anuais | 14,09% | 10,50% | 10,50% |
| Focus: trajetória | 13,36% | 10,00% | 10,00% |
| média decenal do CDI (o motor de antes, e o recuo) | 14,09% | 9,39% | 9,39% |

O Focus de 14/09/2026 espera a Selic em 13,75% no fim de 2026, 12,00% em 2027,
10,50% em 2028 e 10,00% em 2029 e 2030; a mediana dos cinco anos é **10,50%**.
Na **trajetória**, a taxa de cada ano é a Selic média que o Focus espera para ele,
ligando por segmentos de reta o CDI corrente às expectativas de fim de ano, e a
última expectativa segue até a perpetuidade.

**A curva está 4 pontos acima do Focus no longo prazo.** Em 25/09/2026, a curva do
dia dava 13,7% no ano 1 e 14,0% na perpetuidade. É o que o mercado cobra hoje
para emprestar ao Tesouro por dez anos em reais: a Selic esperada **mais um
prêmio de prazo**, que no Brasil carrega o risco fiscal e o de inflação.

## 3. O que cada fonte faz

| fonte | avaliados | potencial mediano | acima de zero | preço justo mediano contra a curva | postos contra a curva |
|---|---:|---:|---:|---:|---:|
| **curva do Tesouro** | 97 | −45,4% | 15 | — | — |
| Focus, mediana | 107 | −41,9% | 20 | **+18,3%** | 0,989 |
| Focus, trajetória | 114 | −39,5% | 27 | **+32,9%** | 0,974 |
| média decenal | 107 | −36,9% | 23 | +25,1% | 0,982 |

As duas leituras do Focus ganham ECOR3, ENEV3, ENGI11, GOAU4, LOGG3, MOTV3,
MYPK3, PNVL3, RAIL3 e VBBR3, que a curva recusa; a trajetória ganha também
KLBN3, KLBN4, MOVI3, RENT3, RENT4, UGPA3 e VAMO3. Nenhuma perde ativo.

## 4. O que isso responde

**A premissa do pedido vale contra o motor de hoje, e não contra o que ele
nomeia.** Trocar a média do passado (9,4%) pela mediana prevista (10,5%)
**baixaria** os valuations. Trocar a curva (14,3%) pelo Focus os **sobe**, de 18%
a 33% na mediana. É esta a troca que o pedido descreve no efeito.

**O nível melhora pouco.** O potencial mediano vai de −45% a −40% ou −42%, e o
motor continua dizendo que a ação mediana vale menos da metade do preço. É o
que a [decisão 116](../decisoes/116-o-premio-de-mercado-fica-em-5-5-por-cento-por-medicao-das-duas-alternativas.md)
já tinha medido pelo prêmio de risco: zerar o prêmio levava a mediana só a
−30%. O desacordo de nível vem da rentabilidade das companhias abertas, abaixo
do custo de capital delas
([decisão 112](../decisoes/112-a-rentabilidade-reverte-a-mediana-do-mercado-e-nao-ao-custo-de-capital.md)),
e nenhuma taxa livre de risco plausível o fecha.

**A ordenação quase não muda**: postos de 0,974 a 0,989. Taxa é botão de nível,
e não de ordenação, como a decisão 74 mediu para a própria curva (0,93) e a 116
para o prêmio (0,996). **Por isso a troca não deve mover o R2 nem o R3.** A
previsão pode ser testada: o Focus tem histórico desde 2001, e o backtest com a
trajetória de cada coorte mediria as duas coisas. Esse teste não foi feito.

**E ela desmarca uma condição do valuation exemplar.** «Curva de desconto
observada» é condição do exemplar desde a decisão 84. O Focus é pesquisa de
opinião sobre a Selic de curto prazo, e não preço de mercado.

## 5. É recomendado?

**Como taxa de desconto, não.** A taxa livre de risco de um fluxo descontado é o
custo de oportunidade de quem avalia: o que ele ganharia, sem risco de crédito,
pelo mesmo prazo. Esse custo é a curva. Um investidor compra hoje um prefixado
que paga cerca de 14% ao ano por dez anos, e não um que paga os 10% do Focus. Descontar
pelo Focus é supor que o prêmio de prazo é zero. O resultado é avaliar a ação
como se o dinheiro sem risco rendesse quatro pontos a menos do que rende, o que
superavalia justamente os ativos de fluxo longo. O prêmio de mercado de 5,5% foi
fixado sobre a curva, e a soma dos dois é que é o custo de capital.

**O Focus tem lugar legítimo em dois pontos**, se o orientador quiser vê-lo:

- **como cenário de sensibilidade declarado** — «se os juros seguirem o que o
  Focus espera, o preço justo seria X» —, ao lado do preço justo e sem
  substituí-lo, que é o papel dos cenários desde a
  [decisão 92](../decisoes/092-a-incerteza-e-a-faixa-calibrada-e-os-cenarios-sao-sensibilidade.md);
- **na projeção do resultado financeiro**, que é fluxo, e não desconto: o juro
  do caixa e da dívida indexados ao CDI. O motor de hoje não projeta o resultado
  financeiro linha a linha, e esta seria uma mudança de modelo maior.

**Trocar a base exige decisão que substitua a 84**, e o exemplar passa a ter uma
condição a menos. A escolha é de vocês e do orientador (item B33).

## 6. O que resolver de qualquer jeito

**O pacote da curva precisa acompanhar o build web.** O cabeçalho de
`tool/curva_empacotar.dart` já manda rodar `python tool/tesouro_baixar.py` e ele
antes de cada `flutter build web`; sem isso, a web cai na média decenal uma
semana depois da data do pacote. Regerar o
pacote muda a entrada do gabarito, que é congelada numa data: o gabarito e a
entrada congelada têm de ser regravados juntos.
