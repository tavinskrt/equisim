# O registro de emissores da B3 — itens A3.1 e A3.3

Medido em 14/09/2026. Ferramentas: `tool/b3_companhias_baixar.py`,
`tool/b3_empacotar.dart` e `tool/b3_eventos_conferir.dart`.

## 1. A fonte

A página de empresas listadas da B3 é servida por um endpoint que devolve, por
emissor de quatro letras: **quantidade de ações por classe**, **código CVM**,
**eventos de ações** — desdobramento, grupamento, bonificação, com fator,
data-com e ISIN — e proventos em dinheiro. Aberto, sem cadastro.

| | |
|---|---:|
| emissores do universo consultados | **297 de 297**, nenhuma falha |
| eventos de ações declarados, todas as datas | 759 |
| eventos de contagem de 2010 em diante, distintos | 388 |
| pacote do aplicativo | 93 KB, 606 eventos compostos |

**O endpoint não libera CORS**, como o do Tesouro: o aplicativo o recebe por
pacote versionado.

**Ele traz proventos em dinheiro** com data-com e valor por ação. É a fonte
independente que o item A4 pedia para reabrir a decisão 23 — que continua sendo
decisão do orientador.

## 2. A convenção do fator — conferida contra o preço

O fator não tem unidade declarada, e duas convenções convivem. Confrontado com
a razão de fechamento do COTAHIST no primeiro pregão depois da data-com:

| rótulo | o fator é | bate a 15% |
|---|---|---:|
| `BONIFICACAO` | acréscimo percentual — `25` é +25% | **100%** de 84 |
| `DESDOBRAMENTO` | acréscimo percentual — `900` é 1 para 10 | 80% de 99 |
| `GRUPAMENTO` | multiplicador — `0,05` é 20 para 1 | 77% de 70 |

**Os desvios de desdobramento e grupamento eram quase todos pares.** A B3
escreve um desdobramento de 1 para 2 como grupamento de 10 para 1 **e**
desdobramento de 1 para 20 no mesmo dia — CPFE3 em 2011, LEVE3 em 2012, VIVT3,
EMAE4 e TIMS3 em 2025. Lido evento a evento, o fator erra por 10x ou 100x.

**Compostos por ISIN e data-com**, os eventos batem com o preço em **93,4% de
243 a 15%**, e em 97,1% a 30%. O que sobra:

- **Par incompleto no próprio registro** — ITUB3 e ITUB4 em 2011 trazem só o
  grupamento, BEES3 e BEES4 em 2012 só o desdobramento.
- **O mercado andou no dia** — grupamento de papel em crise costuma cair no
  mesmo pregão: IRBR3 em 2023, DOTZ3 em 2023, PDGR3 em 2025.

80 eventos não têm preço para conferir: papel ilíquido cujo pregão seguinte à
data-com está a semanas, ou ISIN que deixou de negociar.

## 3. A contagem oficial contra a da fonte de preços

Sobre os 363 ativos do universo com as três contagens:

| as contagens da fonte que batem com a B3 a 5% | ativos |
|---|---:|
| corrente, do exercício e implícita no valor de mercado | 236 |
| corrente e implícita | 56 |
| corrente e do exercício | 24 |
| só a do exercício | 15 |
| só a corrente | 13 |
| **nenhuma** | 9 |
| units, com a razão de unidade | 10 |

**Os casos mais graves da §1.7 das limitações não eram grupamento.** A MILS3 tem
234.286.833 ações na B3 — a contagem do exercício —, e a "corrente" de 48.172
da fonte está simplesmente errada, com valor de mercado de R$ 762 mil. A MEAL3
tem 286.676.540 na B3 contra 307.010 correntes. **Nenhuma das duas tem evento
de ações no registro.** A regra do maior acertava nelas; o diagnóstico
registrado — grupamento aparente — estava errado.

**E a regra do maior errava nos dois sentidos em outros:**

| ativo | fonte | B3 | a regra do maior |
|---|---:|---:|---|
| CTKA4 | 62,1 milhões | 6,2 milhões | divisor 10x grande, preço justo 10x baixo |
| FIEI3 | 48,4 milhões | 2,4 milhões | divisor 20x grande |
| AUAU3 | 451 milhões | 861 milhões | **divisor pequeno, preço justo 1,9x alto** |
| AZUL3 | 21,7 milhões implícitas | 368,6 milhões | **divisor 17x pequeno** |

**O total da B3 inclui as ações em tesouraria.** Contra o capital integralizado
declarado à CVM, nas duas escalas que a CVM usa sem dizer qual: bate com o total
em 260 de 293 emissores, e com o total líquido de tesouraria em 3. Ação em
tesouraria não tem direito ao patrimônio, e o divisor oficial a desconta pela
fração — 62 emissores com mais de 1% em tesouraria, mediana de 2,45%, máximo de
53,1%.

## 4. A ponte oficial

O código CVM do registro, cruzado com os metadados das DFPs e ITRs, liga emissor
a CNPJ. Contra a ponte do A1.1: **369 de 371 iguais**. As duas diferentes eram
erros da ponte inferida, nas fusões de 2025 — MBRF3 ligada à BRF em vez da
Marfrig, AUAU3 à Petz em vez da União Pet. Ver a decisão 82.

## 5. O registro contra a inferência pelo preço

A decisão 75 validou a inferência pelo preço comparando **retornos diários**
ajustados com a fonte de mercado: 99,96% batiam. Evento é raro no dia, e aquela
medida não dizia quantos eventos a inferência acha. O registro diz. Papel a
papel, de 2010 em diante, casando data ex a três dias e fator a 6%:

| | |
|---|---:|
| ISINs com evento declarado e pregão | 305 |
| eventos oficiais dentro da série de preço | 289 |
| **cobertura** — oficiais que a inferência encontrou | **41,5%** (120) |
| **precisão** — inferidos que o registro confirma | **63,8%** (120 de 188) |

| tamanho do fator | cobertura |
|---|---:|
| até 20% — bonificação pequena | 1,6% (1 de 61) |
| 21% a 60% | 36,4% (12 de 33) |
| 1,6x a 2,5x | 74,2% (23 de 31) |
| acima de 2,5x | 51,2% (84 de 164) |

**Parte dos falsos positivos é cisão.** ITUB3 em 04/10/2021 — a separação da XP
— sai como bonificação de 25%, e o registro traz, na mesma data, `CIS RED CAP`:
cisão com redução de capital, que não muda a contagem. A inferência não tem como
separar uma da outra. **Outra parte não se resolve com o que há**: CMIG3 e CMIG4
aparecem com ×1,3 em 2012 e 2013, e o registro não traz evento nenhum da Cemig
nesses anos — pode ser bonificação que o registro não tem, ou queda de provento
grande. Não foi conferido.

**A cobertura baixa nos fatores grandes é grupamento de papel de centavos.** Nos
eventos acima de 2,5x o `DISMES` muda sempre, e o fator de cotação só em 5 —
não é isso. O que a amostra mostra é preço de centavos: AZTE3 foi de R$ 0,14 a
R$ 1,23 num grupamento de 10 para 1, e o tick de R$ 0,01 sobre R$ 0,14 já é 7%,
acima da folga de 6%; AMAR3 e AMOB3 andaram 12% a 13% no pregão do grupamento.
E frações como 1/30 e 1/200 não estão na lista do detector.

**O que isto muda.** Para emissor listado, o registro substitui a inferência. Para
companhia deslistada (A3.2), a inferência continua sendo a única fonte, com
esses números como teto declarado: um retorno de coorte ajustado só pelo preço
erra o evento em mais da metade dos casos.
