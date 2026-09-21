# O prior do beta no aplicativo — item B11

> **Medido em 20/09/2026**, sobre a entrada congelada do gabarito da cascata
> (`tool/gabarito_cascata.dart`), que fixa cache, Ibovespa e universo.

## 1. O que o aplicativo fazia

**As decisões 40 a 46 descreviam um motor que não rodava.** `ResolveBetaPrior` só
era chamado pelas ferramentas de diagnóstico. Sem prior não há beta
desalavancado, e sem `β_U` não há realavancagem: o aplicativo avaliava com o beta
cru e o WACC estático — o recuo declarado das decisões 40 e 41. Ficavam de fora,
em produção:

- o encolhimento do beta por precisão (decisão 40);
- o custo de capital resolvido ano a ano contra a alavancagem que a própria
  avaliação produz (decisão 41);
- os passes do veredito da perpetuidade contra a taxa resolvida (decisões 44
  e 51);
- a rota derivada do capital próprio com taxas coerentes (decisões 43 e 102);
- a recusa de estrutura de capital pelo solucionador (decisão 45);
- a isenção de realavancagem da Porta 1 (decisão 46).

A montagem padrão da validação também não passava prior, de modo que ela media o
mesmo motor do aplicativo. **O que divergia era o registro.**

## 2. As quatro coisas a resolver antes de ligar

### 2.1. O custo da dívida do solucionador era o observado

O solucionador recebia `latest.costOfDebt` — `despesa financeira ÷ dívida
bruta` —, que a decisão 31 já tinha descartado do WACC estático por carregar
arrendamento e variação cambial: ele cai fora da banda defensável em 70 dos 120
avaliados. Pior: **ele não decai com a curva**, de modo que a perpetuidade
herdava o juro de hoje.

Agora o solucionador recebe o **prêmio de crédito**, e monta `K_d,t = Rf_t +
spread`, com `K_d,∞ = Rf_∞ + spread`. É o mesmo que
`CostOfCapital.effectiveCostOfDebt` aplica. A rota derivada usa o mesmo `K_d` nas
duas rotas.

**Efeito, na montagem com o prior:** o preço justo muda em 76 de 98 avaliados,
com mediana de **−7,0%** e cauda dos dois lados — de −84,1% na MOTV3 a +377,3% na
PGMN3. A RADL3 vai de R$ 3,43 a R$ 7,42, contra R$ 8,07 da montagem sem prior:
**as duas montagens pararam de discordar por um fator de dois**.

### 2.2. A tensão da via do acionista, e a leitura estava invertida

A lente `metodo` disse que, na via do acionista, o `Ke` resolvido **cai com a
desalavancagem do modelo** e o fluxo não cobra a amortização que produziu a
queda. Medido, o modelo fazia o contrário: com `g = 8%` e `D/E` inicial de 0,63,
a razão ia a **0,81** no ano dez e o `Ke` subia de 19,73% a 20,20%. Ele
**re**alavancava.

O defeito, com o sinal certo: a via desconta `lucro × (1 − b)`, isto é, **o
crescimento já é financiado por lucro retido**. Fazer a dívida crescer a `g`
junto financiava o mesmo crescimento duas vezes — a alavancagem subia, o `Ke`
subia com ela, e o acionista não recebia nada pela dívida nova que a conta supunha
emitida. Na via da firma a premissa oposta é consistente, porque lá o fluxo do
acionista credita o `+ΔD` (decisão 102); aqui não há onde creditá-lo.

A dívida ficou **constante em termos nominais**. Com os mesmos parâmetros, `D/E`
agora vai de 0,61 a 0,43 e o `Ke` de 19,67% a 19,16% — desalavancagem de verdade,
financiada pelo lucro retido. **Na montagem do aplicativo isto alcança um único
ativo hoje**: só uma avaliação resolve o `Ke` pela via do acionista. Ele pesa nas
coortes, onde a Porta 3 é mais frequente.

### 2.3. O que a tela mostrava não era o que a conta usou

Com taxas resolvidas, o preço justo sai das premissas **finais** — caminho de
taxas e retorno terminal do último passe —, mas o rastro, os cenários, os
diagnósticos e a taxa de desconto saíam das **interpoladas**, que são o chute de
que o ponto fixo parte. No aplicativo de antes as duas coincidiam, porque ele não
resolvia o prior.

Três correções:

- **a taxa exibida é a do ano 1** (`discountRateAt(1)`), e não o campo escalar,
  que com o caminho resolvido guarda o chute;
- **a faixa de sensibilidade é centrada nas premissas finais**, de modo que o
  cenário base volta ao preço justo;
- **o deslocamento que um cenário impõe ao desconto é aplicado ao caminho de
  `Ke` resolvido**. Antes o cenário não movia o desconto nesta rota: a faixa
  respondia ao crescimento e não ao custo de capital.

Visível na RADL3: o retorno terminal exibido era 20,57% — o da interpolação —
enquanto a conta usava 17,59%.

### 2.4. Dois ativos subiam com a taxa no caminho resolvido

Na varredura de 16/09/2026, a RADL3 e a SEER3 subiam num ponto da grade, pelo
veredito da perpetuidade que alternava entre passes do ponto fixo. Com o `K_d` do
ano e as premissas finais, os dois ficaram monótonos.

## 3. Como o prior chega ao aplicativo

**Empacotado no build**, como a curva na web (decisão 86) e o registro da B3
(decisão 83). Resolvê-lo em tempo de execução é varrer o universo inteiro — cinco
anos de cotação, o histórico de fundamentos e o perfil de cada um dos 376
papéis — para avaliar **um** ativo.

Gerado por `tool/beta_prior_empacotar.dart` sobre a mesma camada de dados que o
aplicativo lê: CVM mesclada e setor da B3 por emissor. Resolver sobre outra
camada daria outros grupos e outra alavancagem.

| | valor |
|---|---:|
| beta desalavancado mediano do universo | **0,6421** |
| dispersão robusta dos betas alavancados | 0,5444 |
| setores com mediana própria | 10 |
| papéis varridos | 376 |

**O prior anda devagar, e é isso que autoriza o pacote.** Remedido em datas
anteriores, sobre a mesma entrada:

| defasagem | universo | diferença | dispersão |
|---|---:|---:|---:|
| na data (14/09/2026) | 0,6421 | — | 0,5444 |
| −90 dias | 0,6618 | +3,1% | 0,5151 |
| −180 dias | 0,6695 | +4,3% | 0,5208 |
| −365 dias | 0,6620 | +3,1% | 0,4760 |

A validade do pacote é de **um ano** — contra os sete dias da curva, que é taxa
de um dia. Fora dela, o motor volta ao beta cru, **e a avaliação diz que voltou**:
a ressalva nomeia qual dos dois motores produziu o número.

## 4. O efeito de ligar

| | antes | depois |
|---|---:|---:|
| avaliados na montagem do aplicativo | 115 | **102** |
| avaliações com taxas resolvidas | 0 | **83** |
| recusas por estrutura de capital | 0 | **25** |
| não monótonos na varredura do nível | 0 de 115 | **0 de 102** |
| não monótonos no caminho resolvido | 2 de 102 | **0 de 102** |

**Catorze ativos saem, e um entra.** Saem CAML3, DASA3, DXCO3, ECOR3, ENEV3,
LOGG3, MOVI3, PNVL3, RAIL3, RENT3, RENT4, UGPA3, VAMO3 e VBBR3 — todos pela
recusa da decisão 45, e todos no **ano zero da primeira iteração**: o valor da
firma não cobre a dívida líquida nem no chute inicial. Eles eram avaliados porque
o `Ke` do CAPM e o WACC estático não são a mesma conta. Entra a GOAU4.

**O preço justo cai 2,4% na mediana**, com cauda dos dois lados: −79,6% na MYPK3,
−68,1% na ENGI11, −48,6% na MULT3; +22,7% na EMBJ3, +20,1% na ANIM3, +18,4% na
FESA4.

**Somando o B9 desta mesma rodada**, o aplicativo vai de 114 a 102 avaliados, com
mediana de **−0,4%** nos 101 que ficam nos dois lados — os dois itens andam em
direções opostas no nível e se cancelam quase por inteiro.

## 5. O que isto não resolve

- **A medição do backtest não foi refeita.** A base bruta — COTAHIST, CVM
  ingerida, FRE — não está nesta máquina. A habilidade, a faixa calibrada, o
  custo das recusas e a ponte por papel continuam medidos sobre o motor da
  decisão 102. É o item C5.
- **A recusa de estrutura é decidida pelo chute inicial.** O guarda dispara na
  primeira iteração, antes de o ponto fixo ter chance. A direção é conservadora —
  mais alavancagem eleva o `Ke`, que eleva o WACC, que baixa o valor da firma —,
  mas o veredito é do recuo, e não do ponto fixo.
- **O prior é do build.** Ele fica congelado até o próximo empacote.
