# D2b — o destino da via do acionista

Medido em 10/09/2026, sobre os 120 ativos que a cascata avalia.

```bash
dart run tool/via_acionista.dart   # grava via_acionista.json
```

---

## 0. O que sobrou para perguntar

A [decisão 45](../decisoes/045-estrutura-de-capital-recusada.md) tirou da via do
acionista o papel de **segundo estimador**: nos 90 ativos em que as duas vias
são calculáveis, nenhum resultado mescla e nenhum migra
([vias.md §8](vias.md)). A discordância entre elas deixou de decidir.

Ela não deixou de existir, e a via do acionista continua avaliando sozinha uma
parte do universo. A pergunta do D2b é o que fazer com ela — e a resposta
depende de duas medições: **quem ela avalia** e **com que custo de capital**.

## 1. Quem ela avalia, e por qual porta

| | ativos |
|---|---:|
| avaliados pela cascata | 120 |
| **pela via do acionista** | **33** |
| ↳ Porta 1 — instituição financeira | 15 |
| ↳ Porta 3 — lucro operacional não sustentado | 3 |
| ↳ **estrutura de capital recusada** (decisão 45) | **15** |
| ↳ sem porta declarada | 0 |

Duas coisas saltam.

A primeira: **a recusa da decisão 45 empata com a Porta 1 como maior porta de
entrada.** Uma decisão tomada há horas virou, sozinha, metade do motivo pelo
qual a via do acionista existe em produção.

A segunda: **toda entrada tem porta nomeada.** Nenhum ativo chega ali por
omissão.

## 2. O motor tinha dois custos de capital próprio para o mesmo ativo

Desde a [decisão 41](../decisoes/041-custo-de-capital-realavancado-ano-a-ano.md)
a via da firma resolve o `Ke` ano a ano contra a alavancagem que a própria
avaliação produz. A via do acionista não resolvia: descontava ao `Ke` do CAPM
com o beta alavancado de hoje, **supondo essa alavancagem perene** — que é
exatamente a hipótese que a decisão 41 mediu e descartou.

Medido nos 90 ativos em que os dois existem:

| `Ke` resolvido − `Ke` do CAPM, no equilíbrio | valor |
|---|---:|
| p10 | −2,66 p.p. |
| mediana | −0,52 p.p. |
| p90 | +0,62 p.p. |
| \|dif\| > 1 p.p. | **38 de 90** |
| \|dif\| > 3 p.p. | 9 |

O resolvido é **menor** em 68 dos 90: na maioria dos ativos a alavancagem
encolhe ao longo da projeção, e a taxa que supõe a de hoje perene cobra caro
demais pela perpetuidade.

### 2.1 E não dava para emprestar o caminho da outra via

A saída óbvia seria a via do acionista usar o `Ke` que o ponto fixo da via da
firma devolve. A medição fecha essa porta:

> Nos **18** ativos em que a via do acionista decide sozinha fora da Porta 1, a
> via da firma produz caminho de taxas em **zero** deles.

E não é coincidência: **as portas que mandam o ativo para lá são exatamente as
que tornam a via da firma indisponível.** Porta 3 dispara quando o NOPAT não se
sustenta — e sem NOPAT não há fluxo da firma a descontar. A recusa da decisão 45
dispara quando o ponto fixo da firma recusa a estrutura.

Ou o `Ke` da via do acionista sai dos fluxos dela mesma, ou continua supondo
alavancagem constante.

## 3. A correção: o ponto fixo pelo lado do capital próprio

Decisão 46. `LeveredCostOfCapital.solveEquity` resolve a mesma recorrência sem
passar pelo valor da firma:

```
E_t   = (LPA_t + E_{t+1}) / (1 + Ke_t)
β_L,t = β_U · (1 + (1 − τ)·D_{t−1}/E_{t−1})
Ke_t  = Rf_t + β_L,t · prêmio
```

O capital próprio vem por acumulação regressiva do próprio fluxo do acionista;
a dívida segue a base de capital, como na via da firma — trocar a premissa aqui
faria as duas divergirem por construção. Tudo por papel: `D/E` é razão, e
resolver na escala por papel mantém a contagem de ações fora do ponto fixo.

**A instituição financeira fica de fora, e é de direito.** Depósito e captação
são insumo do negócio: realavancar por `D/E` trataria a matéria-prima como
estrutura de capital, que é o que a Porta 1 existe para não fazer. Para banco
vale o `Ke` do CAPM sobre o beta observado, e a alavancagem perene passa a ser
**premissa declarada** em vez de descuido.

## 4. O efeito

### 4.1 Cobertura

| | valor |
|---|---:|
| resolvem o próprio `Ke` | **103 de 120** |
| entre os 33 que a via do acionista avalia | **18** |
| instituição financeira (exceção declarada) | 15 |

Os 18 são todos os não financeiros da via. **A exceção cobre exatamente o que
foi declarado, e nada mais.**

### 4.2 Os dois custos de capital convergiram

| | antes | depois |
|---|---:|---:|
| p10 | −2,66 p.p. | **−1,30 p.p.** |
| mediana | −0,52 p.p. | **0,00 p.p.** |
| \|dif\| > 1 p.p. | 38 de 90 | **18 de 90** |
| o resolvido é maior em | 22 de 90 | 32 de 90 |

**A diferença entre os dois `Ke` caiu pela metade** e a mediana foi a zero. O
que resta não é mais "uma via ignora a alavancagem": é que os dois modelos
projetam valores de capital próprio diferentes, e a alavancagem que cada um
enxerga difere com eles.

### 4.3 No universo

| | antes | depois |
|---|---:|---:|
| potencial mediano | −36,1% | −36,1% |
| potencial p25 | −66,5% | **−69,0%** |
| potenciais positivos | 30 | 30 |
| preços justos alterados | — | **15** |
| ativos que deixam de ser avaliados | — | **0** |

Os quinze movem nos dois sentidos: PRNR3 −28,6%, AXIA3 −14,3%, UGPA3 −10,8%,
SMFT3 −10,7%, as três KLBN em torno de −10%, e do outro lado MILS3 +15,4%,
MBRF3 +13,1%, MYPK3 +7,1%, PRIO3 +4,7%.

**Nenhum ativo saiu.** O ponto fixo do lado do acionista não recusou ninguém — o
que é esperado: com lucro por papel positivo o capital próprio não desaparece,
e a divergência do terminal só existe quando há vantagem residual declarada,
porque o terminal neutro da decisão 25 não depende do crescimento perpétuo.

## 5. Um buraco na taxonomia, medido

**BRSR6, PINE4 e SANB4 são bancos e chegam sem setor.** A fonte não os
classifica, a Porta 1 não os pega, e a Porta 3 os captura — porque o NOPAT de um
banco de fato não se sustenta. Resultado: passam a ser realavancados como se o
depósito fosse financiamento, que é precisamente o que a exceção existe para
impedir.

O tamanho do estrago, medido:

| Ativo | variação do preço justo |
|---|---:|
| PINE4 | −0,27% |
| BRSR6 | −0,15% |
| SANB4 | −0,10% |

**O confinamento de `D/E` em 3,0 absorve o caso.** Um banco tem alavancagem
muito além do teto, o fator de Hamada satura, e o `Ke` resolvido reencontra
quase exatamente o do CAPM — que já fora medido sobre a ação alavancada. A
falha de taxonomia é real e o efeito dela hoje é de terceira casa decimal.

A SANB11 é classificada e a SANB4 não, no mesmo emissor. Corrigir isso é
trabalho de dado, não de método, e está declarado em
[limitacoes.md](limitacoes.md).

## 6. O que fica em aberto

1. **A via do acionista continua sendo um modelo diferente do da firma** —
   cresce sobre patrimônio, normaliza sobre ROE, parte do LPA publicado. O que o
   D2b fecha é o custo de capital; crescimento e base seguem medidos em séries
   diferentes, e é isso que [vias.md §8.4](vias.md) mede em 50 de 90 além de
   1,5×.
2. **Para banco, a alavancagem perene é premissa declarada**, não resolvida. Um
   modelo próprio de instituição financeira — capital regulatório, margem
   financeira, provisão — é outro trabalho.
3. **A dívida projetada cresce a `g` também aqui**, com a mesma consequência que
   [limitacoes.md §2.13](limitacoes.md) registra para a via da firma.
