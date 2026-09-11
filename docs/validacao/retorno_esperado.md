# A carteira de ações que esperava a renda fixa

Medido em 11/09/2026.

```bash
dart run tool/retorno_esperado.dart   # grava retorno_esperado.json
```

---

## 0. O defeito

`ExpectedReturn.crossSection` estimava o retorno esperado de cada ativo como

```
E[R_i] = CDI + z_i · prêmio,    z_i = (u_i − mediana(u)) / MAD*(u)
```

com `z` sendo o potencial padronizado robustamente contra a seção transversal.

**O ativo mediano da seção recebia exatamente o CDI.** O prêmio de risco de
mercado aparecia só como **dispersão** em torno da renda fixa, nunca como
nível: uma carteira centrada na seção esperava a renda fixa, e nenhuma teoria
de precificação sustenta isso.

A lente `metodo` apontou em **oito rodadas seguidas**.

## 1. O tamanho

| | valor |
|---|---:|
| CDI corrente | 14,09% |
| custo do capital próprio, mediana dos 127 | **19,56%** |

| retorno esperado | p10 | mediana | p90 |
|---|---:|---:|---:|
| **âncora no CDI (antes)** | 9,32% | **14,09%** | 23,32% |
| **âncora no `Ke` (agora)** | 15,02% | **20,45%** | 28,58% |

A mediana de antes é o próprio CDI, ao centavo — é assim que o defeito se
enxerga.

**Numa carteira igualmente ponderada do universo**: 15,09% antes contra 21,06%
agora, **+5,97 p.p.** Antes, segurar as 127 ações do universo elegível prometia
**1 ponto percentual** acima da renda fixa; o prêmio de mercado que o mesmo
motor usa para descontar o fluxo é de 5,5.

## 2. A correção

```
E[R_i] = Ke_i + z_i · prêmio
```

O ativo mediano passa a receber o **próprio custo de capital próprio** —
`Rf + β_i·prêmio`, que é o retorno esperado incondicional dele pelo CAPM. A
ordenação continua fazendo o que fazia: quem está descontado em relação aos
pares recebe mais, quem está esticado recebe menos.

**O `Ke` já existia no motor** — é a taxa com que a via do acionista desconta —
e passou a sair no resultado, em `ValuationDiagnostics.costOfEquity`. Não
confundir com `ValuationResult.discountRate`, que é WACC na via da firma e fica
abaixo do `Ke` sempre que há dívida.

**Dois ativos no mesmo ponto da seção deixam de ter o mesmo retorno esperado**:
o de beta maior recebe mais, que é o que a âncora única apagava.

Sem `Ke` utilizável, a âncora recua para o CDI e o resultado declara em
`CrossSectionalReturn.anchoredOnCostOfEquity`. Nos 127 avaliados, **nenhum**
precisou do recuo.

## 3. O que isto não muda

**O preço justo do ativo continua saindo do DCF**, e é ele que a tela de
avaliação mostra. Este estimador é a projeção de otimização, e só ela.

**O nível do potencial continua fora da conta.** `(1 + u)^(1/H) − 1` seria uma
afirmação sobre quando o preço converge, e o motor não a sustenta — a razão
está na §"Por que não é a anualização do potencial" do próprio
`ExpectedReturn`. O que muda é a **âncora** em torno da qual a ordenação
opera, e ela deixou de ser a renda fixa.
