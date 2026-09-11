# As duas rotas do capital investido, que nunca se conferiram

Medido em 11/09/2026.

```bash
dart run tool/capital_investido.dart   # grava capital_investido.json
```

---

## 1. A afirmação

`FundamentalsSnapshot.investedCapital` apura pelo **financiamento**:

```
CI = PL + dívida bruta − caixa
```

e o comentário dela dizia, desde que foi escrita:

> Equivale, por identidade de balanço, a `imobilizado + intangível + capital de
> giro` — ver `investedCapitalOperating`, **cuja concordância com este serve de
> teste de qualidade**.

**Esse teste nunca foi executado.** `investedCapitalOperating` não é lido por
nenhuma linha do motor: aparece uma única vez no repositório inteiro, num
despejo de `tool/deep_audit.dart`. A identidade era prosa.

## 2. A conferência

Sobre os **3.915 exercícios de 316 ativos** em que as duas rotas se apuram:

| distância multiplicativa | valor |
|---|---:|
| p10 | 1,028× |
| p25 | 1,074× |
| **p50** | **1,199×** |
| p75 | 1,584× |
| p90 | 3,165× |
| p95 | 7,863× |
| máximo | 316,4× |

| acima de | exercícios |
|---|---:|
| 1,05× | 3.210 (82,0%) |
| 1,10× | 2.675 (68,3%) |
| 1,25× | 1.753 (44,8%) |
| 1,50× | 1.098 (28,0%) |
| 2,00× | 668 (17,1%) |
| 5,00× | 275 (7,0%) |

**As duas rotas não concordam.** O viés é sistemático e num só sentido: a rota
do financiamento é **1,35×** a operacional, em média geométrica.

## 3. Por que, e por que não tem conserto aqui

A cauda é setorial:

| ticker | exerc. | financiamento | operacional | distância |
|---|---:|---:|---:|---:|
| HBRE3 | 2019 | R$ 1,981 bi | R$ 0,006 bi | 316,4× |
| BRAP3/4 | 2019 | R$ 9,583 bi | R$ 0,040 bi | 239,4× |
| LOGG3 | 2015 | R$ 2,444 bi | R$ 0,016 bi | 157,0× |
| IGTI3/4/11 | 2024 | R$ 5,938 bi | R$ 0,048 bi | 124,6× |
| SCAR3 | 2012 | R$ 1,594 bi | R$ 0,016 bi | 100,1× |
| SYNE3 | 2015 | R$ 4,007 bi | R$ 0,045 bi | 89,2× |
| CURY3 | 2025 | R$ 1,346 bi | R$ 0,018 bi | 73,6× |

Todas imobiliário ou *holding*. O ativo dessas empresas é **propriedade para
investimento** ou **participação em coligada**, e a rota operacional soma
apenas `imobilizado + intangível + capital de giro`. Falta-lhe todo ativo não
circulante que não caiba nessas duas linhas — propriedade para investimento,
participação societária, recebível de longo prazo, crédito tributário
diferido.

**A fonte não publica nenhuma dessas linhas, nem o ativo total de onde
inferi-las** — ver a lista de campos de `FundamentalsSnapshot`. Não há como
completar a soma, e portanto não há como transformar a rota operacional no
contraponto que o comentário prometia.

## 4. O que foi feito

Nada de numérico muda: **o ROIC, o freio de reinvestimento `b = g/ROIC` e o
veredito de fosso saem da rota do financiamento**, que fecha por construção a
partir de PL, dívida e caixa. A rota operacional é a metade quebrada, e é a que
não é usada.

O que muda é o registro. A afirmação de que a concordância entre as duas serve
de teste de qualidade foi **removida**, e a rota operacional passa a declarar o
que lhe falta, com esta medição citada. Ela fica no lugar porque informa onde o
ativo de fato é imobilizado, e porque o despejo de auditoria a consome.

**O que sobra é uma ausência, não um erro:** o motor não tem conferência
analítica do balanço, e não pode ter com esta fonte. Isso vai para
[limitacoes.md §2.17](limitacoes.md), e a alternativa — inventar o ativo não
circulante que falta — seria pior que a ausência.
