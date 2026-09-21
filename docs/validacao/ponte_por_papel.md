# A ponte por papel nas coortes — item C3

Medido em 15/09/2026 por `dart run tool/ponte_por_papel.dart`, sobre
`docs/validacao/backtest_trimestral.json` — as 31 coortes trimestrais com as
deslistadas ([habilidade_trimestral.md](habilidade_trimestral.md)). Dados em
[ponte_por_papel.json](ponte_por_papel.json). Decisão:
[97](../decisoes/097-a-coorte-forma-preco-contagem-e-valor-de-mercado-na-base-da-data.md).

## 1. O que faltava, e o que se achou no caminho

A §3.5 das limitações registrava que nenhuma coorte exercitava a ponte por papel:
com `valor de mercado = contagem do exercício × preço` e a mesma contagem como
corrente, a razão de unidade saía 1 e as duas candidatas a divisor, iguais — 351
de 351 ativos, conferido em 11/09/2026.

**Levantar a peça achou o defeito que a causava, e ele era maior que ela.** A
fonte de preços publica o fechamento ajustado por todo evento de ações até hoje, e
a coorte o multiplicava pela contagem do exercício, que está na base daquele ano.
O fator entre o fechamento bruto do COTAHIST e o da fonte, no mesmo pregão:

| fator de base, nas 9.010 observações das listadas | observações |
|---|---:|
| a até 2% de 1 | 6.046 |
| de 2% a 10% | 261 |
| de 10% a 50% | 1.068 |
| **mais de 1,5 vez** | **1.635** |

Um terço das observações estava fora da base da data, e quase uma em cinco por
mais de 1,5 vez. O mesmo fator errava o valor de mercado — no potencial e no
book-to-market igualmente — e o financeiro da Porta 0, porque o volume da fonte
não é ajustado. O efeito sobre a habilidade medida está em
[habilidade_trimestral.md](habilidade_trimestral.md) §5.

## 2. A montagem na base da data

`tool/coortes/base_da_data.dart`:

- **o preço**: a série da fonte vezes o fator medido no último pregão até a data;
  o volume refeito do financeiro do COTAHIST. Em 489 observações o pregão da data
  é de um código anterior da companhia — a VVAR3 da BHIA3, a BRDT3 da VBBR3 —,
  encadeado pela FCA;
- **a contagem**: a do Formulário de Referência na data (A3.4), como corrente e
  como a contagem oficial que arbitra o divisor;
- **o valor de mercado**: o da companhia, espécie a espécie.

| origem do valor de mercado | listadas | deslistadas |
|---|---:|---:|
| as duas espécies, cada uma pelo preço dela | 3.408 | 594 |
| uma espécie só, ou a sem pregão pelo preço da outra | 5.403 | 1.267 |
| sem contagem da data: contagem do exercício × preço bruto | 170 | 3 |
| com contagem e sem pregão de espécie | 18 | — |

## 3. A razão de unidade, contra a composição declarada

A FCA declara a composição de cada unit em texto — "1 ON e 4 PN", "1 KLBN3 + 4
KLBN4" —, e é a verdade contra a qual a razão medida se confere. A decisão 61 não
tinha essa conferência fora da amostra.

| unit | declarada | coortes | razão igual à declarada | razão bruta mediana |
|---|---:|---:|---:|---:|
| SANB11 | 2 | 31 | **31** | 2,00 |
| SAPR11 | 5 | 31 | **30** | 4,98 |
| TAEE11 | 3 | 31 | **30** | 2,99 |
| KLBN11 | 5 | 31 | 24 | 4,93 |
| ALUP11 | 3 | 31 | 22 | 2,95 |
| ENGI11 | 5 | 31 | **4** | 4,37 |
| IGTI11 | 3 | 16 | **0** | 4,27 |
| BRBI11 | 3 | 18 | **0** | 1,00 |
| **total** | | **220** | **141** | |

**A razão acerta onde as espécies negociam a preço parecido, e erra onde não.** A
razão bruta é `contagem × preço da unit ÷ valor de mercado`, e só vale o número de
ações da unit quando ordinária e preferencial valem o mesmo. Na ALUP11 de 2019 a
ON negociava 35% acima da PN, e a razão foi de 2,69. Três jeitos de errar:

- **cair em 1**, fora da folga de 5% do inteiro: 49 observações — a unit é
  avaliada como ação, e o potencial sai de três a cinco vezes errado;
- **cair no inteiro errado**, dentro da folga: 12 observações — a ENGI11 com 4 em
  vez de 5 em cinco coortes, a IGTI11 com 4 em cinco e com 8 em duas —, e o erro
  fica escondido;
- **não ter espécie negociando**: 18 observações da BRBI11, cujas ON e PN não
  negociam na data, e o valor de mercado recua
  para a contagem vezes o preço da unit: a razão volta a 1 por construção.

**Nos papéis que não são unit**, a razão sai maior que 1 em 16 de 8.740
observações.

**O aplicativo tem a mesma fragilidade**, e não a mostra hoje: pela fonte de
mercado, as nove units de 04/09/2026 ficaram a até 2,4% do inteiro (decisão 61). A
convenção do valor de mercado da fonte não é conhecida, e ela decide se o erro
aparece. Ler a composição declarada em vez de inferi-la é o item B16.

## 4. O divisor

| origem do divisor | observações |
|---|---:|
| a contagem da data, como oficial | 10.676 |
| implícita no valor de mercado | 155 |
| a única disponível | 15 |

As candidatas — a implícita no valor de mercado e a conciliada pelas
demonstrações — divergem além da banda de conciliação em 869 de 10.846. **A regra
do maior quase não decide mais**: com a contagem da data arbitrando, como o
registro da B3 no aplicativo, ela só vale nas 170 observações sem contagem.

## 5. A unit contra a espécie da mesma companhia

A §3 de [unidade.md](unidade.md) conferiu, num dia, que a unit e a espécie que a
compõe descrevem o mesmo negócio. Nas coortes, entre a unit avaliada e a espécie
avaliada mais próxima dela na mesma coorte:

| | pares | distância mediana entre os `1 + potencial` |
|---|---:|---:|
| base de hoje, só 30/09 | 20 | **80,1%** |
| **base da data, as 31 coortes** | **75** | **1,5%** |

Na montagem antiga, a unit e a espécie da mesma companhia discordavam pelo fator
da unit. Na da data, a distância mediana cai para 1,5%; a das observações em que
a razão errou fica na cauda, e não foi separada.

## 7. A composição declarada passou a decidir — item B16, 20/09/2026

A §3 mediu a inferência contra a declaração e achou 79 erros em 220 observações.
A [decisão 106](../decisoes/106-a-razao-de-unidade-sai-da-composicao-declarada-e-a-medida-confere.md)
inverteu os papéis: **a composição declarada decide, e a razão medida vira
conferência**, no aplicativo e nas coortes.

**O pacote.** `tool/unit_empacotar.dart` lê o quadro de valores mobiliários da
FCA, ano a ano, e grava `assets/cvm/units.json`. A chave é o **CNPJ**, e não o
código de negociação: a coluna de código vem em branco em 44% das linhas e zerada
no BTG, que declara a composição da BPAC11 sob `000000`. Nove das dez units do
universo saem com composição:

| unit | ações | declarado |
|---|---:|---|
| ALUP11 | 3 | "1 ON E 2 PN" |
| BPAC11 | 3 | "1 ON E 2 PNA" |
| BRBI11 | 3 | "2 ações preferenciais e 1 ação ordinária" |
| ENGI11 | 5 | "1 ação ordinária e 4 ações preferenciais" |
| IGTI11 | 3 | "1 ON e 2 PN" |
| KLBN11 | 5 | "1 KLBN3 + 4 KLBN4" |
| SANB11 | 2 | "1 ON + 1 PN" |
| SAPR11 | 5 | "1 ON e 4 PN" |
| TAEE11 | 3 | "1 ON / 2 PN" |

A décima, a ONCO11, não é declarada como unit pela companhia — e ali o motor
continua inferindo, **dizendo que inferiu**.

**No aplicativo de 14/09/2026, nenhum número muda.** Nas sete units avaliadas, a
razão medida coincide com a declarada, e nenhuma conferência dispara. É o que a
decisão 61 já tinha visto ao medir as nove a até 2,4% do inteiro. O que muda é de
onde o número vem: ele deixa de depender de uma convenção de valor de mercado que
não é conhecida, e o rastro de auditoria passa a trazer as duas razões e a dizer
qual valeu.

**O leitor do texto livre ganhou um caso que errava.** O código de negociação de
três letras: a ENGI11 de 2018 declara "1 ENG3 e 4 ENGI4", e exigir quatro letras
somava só o 4 — a unit saía com quatro ações em vez de cinco, que é justamente um
dos doze erros de inteiro da §3. A leitura passou ao núcleo
(`UnitCompositionCodec.parse`), porque deixou de ser conferência e passou a
decidir número, e tem teste sobre as dezoito formas que as companhias escreveram.

**As coortes só recolhem o ganho quando o backtest for reexecutado.** O código
delas já passa a composição por CNPJ e por data; os números da §3 continuam sendo
os da inferência até lá (item C5).

## 6. O que isto não diz

- **A contagem do FRE não é a oficial.** Nas dez companhias em que diverge da B3
  por mais de 1% em 14/09/2026 — TOKY por 20 vezes, AGXY por 12,8 —, o divisor da
  coorte herda o erro.
- **A divisão entre espécies é a da última aprovação de capital**, e a
  preferencial com mais de uma classe vai toda pelo preço da mais negociada.
- **Não há evidência preditiva própria da razão de unidade**: são oito units, e o
  que a medição dá é conferência contra a composição declarada, e não retorno.
