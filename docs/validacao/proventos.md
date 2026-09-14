# Proventos da B3, conferidos, e o retorno total — item A4

Medido em 14/09/2026. Ferramentas: `tool/b3_complemento_baixar.py`,
`tool/proventos_conferir.dart`, `tool/b3_proventos_empacotar.dart`,
`tool/regressao_condicional.dart` e `tool/padrao_ligar.dart`.
[Decisão 89](../decisoes/089-proventos-voltam-como-dado-conferido.md).

## 1. Por que agora

A [decisão 23](../decisoes/023-remocao-de-proventos.md) tirou provento do projeto
porque a premissa de que o valor da fonte era bruto nunca foi conferida contra
documento. **O orientador reabriu a decisão em 14/09/2026**, e a conferência
passou a ser possível com uma fonte independente.

**A fonte que o plano dava como existente não servia.** O registro do
`GetListedSupplementCompany`, usado no item A3.1, só traz os proventos dos
últimos doze meses: dos 1.082 que ele listava, o mais antigo era de 12/09/2025.
O histórico está em outra consulta do mesmo portal, `GetListedCashDividends`:
**18.651 proventos** dos 297 emissores do universo, de 1995 a 2026, com classe,
data-com, valor, rótulo e o fechamento com direito.

| rótulo | proventos |
|---|---:|
| juros sobre capital próprio | 9.184 |
| dividendo | 8.967 |
| rendimento | 422 |
| restituição de capital em dinheiro | 78 |

2.744 vêm na unidade de lote de mil ações, dos anos em que a B3 cotava assim; o
leitor divide valor e preço pela mesma unidade.

## 2. A conferência

### 2.1 O fechamento com direito bate com o COTAHIST

| | |
|---|---:|
| proventos com preço publicado e pregão na data-com | 9.243 |
| batem a 1% | **9.241 (100,0%)** |
| desvio mediano | 0,00% |

É a prova de que a data-com, a unidade e a classe estão certas: o preço que a B3
publica ao lado do provento é o do pregão do COTAHIST no mesmo dia, papel a papel.

### 2.2 O preço cai na data ex

Nos 6.073 proventos acima de 0,5% do preço, a queda do fechamento na data ex é
**1,17 vez o provento na mediana** — mas com o intervalo interquartil de 0,25 a
2,32, que é o tamanho do movimento diário do mercado. Confirma a data ex; não
mede o valor.

### 2.3 O `adjustedClose` da fonte de preços contra os proventos da B3

A [§1.2 das limitações](limitacoes.md) media, em 20/08/2026 e sobre 11 ativos,
**9,1%** de desvio mediano entre o ajuste da fonte e o fluxo de proventos
**da própria fonte**. Com a B3 como referência independente, de setembro de 2016
a setembro de 2026:

| | |
|---|---:|
| ativos | 278 |
| desvio mediano | **3,3%** |
| p90 | 16,5% |
| acima de 5% | 101 |

O ajuste da fonte erra menos do que se media, e ainda erra: um em cada três
ativos passa de 5% em dez anos. Os maiores desvios — SYNE3, WEST3, CASH3,
CEBR5/6, CMIG4 — não foram investigados um a um; bonificação em ações e
restituição de capital, que a comparação só com provento em dinheiro não
descreve, são as candidatas.
**O `adjustedClose` continua fora de cálculo**; o retorno total sai do provento da
B3 sobre o preço do dia.

## 3. O retorno total

`TotalReturn.factor` e `TotalReturnIndex` reinvestem o provento no fechamento da
data ex: o retorno do dia é `P_ex/P_com + D/P_com`. Como `D` e `P_com` são brutos
do mesmo dia, o rendimento **não depende de a série estar ajustada por
desdobramento**, e multiplica o retorno de preço que as coortes já usam.

**A convenção é a do acionista pessoa física:** dividendo e rendimento inteiros,
juros sobre capital próprio líquidos dos 15% retidos na fonte.

### 3.1 Nas coortes

Sobre as 2.630 linhas de `backtest_valuation.json`, a diferença mediana entre o
retorno total e o de preço em 36 meses:

| coorte | total − preço |
|---|---:|
| 2018 | +11,2% |
| 2019 | +8,0% |
| 2020 | +10,5% |
| 2021 | +7,0% |
| 2022 | +8,3% |

**1.354 proventos saem do preço com direito da B3, e não do COTAHIST.** O papel
que trocou de código — ESTC3 para YDUQ3, KROT3 para COGN3, TIMP3 para TIMS3 — só
tem no COTAHIST o código novo, e 115 tickers das coortes começam depois da
primeira coorte. O provento da B3 é da classe do emissor e não depende do código:
sem o pregão da data ex, vale `P_com − D`, e o erro é o movimento do dia vezes o
rendimento. Ficam **8** proventos sem preço nenhum.

### 3.2 O que muda na habilidade

A pergunta do cabeçalho de `backtest_valuation.dart` era se o retorno de preço
penalizava o motor em ativo de *payout* alto. Sobre as mesmas coortes, na
regressão de Fama-MacBeth:

| | preço | total |
|---|---:|---:|
| 36 meses, IC do potencial sozinho | 0,161 (t = 2,92) | **0,199 (t = 3,84)** |
| 36 meses, potencial com P/B e L/P | 0,042 (t = 0,43) | 0,024 (t = 0,22) |
| 36 meses, P/B com os outros | 0,173 (t = 2,23) | 0,189 (t = 2,47) |
| 12 meses, IC do potencial sozinho | 0,087 (t = 1,24) | 0,114 (t = 1,71) |
| 12 meses, potencial com P/B e L/P | 0,021 (t = 0,28) | 0,021 (t = 0,28) |

**O retorno total melhora a correlação do potencial com o que veio depois, e não
muda nada no que decide.** Condicionado ao valor patrimonial e ao lucro sobre
preço, o potencial continua sem informação própria. A penalidade existia, e não
era ela que escondia habilidade. As coortes são as do motor de 11/09/2026; o C1
remede sobre o motor de agora.

### 3.3 No beta do aplicativo

O Ibovespa, do outro lado da regressão do beta, é índice de retorno total. O
ativo, pelo fechamento, não era: a queda da data ex entrava na regressão como
retorno do ativo sem contrapartida no índice. **O beta passa a sair
do retorno total** dos dois lados, com o pacote `assets/b3/proventos.json` —
9.006 proventos de 239 emissores, com data ex desde 2015 e preço com direito.
O efeito, na mesma execução, está em [fase1_padrao.md](fase1_padrao.md).

## 4. O que não mudou

- **A simulação da carteira continua de preço**, com ação inteira e caixa
  residual. A decisão 89 reabre a 23 para a validação e para o beta; o crédito de
  provento na simulação, o modelo de Gordon e o *yield* no retorno esperado
  continuam fora, e voltar com eles exige decisão nova.
- **A cascata de avaliação não lê provento.** O fluxo descontado é o lucro menos a
  retenção, pela identidade `g = b·ROIC`, e não o provento publicado.
- **As deslistadas também têm provento**: a consulta da B3 é por nome de pregão e
  responde para companhia que saiu da bolsa. Para as 164 da ponte, 135 têm
  proventos, e o preço com direito bate com o COTAHIST do papel em 98,5% — ver
  [b3_contagem_por_data.md](b3_contagem_por_data.md). O retorno total das
  coortes delas é trabalho do C1b.
