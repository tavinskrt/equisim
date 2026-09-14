# Contagem de ações e eventos por data das deslistadas — item A3.4

Medido em 14/09/2026. Ferramentas: `tool/cvm_baixar.py --docs FRE`,
`tool/b3_complemento_baixar.py --deslistadas` e
`tool/b3_deslistadas_contagem.dart`. Resumo em
[b3_contagem_por_data.json](b3_contagem_por_data.json); a série por companhia,
para as coortes da Fase 2, em `data/b3/deslistadas_contagem.json`.
[Decisão 90](../decisoes/090-a-contagem-por-data-vem-do-formulario-de-referencia.md).

## 1. O que faltava

A ponte do A3.2 ligou 164 companhias deslistadas ao preço do COTAHIST. Para uma
coorte usá-las, faltavam três coisas:

- **a contagem de ações de cada data** — a contagem oficial da B3 é de hoje e só
  de emissor listado, e a coorte de 2015 precisa da de 2015. É também o que falta
  para a validação exercitar a ponte por papel (limitações §3.5, item C3);
- **os eventos de ações**, para ajustar a série bruta;
- **a escala conferida**, porque um erro de mil vezes na contagem é um erro de
  mil vezes no valor de mercado.

## 2. A fonte: o Formulário de Referência

O FRE da CVM, de 2010 a 2026, tem dois quadros estruturados que servem:

| quadro | o que dá |
|---|---|
| capital social (17.1) | capital integralizado, com data de aprovação e quantidade de ações |
| desdobramento, grupamento e bonificação (17.3) | data de aprovação e contagem antes e depois |

O quadro de eventos parou em 2023, com a mudança de formato do formulário.

## 3. A série: três camadas

A primeira versão lia a declaração mais recente de cada aprovação de capital, e o
P/VPA denunciou o erro: a CPFL Transmissão saía com **P/VPA de 0,01 de 2010 a
2015**. Um grupamento muda a contagem **sem** aprovar capital novo, e o
formulário seguinte repete a data de aprovação antiga com a contagem nova — que
a série levava para antes do grupamento. `ShareCountHistory` passou a ter três
camadas:

1. cada aprovação de capital vale pela contagem da **primeira** declaração dela;
2. cada evento declarado entra na data ex dele — ou na aprovação, sem data ex —,
   com a contagem de depois;
3. o formulário cuja contagem a série não explica entra na **data de
   recebimento** dele: o evento não declarado aconteceu antes.

## 4. Os eventos, localizados no preço

A data de aprovação não é a data ex. `CorporateEvents.locate` procura, até um ano
depois da aprovação, o pregão em que o fechamento se divide pelo fator declarado,
com a folga de 6% da inferência. Fator perto de 1 — bonificação pequena — sai
pela troca do número de distribuição. E fator longe de 1 tem segunda chance: o
grupamento de papel em crise acontece no dia em que o papel também despenca, e um
fator de 25 não se confunde com oscilação — vale a troca de distribuição com a
razão a 25% do fator.

| | |
|---|---:|
| companhias com evento declarado | 100 |
| eventos distintos | 186 |
| com pregão do papel na data de aprovação | 89 |
| **localizados no preço** | **69** |
| com pregão na aprovação e não localizados | 22 |
| inferidos pelo preço onde o FRE não declara | 17 |

Os 97 eventos sem pregão na data de aprovação são anteriores a 2010, quando o
COTAHIST compacto não começa, ou de fora da vida do papel; alguns deles se
localizam mesmo assim, porque a data ex cai depois do primeiro pregão. **Os 22
não localizados ficam marcados por papel**, com a data de aprovação, para a coorte
cuja janela os atravessa sair: Banco Inter (2021), Gol (2015), CCX, OGX (2011 e
2016), Santanense, Tec Toy, Tekno (2012 e 2013), Blue Tech (quatro), Adolpho
Lindenberg, Aliperti, CPFL Transmissão, Springer, Anhanguera, RJ Capital e
Clarion (2010). Onde a data ex não se localiza, a contagem muda na data de
aprovação — é o que corrige o P/VPA da CPFL Transmissão.

## 5. A escala, conferida de três jeitos

### 5.1 Nas listadas, contra a contagem oficial

É onde a verdade existe, e o que valida o método: a contagem do FRE em
14/09/2026 contra a do registro da B3.

| | |
|---|---:|
| emissores | 291 |
| **batem a 1%** | **281 (96,6%)** |

As dez divergências, FRE ÷ B3: TOKY 20,0, AGXY 12,8, JFEN 1,64, PINE 1,02,
VITT 0,98, PMAM 0,94, POMO 0,91, RCSL 0,87, AHEB 0,61 e MBRF 0,50 — esta, a
companhia que incorporou a BRF, com o formulário anterior à incorporação. As
outras não foram investigadas uma a uma.

### 5.2 Nas deslistadas, formulário contra formulário

A contagem do FRE contra a composição do capital do DFP e do ITR da mesma data —
dois quadros diferentes da CVM, preenchidos por pessoas diferentes.

| | |
|---|---:|
| datas conferidas | 1.848 |
| **batem a 2%** | **1.619 (87,6%)** |

**A composição vem na escala do declarante**: 621 datas divergiam por
exatamente mil, em quem publica as demonstrações em milhares — a EDP, com
581.165.268 ações no FRE e 581.165 na composição. É o que a
[decisão 70](../decisoes/070-a-contagem-de-acoes-da-cvm-nao-tem-escala.md) já registrava ao
usar só a fração em tesouraria, e a conferência conta as mil exatas como a mesma
contagem. O que sobra são companhias em recuperação, fusões e defasagem em torno
de aumento de capital.

### 5.3 P/VPA plausível

Contagem × fechamento no fim do exercício, sobre o patrimônio líquido do DFP. Um
erro de mil vezes tira qualquer companhia da faixa de 0,02 a 50.

| | |
|---|---:|
| exercícios conferidos | 867 |
| **na faixa** | **860 (99,2%)** |
| P/VPA mediano | 1,27 |

Os sete fora: cinco acima de 50 — CEPE5 em 2019 com 1.191, PRTX3 em 2010 com
87, AELP3 em 2016 com 76, CRUZ3 em 2010 com 66 e MPLU3 em 2012 com 52 — e dois
abaixo de 0,02, MEGA3 em 2021 e CTIP3 em 2011. Os dois de baixo são os candidatos
a contagem errada.

## 6. Cobertura

| | |
|---|---:|
| companhias da ponte | 164 |
| **com contagem por data** | **160** |
| exercícios com contagem na data e pregão no ano seguinte | **1.151** |

O A3.2 contava 1.272 exercícios com pregão no ano seguinte. A diferença é de
companhia sem capital no FRE e de exercício anterior à primeira aprovação
declarada, e não foi decomposta.

## 7. Proventos das deslistadas

A consulta de proventos da B3 é por nome de pregão, e responde para companhia que
saiu da bolsa. O nome vem do COTAHIST, papel a papel.

| | |
|---|---:|
| companhias com proventos | 135 de 164 |
| proventos na vida dos papéis | 3.008 |
| **preço com direito contra o COTAHIST do papel, a 1%** | **1.753 de 1.779 (98,5%)** |

A conferência do preço é a que garante que o nome de pregão é o da companhia, e
não o de outra com nome parecido: o fechamento com direito que a B3 publica é o
do papel da ponte no mesmo dia. Os proventos ficam por papel em
`data/b3/deslistadas_contagem.json`, para o retorno total das coortes das
deslistadas (C1b).
