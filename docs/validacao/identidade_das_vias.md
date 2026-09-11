# A2 — a identidade entre as duas rotas do capital próprio

Construída e medida em 10/09/2026.

> **Resolvido.** As §§ 0 a 6 registram o diagnóstico e a divergência de 4,2%;
> a §7 registra o conserto — a identidade fecha dentro de 1e-6 —, a §8 a
> entrada em produção e a §9 a saída da ponte do caminho do preço.

---

## 0. O que A2 tenta

A [decisão 39](../decisoes/039-as-duas-vias-sao-modelos-independentes.md)
estabeleceu que as duas vias são modelos independentes: os fluxos não derivam
um do outro, e falta a ponte `FCFE = FCFF − juros(1−τ) + ΔDívida`.

A2 constrói essa ponte. A rota derivada **não é uma segunda opinião** — é a
mesma avaliação por um caminho que não passa pela subtração `EV − D`, e por
isso não sofre a amplificação de `1/participação` que motivou a pós-condição da
ponte.

## 1. A identidade, e o que ela exige

```
FCFE_t     = FCFF_t − D_{t−1}·[Kd(1−τ) − g_t]
FCFE_{N+1} = (WACC − g)·V − D·Kd(1−τ) + D·g
           = Ke·E + Kd(1−τ)·D − g·E − g·D − D·Kd(1−τ) + D·g
           = E·(Ke − g)
```

de modo que `TV_acionista = FCFE_{N+1}/(Ke − g) = E = TV_firma − D`.

A passagem do meio usa `WACC·V = Ke·E + Kd(1−τ)·D`. **Ela só vale se os pesos
do WACC forem o `E` e o `D` do próprio modelo, em cada ano.** É a condição
inteira.

## 2. Com alavancagem constante, fecha

Travado em [`equity_from_firm_test.dart`](../../packages/equisim_core/test/equity_from_firm_test.dart):
com `g = 0` — dívida constante, valor constante, `D/V` constante — as duas
rotas coincidem dentro de **uma parte em dez mil**, e o resíduo é a convergência
do ponto fixo do WACC, não discordância de método.

Sem dívida, as duas são literalmente a mesma conta, e coincidem em `1e-9`.

## 3. Com crescimento, não fecha — e a causa foi isolada

Sondado com `g = 5%`, `Kd = 11%`, `Ke = 15,5%`, `τ = 30%`, dívida de 3.000 e
WACC levado a ponto fixo:

| | valor |
|---|---:|
| WACC convergido | 13,2632% |
| EV | 10.461,19 |
| E = EV − D | 7.461,19 |
| **peso do equity no ano 0** | **0,7132** |
| TV da firma (ano N) | 12.895,41 |
| D no ano N | 4.886,68 |
| E no ano N | 8.008,73 |
| **peso do equity no ano N** | **0,6211** |

E o efeito:

| | valor |
|---|---:|
| `TV_firma − D_N` | 8.008,73 |
| `FCFE_{N+1}/(Ke − g)` | **8.891,70** |
| preço justo pela firma | R$ 74,61 |
| preço justo pela rota derivada | R$ 77,75 |
| **divergência** | **4,2%** |

Conferindo a passagem que deveria fechar, no ano N:

```
Ke·E + Kd(1−τ)·D = 0,155·8.008,73 + 0,077·4.886,68 = 1.617,62
WACC·V           = 0,132632·12.895,41              = 1.710,32
```

**Diferença de 92,70 — exatamente o vão.**

### A causa

**A dívida cresce a `g`; o valor da firma não.** A dívida é projetada sobre a
base de capital, que cresce a `g` por construção. O valor, não: a estrutura
terminal faz `V` crescer a outra taxa. Resultado, `D/V` sai de 0,2868 no ano
zero para 0,3789 no ano dez — e o WACC, montado com os pesos do ano zero,
deixa de descrever os anos seguintes.

**O motor já supunha alavancagem constante e não a produzia.** Usar um WACC
único ao longo da projeção *é* supor `D/V` constante. A projeção da dívida
contradiz essa suposição, e a contradição estava invisível porque nada
verificava as duas rotas uma contra a outra.

## 4. As duas saídas, e as duas são decisão nova

**(a) Amarrar a dívida ao valor.** `D_t = D_0 · (V_t/V_0)` em vez de crescer a
`g`. `D/V` fica constante por construção, o WACC único passa a ser coerente e a
identidade fecha. O custo é uma passagem regressiva para conhecer `V_t`, e a
hipótese econômica passa a ser "a empresa mantém a estrutura-alvo" — que é
exatamente o que o WACC constante já afirmava.

**(b) Realavancar o `Ke` ano a ano.** Aceitar que `D/V` varia e reprecificar o
custo do capital próprio em cada ano pela alavancagem daquele ano. É a saída
mais fiel, e é **onde o beta desalavancado da
[decisão 40](../decisoes/040-beta-encolhido-por-precisao.md) se torna
indispensável** — sem `β_U` não há como relavancar. Custa circularidade por
ano, resolvida por ponto fixo.

**A decisão 39 dizia que o beta desalavancado era pré-requisito de A2, e eu
não sabia dizer exatamente por quê.** Esta medição é a razão: sem ele, a saída
(b) não existe.

## 5. O que já está garantido por teste

| Propriedade | Estado |
|---|---|
| identidade sob alavancagem constante | **trava** dentro de 1e-4 |
| sem dívida, as rotas coincidem | **trava** em 1e-9 |
| divergência sob alavancagem instável | **trava** a ordem de grandeza (1% a 10%) |
| recusa quando `Ke_∞` não supera `g_∞` | **trava** |

O terceiro é o mais importante: ele impede que a divergência seja consertada
por acidente sem que alguém perceba, e impede que ela cresça sem alarme.

## 6. O que fica em aberto

1. **Escolher entre (a) e (b).** A medição não decide: (a) é mais simples e
   coerente com o que o motor já supõe; (b) é mais fiel e usa o `β_U` que já
   existe.
2. **A rota não está ligada à produção**, e a via do acionista continua sendo o
   modelo independente sobre LPA — com a discordância que a decisão 39 mediu.
3. **A circularidade do WACC não é resolvida em produção.** O peso do equity
   vem do valor de mercado, e o modelo diz que o equity vale ~38% menos. Isso é
   inconsistência à parte, e nenhuma das duas saídas a resolve sozinha.
4. **Instituição financeira fica fora dos dois caminhos**, por direito: não há
   valor da firma nem dívida líquida com sentido econômico ali.

---

## 7. Resolvido pela rota (b), em 10/09/2026

A escolha foi a fidelidade: **aceitar que a alavancagem muda e reprecificar o
custo do capital próprio a cada ano**, em vez de forçar a dívida a seguir o
valor. Decisão 41.

### 7.1 O que entrou

`LeveredCostOfCapital.solve` resolve por **ponto fixo** o que é circular por
natureza — as taxas dependem dos valores, que dependem das taxas:

```
β_L,t  = β_U · (1 + (1 − τ)·D_{t−1}/E_{t−1})
Ke_t   = Rf_t + β_L,t · prêmio
WACC_t = Ke_t·(E/V)_{t−1} + Kd·(1 − τ)·(D/V)_{t−1}
```

Cada iteração reavalia a firma com o caminho da anterior, reconstrói o valor
ano a ano por acumulação regressiva e recalcula a alavancagem de cada ano. A
parada é o valor no ano zero deixar de se mover, a 1e-10.

**O amortecimento de meio a meio não é enfeite.** Sem ele o ponto fixo oscila
em ativo muito alavancado: uma queda de `E` eleva `Ke`, que derruba `E` de
novo.

`DcfAssumptions` ganhou `discountRatePath` e `equityFromFirm` ganhou
`equityDiscountRatePath`: com alavancagem variável, a taxa deixa de ser
interpolação de dois pontos e passa a ser **caminho**.

### 7.2 O critério de aceite

| | divergência entre as rotas |
|---|---:|
| interpolação de dois pontos, com crescimento | **4,2%** |
| caminho resolvido por ponto fixo | **< 1e-6** |

**A identidade fecha.**

### 7.3 O que mais ficou travado

| Propriedade | Estado |
|---|---|
| identidade **com crescimento** | trava em 1e-6 |
| o ponto fixo converge | trava, com contagem de iterações |
| `Ke` sobe quando a alavancagem sobe | trava (Hamada) |
| sem dívida, o caminho é plano e igual ao CAPM | trava em 1e-9 |
| capital próprio que desaparece vira **recusa nomeada** | trava |
| sem `β_U`, recusa — a rota (b) depende dele | trava |
| caixa líquido extremo mantém as taxas finitas | trava |

O penúltimo é o que amarra a decisão 40 a esta: **sem beta desalavancado a rota
(b) não existe**, e agora isso é uma recusa explícita em vez de um argumento.

---

## 8. D1b — o solucionador entra em produção

Decisão 42. `ValuationInputs.unleveredBeta` recebe o `ShrunkBeta.unlevered` que
`PrepareValuationInputs` já produzia e descartava. Na via da firma, a cascata
resolve o caminho de taxas e o usa no lugar da interpolação. **Sem `β_U`, ou
sem convergência, vale a interpolação** — e o resultado declara qual valeu.

| | valor |
|---|---:|
| receberam o caminho resolvido | **117 de 122** |
| caíram na interpolação | 5 |

### O efeito foi redistribuição, não deslocamento

| | antes | depois |
|---|---:|---:|
| potencial mediano | −38,6% | −37,3% |
| potenciais positivos | 30 | 27 |
| preços justos alterados além de 0,5% | — | **81 de 122** |
| **variação mediana** | — | **+0,0%** |

Oitenta e um se movem e a mediana não muda: o motor deixou de tratar todos como
se a alavancagem fosse constante. MOTV3 +268,0%, SBSP3 +147,7%, PGMN3 −78,1%,
MGLU3 −76,1%.

### A taxa de equilíbrio deixou de ser a mesma para todo mundo

| delta do desconto terminal, nos resolvidos | valor |
|---|---:|
| mediana | −0,00 p.p. |
| p10 / p90 | −1,37 / **+2,94 p.p.** |
| subiu em | 56 de 117 |

**Sobe em metade e cai na outra** — a alavancagem cresce ao longo da projeção em
uns e encolhe em outros, e antes nenhum dos dois casos era visto.
---

## 9. D1c e D1d — a ponte deixa de decidir preço (10/09/2026)

### 9.1 O que mudou

Com o caminho de taxas resolvido, o preço por papel vem de
`DcfCalculator.equityFromFirm`. A pós-condição dos 20% e a mescla da decisão 38
**deixam de se aplicar ali** — elas escolhiam entre dois estimadores que
discordavam, e agora há um só. Continuam valendo no recuo, onde a ponte ainda é
o caminho.

E o veredito de vantagem competitiva passou a ser fechado **duas vezes**: o
primeiro passe contra a interpolação, o segundo contra a taxa que o ponto fixo
devolve.

### 9.2 O efeito

| | antes | depois |
|---|---:|---:|
| potencial mediano | −37,3% | **−35,8%** |
| potencial p75 | −5,3% | **+1,5%** |
| potenciais positivos | 27 | **31** |
| multiplicador necessário | 1,37× | **1,31×** |
| preços justos alterados além de 0,5% | — | 36 de 122 |
| variação mediana | — | **+0,0%** |

**O quartil superior cruzou o zero.**

### 9.3 Nove deixam de migrar, e três caem muito

VBBR3 −70%, ENGI11 −67%, RENT3 −67%. Eles migravam para a via do acionista e
recebiam o número dela, mais alto. **Isso não era estimativa melhor — era outro
modelo.** Sob a rota derivada recebem o que a própria avaliação da firma
produz, e o motor deixa de escolher o maior entre dois números que discordam.

Do outro lado: ECOR3 +264%, DXCO3 +234%, GRND3 +227%, CAML3 +152%.

### 9.4 O que ainda falta

1. **A via do acionista sobre LPA continua** para o recuo e para instituição
   financeira, e com ela a discordância da decisão 39. Medi-la de novo agora
   que a via da firma mudou é o próximo passo.
2. **Não há terceiro passe do veredito.** Parar no segundo é escolha
   declarada, e o `λ` mediano de 0,0015 é o que a sustenta.
3. **O `terminalShare` mudou de referência** na rota derivada — passa a ser
   fração do capital próprio, não do valor da firma.

---

## 10. O que o D2 fez com o que a §9.4 deixou aberto

O item 1 da §9.4 — remedir a discordância agora que a via da firma mudou — foi
feito, e está em [vias.md §8](vias.md). O resultado curto: **a discordância
continua e deixou de decidir**. Nos 90 ativos em que as duas vias são
calculáveis, nenhum resultado mescla e nenhum migra.

O caminho até lá passou por um defeito que esta ponte criou sem que se
percebesse: onde o solucionador **recusava** a estrutura de capital, o motor
recuava para a interpolação e produzia preço mesmo assim — descontando pela
taxa que a realavancagem acabara de rejeitar. Os seis ativos em que isso
acontecia eram exatamente os seis que ainda eram mesclados. A
[decisão 45](../decisoes/045-estrutura-de-capital-recusada.md) separa recusa de
não convergência e fecha o caminho.
