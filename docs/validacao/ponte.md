# D7 — o que existe entre o valor da firma e o do acionista

Medido em 10/09/2026, contra os campos crus da fonte.

```bash
dart run tool/probe_ponte.dart PETR4 VALE3 RENT3 ITSA4 CSNA3
```

---

## 0. A pergunta

A ponte do motor é `E = EV − dívida líquida`. O manual tem mais termos:

| Termo | O que o manual manda fazer |
|---|---|
| participação de não controladores | subtrair |
| investimento em coligada | somar |
| arrendamento (IFRS 16) | somar à dívida |
| debênture | somar à dívida |

**Aplicar os quatro sem conferir a fonte seria errar em três deles.** A ordem
correta é: descobrir o que a fonte publica, descobrir o que ela já contou, e só
então corrigir o que sobra.

A sonda foi necessária porque o cache guarda apenas os campos já tipados — 30
dos 211 que a fonte devolve por exercício. O que ela não tipa, ninguém vê.

## 1. Arrendamento e debênture já estão na dívida

A fonte publica a conta-mãe **e** as filhas:

| PETR4, R$ bi | valor |
|---|---:|
| `longTermLoansAndFinancing` | 316,8 |
| `longTermLeaseFinancing` | 183,3 |
| `longTermProvisions` | 252,5 |
| **passivo não circulante** | **607,4** |

Somar mãe e filha dá `316,8 + 183,3 + 252,5 = 752,6` — **145 bilhões acima do
passivo não circulante inteiro**. A conta não fecha, e é isso que prova a
hierarquia: o arrendamento está **dentro** da conta de empréstimos.

O mesmo teste, nos três ativos onde os termos são grandes:

| | passivo não circulante | só a conta-mãe | somando as filhas |
|---|---:|---:|---:|
| PETR4 | 607,4 | 569,3 ✓ | **752,6 ✗** |
| VALE3 | 199,8 | 198,7 ✓ | **201,5 ✗** |
| RENT3 | 43,5 | 39,0 ✓ | **71,5 ✗** |

A RENT3 é o caso mais direto: `longTermDebentures` de R$ 32,5 bi contra um
passivo não circulante de R$ 43,5 bi, com R$ 39,0 bi já em empréstimos. As
debêntures **são** aqueles R$ 39,0 bi, em boa parte.

**Conclusão: o termo de dívida da ponte está completo.** Somar arrendamento
teria inflado a dívida líquida da PETR4 em 61% do valor de mercado dela, e a
correção "de manual" teria sido o maior erro do motor.

## 2. Coligada: a receita já está no fluxo

`longTermInvestments` é a conta-mãe de "Investimentos", e ela se decompõe:

| CSNA3 | valor |
|---|---:|
| `shareholdings` (participações societárias) | 8.072.501 |
| `investmentProperties` | 219.525 |
| **`longTermInvestments`** | **8.292.026** |

A soma fecha exatamente. E o tamanho é grande: 56,5% do valor de mercado na
ITSA4, 69,9% na CSNA3, 16,0% na MGLU3.

Somar isso ao valor da firma parece óbvio — e é errado, porque **na DRE
brasileira o resultado de equivalência patrimonial entra acima do EBIT**, em
"Outras Receitas e Despesas Operacionais". Ele já está no fluxo que o motor
desconta.

A prova está na ITSA4, que é quase só participação societária:

| ITSA4 | valor, R$ bi |
|---|---:|
| resultado de equivalência patrimonial | 17,5 |
| **EBIT publicado** | **18,1** |
| resultado das operações próprias | 1,9 |

**Noventa e sete por cento do EBIT da Itaúsa é equivalência patrimonial.**
Somar o valor das participações ao valor da firma contaria a mesma coisa duas
vezes: o fluxo delas e o estoque delas.

## 3. O defeito que estava escondido nisso

Se a equivalência está dentro do EBIT, então:

```
NOPAT = EBIT × (1 − τ)
```

**cobra imposto sobre lucro que já foi tributado na investida.** A equivalência
patrimonial é reconhecida pelo resultado *líquido* da coligada; a controladora
não paga imposto sobre ela de novo.

Na ITSA4 o efeito é quase todo o número: R$ 17,5 bi dos R$ 18,1 bi de EBIT
recebiam 34% de tributo — e a fonte confirma que é isso mesmo que ela faz, com
`cleanNopat = EBIT × 0,66` em 4.572 de 4.572 exercícios.

**A correção:**

```
NOPAT = (EBIT − equivalência) × (1 − τ) + equivalência
```

com dois confinamentos, e os dois assimétricos de propósito:

- **equivalência negativa não devolve imposto.** Prejuízo de investida reduz o
  EBIT sem ter gerado crédito tributário na controladora, e devolver imposto
  ali inventaria caixa;
- **a equivalência não passa do próprio EBIT.** Acima disso a operação está no
  prejuízo, e o NOPAT ficaria maior que o resultado que o gerou.

## 4. Não controladores: o termo que de fato faltava

O único dos quatro que sobrevive à conferência. A demonstração consolida 100%
das controladas, o fluxo da firma carrega o resultado inteiro, e o acionista da
controladora não é dono de tudo isso.

| Ativo | não controladores ÷ valor de mercado |
|---|---:|
| CSNA3 | **24,1%** |
| ITSA4 | 3,0% |
| VALE3 | 1,4% |
| PETR4 | 0,5% |
| RENT3, LREN3, MGLU3 | ~0% |

A correção sai **depois** da ponte e **antes** da divisão por papel, nas duas
rotas — a ponte `EV − D` e a rota derivada da decisão 43.

**A alavancagem não muda.** Minoritário é capital próprio, e tirá-lo de
`equityShare` o trataria como dívida: a pós-condição da ponte e o ponto fixo do
custo de capital leriam uma estrutura que não existe. O que muda é só quanto do
capital próprio pertence a quem compra a ação.

Participação negativa — controlada com patrimônio negativo — é tratada como
zero: subtraí-la *aumentaria* o valor do controlador, e o motor não modela a
obrigação de aportar.

## 5. O efeito, isolado do dado novo

**A migração do cache invalidou a chave de fundamentos**, e a rodada seguinte
trouxe todos os 30 campos frescos — não só os dois novos. Comparar contra o
relatório anterior mediria a correção somada ao que a fonte mudou desde a
última busca.

A separação é feita avaliando o mesmo ativo duas vezes **na mesma série
recém-buscada**: uma com os dois termos e outra com eles zerados, que reproduz
o motor de antes.

```bash
dart run tool/ponte.dart   # grava ponte.json
```

| | valor |
|---|---:|
| ativos com participação de não controladores | **213 de 373** |
| ativos com equivalência patrimonial positiva | 126 |
| equivalência ÷ EBIT, mediana | 4,4% |
| equivalência acima de 20% do EBIT | **20** |
| **preços justos alterados além de 0,5%** | **50 de 120** |
| variação mediana dos alterados | **−2,2%** |
| caem / sobem | 34 / 16 |

### 5.1 As quedas são holdings, e elas estão certas

| Ativo | variação | não controladores ÷ valor de mercado |
|---|---:|---:|
| GOAU4 | **−69,7%** | 235% |
| EMBJ3 | −51,6% | — |
| UGPA3 | −51,0% | — |
| EVEN3 | −43,7% | — |
| ENEV3 | −20,4% | — |

A GOAU4 é o caso que valida a correção inteira: **Metalúrgica Gerdau consolida
100% da Gerdau e possui cerca de um terço dela.** O patrimônio consolidado é de
R$ 53,9 bi, dos quais **R$ 34,7 bi são de não controladores**. O motor vinha
dando ao acionista da holding o crédito da Gerdau inteira.

Cinquenta e um ativos têm participação de não controladores acima de 10% do
valor de mercado, e oito acima de 100% — HBOR3 com 427%, AMBP3 com 122%. Não
são erros de leitura: são holdings e incorporadoras com sócio em SPE,
negociadas com desconto grande sobre o patrimônio.

### 5.2 A alta grande não é da correção — é de um penhasco

KLBN3 e KLBN11 sobem 266%, e a razão não é o tamanho de nada:

| KLBN3 | com os termos | sem os termos |
|---|---:|---:|
| via | `dcfFcff` | **`dcfEarnings`** |
| preço justo | R$ 4,58 | R$ 1,25 |
| WACC de equilíbrio | 8,9% | recusa |

**Sem os termos, o ponto fixo recusa** — "a taxa de equilíbrio não supera o
crescimento perpétuo" — e a avaliação migra para a via do acionista, pela
[decisão 45](../decisoes/045-estrutura-de-capital-recusada.md). Com eles, a
equivalência patrimonial deixa de ser tributada, o NOPAT sobe entre 0,2% e 3,5%
conforme o exercício, e isso basta para o WACC de equilíbrio cruzar a margem
mínima.

**A KLBN estava na beira exata da recusa, e meio ponto percentual de NOPAT vale
3,7 vezes no preço.** É penhasco, e ele é intrínseco: o valor terminal ou
converge ou diverge, não há meio-termo — mas o que está do outro lado do
penhasco não é uma correção do mesmo modelo, é **outro modelo**, o do LPA. Fica
registrado como pendência, e não como conserto desta rodada.
