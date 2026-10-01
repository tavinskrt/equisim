# O crescimento pela retenção e pelo PIB do setor

Medido em 01/10/2026, a pedido do usuário, com o orientador: por que o motor tira
o crescimento `g` da mediana das variações da base de capital, e não de
`ROE × (1 − payout)`? E por que não usar o crescimento do PIB nominal do setor
para as companhias de pouco capital e as que distribuem quase todo o lucro? E
o que fazer com as commodities? **É medição: nada foi ligado no motor.**

Reproduz-se com:

```bash
python tool/cvm/dividendos_pagos.py
```

```bash
python tool/pib_setorial_baixar.py
```

```bash
dart run tool/crescimento_fundamental.dart
```

O resultado completo, ativo a ativo e no histórico, está em
[crescimento_fundamental.json](crescimento_fundamental.json).

---

## 1. Por que o motor usa a variação da base

**Porque é a mesma conta, olhada para trás.** O lucro que a companhia não
distribui fica no patrimônio. Se nenhum capital entra nem sai por outro
caminho, o patrimônio do fim do ano é o do começo mais o lucro retido:

```
Δpatrimônio = lucro × retenção
Δpatrimônio ÷ patrimônio = (lucro ÷ patrimônio) × retenção = ROE × retenção
```

A variação anual do patrimônio **é** o `ROE × retenção` daquele ano, já
multiplicado. A decisão 25 escreveu exatamente isso: `g = ROE × b` na via do
acionista (e `g = ROIC × reinvestimento` na via da firma, sobre o capital
investido), **medido como a mediana das variações anuais da base**. A mediana
de oito ou mais anos é o `ROE × retenção` realizado, com a resistência a um ano
atípico que uma mediana tem.

**O que a proposta muda é o tempo.** A versão do motor diz quanto a companhia
cresceu; `ROE normalizado × (1 − payout observado)` diz quanto ela cresceria
mantendo a política de hoje. As duas diferem em três pontos:

- a variação da base inclui o capital que entrou por emissão ou aquisição e o
  que saiu por recompra — o motor declara o capital externo (guarda 2), mas não
  o tira do `g`; o payout de dividendos não vê nada disso;
- a variação da base pede quatro anos consecutivos e uma série que «diga um
  crescimento só» (o teste de dispersão); quando não diz, o motor cai na
  inflação ou em zero — hoje, **32 dos 100 ativos usam a inflação e 13 usam
  zero**;
- a proposta é coerente com a projeção do próprio motor: na via do acionista o
  dividendo projetado é `lucro × (1 − g ÷ ROE)`, e impor `g = ROE × (1 −
  payout)` faz o dividendo projetado ser o payout que a companhia pratica.

## 2. As regras medidas, fixadas antes de medir

```
ROE normalizado = mediana dos últimos 8 retornos sobre o patrimônio de abertura,
                  com o do último exercício (mínimo de 4)
payout          = dividendos e JCP pagos ÷ lucro líquido, somados nos últimos
                  5 exercícios (mínimo de 3)
g fundamental   = ROE normalizado × (1 − payout), com a retenção em [0; 1]
```

**Regra combinada** (a sua proposta, com a sugestão para commodities):

| Grupo | Critério | `g` |
|---|---|---|
| Commodity | a lista de precedência do ciclo do próprio motor: materiais básicos, petróleo, refino, mineração, siderurgia, papel e celulose, petroquímicos | inflação (4,92% hoje) |
| Alta pagadora | payout ≥ 75% | PIB nominal do setor, 10 anos |
| Pouco capital | receita ÷ capital investido ≥ 2 (mediana de três anos) | PIB nominal do setor, 10 anos |
| O resto | — | `g` fundamental |

**A sugestão para commodities: crescimento real zero sobre a base do meio do
ciclo.** O lucro de uma produtora de commodity anda com o preço, e o preço real
de commodity não tem tendência positiva no longo prazo — sobe e desce em
ciclos. O motor já põe a base dessas companhias no meio do ciclo (decisão 28,
precedência do ciclo). O que sobra de crescimento defensável é a inflação.
Aqui também foi medida a alternativa, crescer reinvestindo ao retorno do meio
do ciclo, que é o `g` fundamental aplicado a elas. Sem o histórico de preços
futuros das commodities, não há como projetar o preço pela curva do mercado.

Os limiares (75%, 2 vezes) e o mapa de setor da B3 para atividade do IBGE
foram escritos na ferramenta antes da primeira rodada, e não foram mexidos
depois dos resultados.

## 3. Os dados

- **Dividendos pagos:** do fluxo de caixa das DFPs da CVM, grupo de
  financiamento (6.03), as linhas de dividendo, JCP, «pagamento de proventos» e
  «distribuição de lucros», sem o que é recebido, sem o pago a não
  controladores e sem linha filha de outra já contada
  ([dividendos_pagos.py](../../tool/cvm/dividendos_pagos.py)). A primeira versão
  não reconhecia «Pagamento de Proventos» e dava payout zero à B3; corrigida
  antes do resultado. **A recompra de ações não entra** — o pedido foi o
  payout de dividendos —, e na B3 ela é maior que o dividendo (R$ 3,8 bilhões
  contra R$ 2,0 bilhões em 2024).
- **PIB do setor:** valor adicionado a preços correntes por atividade, das
  Contas Nacionais Trimestrais do IBGE (SIDRA, tabela 1846), de 1996 ao
  segundo trimestre de 2026 ([pib_setorial_baixar.py](../../tool/pib_setorial_baixar.py)).
  O crescimento é o dos quatro últimos trimestres publicados contra os mesmos
  quatro, dez anos antes. Hoje: economia inteira 7,98% ao ano; energia e
  saneamento 7,80%; financeiro 9,38%; informação e comunicação 8,92%; comércio
  6,43%; transporte 6,01%; construção 3,76%; transformação 9,10%; extrativa
  18,45% (preço de commodity).
- **O mapa** do subsetor da B3 para a atividade do IBGE está na ferramenta
  (`_atividade`). Dois ativos sem subsetor (GSHP3, HBTS5) vão para a economia
  inteira.

---

## 4. Na data congelada: o nível não se mexe, a ordem quase não muda

O universo reavaliado com cada `g`, imposto pelo ponto de diagnóstico do motor
(o decaimento até `g∞`, o teto da economia e o freio de reinvestimento
continuam):

| Regra | Avaliados | Potencial mediano | Potencial acima de zero | Distância mediana ao preço | Preço justo vs. motor, mediana | Postos contra o motor |
|---|---:|---:|---:|---:|---:|---:|
| Motor de hoje | 97 | −45,4% | 15 de 97 | 0,624 | — | 1,000 |
| ROE × retenção, para todos | 95 | −45,6% | 16 de 95 | 0,649 | 0,0% | 0,985 |
| Regra combinada | 96 | −45,3% | 18 de 96 | 0,642 | 0,0% | 0,982 |

A distância ao preço é a mediana de `|ln(preço justo ÷ preço)|`: 0,62 quer dizer
que o preço justo típico está a um fator de 1,9 do preço de mercado, para cima
ou para baixo.

**Por grupo:**

| Grupo da regra combinada | Ativos | `g` do motor | `g` ROE × retenção | `g` da regra | Potencial: motor | ROE × retenção | regra |
|---|---:|---:|---:|---:|---:|---:|---:|
| Commodity | 14 | 4,9% | 7,0% | 4,9% | −36,8% | −31,6% | −35,4% |
| Alta pagadora | 13 | 4,9% | 2,6% | 8,1% | −43,8% | −47,7% | −44,1% |
| Pouco capital | 16 | 4,9% | 8,4% | 6,4% | −52,4% | −58,8% | −59,0% |
| ROE × retenção | 54 | 4,9% | 8,6% | 8,6% | −45,4% | −44,8% | −44,8% |
| Sem dado | 3 | 4,9% | — | — | −73,7% | −73,7% | −73,7% |

(«Sem dado» são ativos sem payout ou ROE medível; ficam com o `g` do motor.)

**A mediana não se mexe, mas os ativos se mexem**: com a regra combinada, 37
dos 93 comparáveis mudam mais de 10% de preço justo e 12 mais de 25%; 34 sobem
e 36 caem mais de 1%. Os maiores saltos percentuais são de ativos cujo preço
justo já é quase zero, o resíduo da dívida do item B34 (EMBJ3 vai de R$ 0,22 a
R$ 1,88, contra R$ 96,52 de preço); ali a porcentagem não diz nada.

Casos:

| Ativo | Grupo | Payout | ROE norm. | `g` motor | `g` ROE×ret. | `g` regra | Justo, motor | Justo, ROE×ret. | Justo, regra | Preço |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| WEGE3 | pouco capital | 53% | 29,9% | 10,8% | 14,1% | 9,1% | R$ 12,53 | R$ 13,27 | R$ 12,15 | R$ 50,74 |
| ITUB4 | ROE × retenção | 51% | 18,6% | 9,8% | 9,0% | 9,0% | R$ 21,76 | R$ 21,75 | R$ 21,75 | R$ 42,35 |
| VALE3 | commodity | 59% | 16,6% | 3,3% | 6,9% | 4,9% | R$ 70,25 | R$ 74,57 | R$ 72,17 | R$ 75,48 |
| SAPR11 | ROE × retenção | 24% | 17,0% | 10,0% | 13,0% | 13,0% | R$ 36,74 | R$ 35,62 | R$ 35,62 | R$ 34,74 |
| TAEE11 | alta pagadora | 75% | 23,7% | 10,5% | 5,9% | 7,8% | R$ 21,71 | R$ 20,28 | R$ 20,98 | R$ 40,51 |
| EGIE3 | alta pagadora | 76% | 35,2% | 15,8% | 8,3% | 7,8% | R$ 20,64 | R$ 17,74 | R$ 17,55 | R$ 30,46 |
| BBSE3 | ROE × retenção | 74% | 85,8% | 4,9% | 22,4% | 22,4% | R$ 38,04 | R$ 64,63 | R$ 64,63 | R$ 39,77 |
| B3SA3 | ROE × retenção | 67% | 19,0% | −0,8% | 6,3% | 6,3% | R$ 4,52 | R$ 5,09 | R$ 5,09 | R$ 17,37 |
| PETR4 | commodity | 90% | 22,3% | 3,8% | 2,3% | 4,9% | R$ 30,85 | R$ 30,15 | R$ 31,35 | R$ 48,92 |
| ABEV3 | alta pagadora | 81% | 18,2% | 9,1% | 3,5% | 9,1% | R$ 10,25 | R$ 9,34 | R$ 10,25 | R$ 15,87 |

A RENT3 é recusada pelas três regras, como hoje. A tabela dos 100 ativos está
no fim.

### Por que o nível não se mexe

**Crescer só cria valor quando o retorno do capital novo passa o custo dele.**
Na projeção do motor, mais crescimento é mais lucro retido. Com o ROE acima do
custo de capital (perto de 20% hoje), reter e crescer vale mais; abaixo, vale
menos — a companhia investe a um retorno pior do que o acionista exige.

| ROE normalizado | Ativos | `g` sobe com a regra | O preço justo sobe | O preço justo cai | Variação mediana |
|---|---:|---:|---:|---:|---:|
| ≥ 20% | 24 | 14 | 11 | 2 | +1,8% |
| 12% a 20% | 38 | 26 | 7 | 17 | −2,8% |
| < 12% | 28 | 15 | 4 | 11 | −7,6% |

Como a maioria das companhias abertas brasileiras rende abaixo do custo de
capital que o motor calcula (decisão 112), subir o `g` não aproxima o preço
justo do preço de mercado: dos 55 ativos em que o `g` sobe, o preço justo cai em
30 e sobe em 22. **Quem decide o
nível é o custo de capital e o terminal, não o crescimento** — a mesma
conclusão da medição do prêmio de risco (decisão 116, B42).

---

## 5. No histórico: a regra combinada acerta mais o crescimento seguinte

Em cada exercício de 2014 a 2022, o `g` que cada regra daria com os dados até
ele — a inflação e o teto da época, o PIB do setor publicado até ali —, contra
o crescimento que aconteceu nos três exercícios seguintes. Para comparar o que
o motor de fato projetaria, o `g` de cada regra entra como o crescimento
composto dos três primeiros anos do caminho que decai até `g∞` — composto, como
o realizado. As três regras são comparadas
nos mesmos pares; o intervalo de 95% sai de 2.000 reamostragens por
companhia.

**Crescimento do patrimônio** (a base que o `g` do motor projeta):

| Conjunto | Pares (companhias) | Erro mediano: motor | ROE × retenção | Regra combinada | Regra − motor [IC 95%] | Viés mediano: motor / regra |
|---|---:|---:|---:|---:|---|---|
| **Todos** | 663 (94) | 5,8% | 5,0% | **4,7%** | **−1,0% [−1,7%; −0,4%]** | −1,2% / +0,3% |
| Commodity | 76 (13) | 8,9% | 7,2% | 6,5% | −2,3% [−3,8%; +1,4%] | −3,8% / −0,6% |
| Alta pagadora | 100 (31) | 7,0% | 7,9% | 6,5% | −0,5% [−3,3%; +1,9%] | −5,9% / −0,9% |
| Pouco capital | 81 (19) | 5,8% | 5,3% | 4,7% | −1,1% [−3,0%; +1,8%] | −2,0% / +1,4% |
| ROE × retenção | 406 (71) | 5,2% | 4,2% | 4,2% | −1,0% [−1,8%; −0,3%] | −0,1% / +0,3% |

**Crescimento do lucro** (média de três anos contra a média dos três
anteriores):

| Conjunto | Pares (companhias) | Erro mediano: motor | ROE × retenção | Regra combinada | Regra − motor [IC 95%] | Viés mediano: motor / regra |
|---|---:|---:|---:|---:|---|---|
| Todos | 597 (88) | 12,3% | 12,3% | 11,6% | −0,7% [−1,9%; +0,3%] | −3,6% / −1,7% |
| Commodity | 55 (13) | 30,2% | 30,1% | 27,0% | −3,3% [−4,8%; +7,6%] | −24,5% / −24,4% |
| Alta pagadora | 87 (24) | 10,4% | 12,6% | 10,6% | +0,2% [−7,6%; +2,1%] | −8,7% / −5,8% |
| **Pouco capital** | 76 (19) | 9,7% | 8,0% | **6,2%** | **−3,6% [−5,3%; −1,2%]** | +0,3% / +0,6% |
| ROE × retenção | 379 (67) | 12,3% | 12,1% | 12,1% | −0,2% [−1,4%; +0,9%] | −2,7% / −1,0% |

O que a tabela diz:

1. **No crescimento do patrimônio, a regra combinada erra menos que o motor**,
   1 ponto a menos na mediana, com o intervalo inteiro abaixo de zero; e quase
   tira o viés (de −1,2% para +0,3%). O `ROE × retenção` sozinho também melhora
   (−0,8 ponto, intervalo de −1,3% a −0,2%).
2. **Nas companhias de pouco capital, o PIB do setor acerta claramente mais o
   lucro**: 6,2% de erro contra 9,7%, com o intervalo inteiro abaixo de zero. É
   a sua intuição confirmada: quem cresce sem precisar reter cresce com o
   mercado.
3. **Nas altas pagadoras, o `ROE × retenção` piora**, e o PIB do setor só empata
   com o motor. Payout de 75% ou mais dá `g` fundamental de 2,6% na mediana,
   abaixo da inflação, e essas companhias cresceram mais que isso (viés de
   −11,5% no lucro). O PIB do setor corrige o viés, mas não o erro.
4. **No lucro total, a melhora não é distinguível de zero.** E nenhuma regra
   ordena o crescimento do lucro: a correlação de postos entre o `g` previsto e
   o realizado é **negativa** nas três (motor −0,15, ROE × retenção −0,22,
   regra −0,21). Quem cresceu mais, ou tem ROE maior, cresceu menos depois. É o
   achado clássico de que crescimento de lucro não persiste (Chan, Karceski e
   Lakonishok, 2003), e vale para as três.
5. **Commodity é ruído para todas**: erro de 27% a 30% no lucro e viés de −24%,
   porque 2021 e 2022 tiveram lucros recordes de preço. Real zero
   (inflação) erra um pouco menos que as outras duas.

---

## 6. Parecer

**O ajuste acrescenta, mas não onde se esperava.**

- **Aproxima a projeção do crescimento real, sim.** Medido contra o que
  aconteceu, a regra combinada projeta o crescimento do patrimônio com um ponto
  a menos de erro e sem o viés do motor, e acerta bem mais o lucro das
  companhias de pouco capital. É o critério mais direto de «projeção mais
  próxima da real» que há aqui, e ele passa.
- **Não aproxima o preço justo do preço de mercado.** O potencial mediano fica
  em −45%, e a distância típica ao preço piora um pouco (0,624 para 0,642).
  Crescer só vale mais quando o retorno passa o custo de capital, e na maior
  parte do universo não passa. O desacordo de nível com o mercado não é do
  crescimento — está no custo de capital (B42) e no terminal (decisão 112).
- **Mexe nos ativos, não no conjunto.** Um terço dos ativos muda mais de 10% de
  preço justo, nos dois sentidos, e a ordem quase não muda (0,98).

**Parte a parte:**

1. **PIB nominal do setor para as de pouco capital: recomendável.** É a parte
   com evidência mais forte (erro de 9,7% para 6,2% no lucro, significante) e
   a de explicação mais simples.
2. **`ROE × retenção` como regra geral: recomendável como substituta da
   mediana**, com duas ressalvas. Ela erra menos o crescimento do patrimônio e
   dá crescimento medido a 38 dos 45 ativos que hoje caem na inflação ou em zero
   por falta de série (42 com a regra combinada).
   Mas explode quando o ROE é altíssimo e o capital pequeno: a BBSE3, com ROE
   de 86% e payout de 74%, recebe `g` de 22,4% e preço justo 70% maior. O
   critério de «pouco capital» (receita ÷ capital investido) não tem sentido
   para financeiras: falta para a BBSE3 e a CXSE3, que escapam dele, e dá
   números sem significado para outras (PSSA3 11,9; PINE4 4,4), que entram no
   grupo por acaso. Uma regra adotada precisaria de um teto (o PIB do setor
   seria o natural) e de um critério de pouco capital próprio para financeiras.
3. **PIB do setor para as altas pagadoras: neutro.** Corrige o viés do
   `ROE × retenção` nelas, mas não erra menos que o motor de hoje.
4. **Commodities com crescimento real zero: neutro a levemente melhor.** É a
   proposta mais conservadora e erra um pouco menos, mas nada acerta lucro de
   commodity com três anos de antecedência.

**Ligar isso no motor pede decisão nova, por dois motivos.** É mudança de
método da Porta 2 (saída 2), sob preservação. E a regra usa dividendo pago
como insumo da avaliação: a decisão 23 tirou provento do motor, e a decisão 89
o reabriu **só** como retorno total nas coortes; levar o payout à cascata é
estender provento a ela, o que o CLAUDE.md diz exigir decisão. O dividendo aqui
vem do fluxo de caixa da CVM, e não dos proventos da B3 — o que evita o B43 e o
B44, mas não a questão de princípio.

## 7. O que isto não diz

- **O histórico é das companhias avaliadas hoje** (94), com os demonstrativos
  como a CVM os publica hoje: sobrevivência e reapresentação, como no resto da
  validação (B8, C1).
- **A comparação é de crescimento, não de habilidade.** Se o preço justo com a
  regra nova ordena melhor o retorno das ações pede o backtest inteiro com
  ela, que não foi rodado — e que depende do B43 e do B44.
- **O payout soma cinco anos de pagamentos de caixa**, e o dividendo pago num
  ano é em parte do lucro do anterior; com lucro crescente, o payout sai um
  pouco subestimado.
- **Recompra fica de fora** do payout, e na B3 ela é a maior parte da
  distribuição.
- **O `g` imposto vale para as duas vias.** Na via da firma, o motor projeta o
  capital investido; aqui ele recebe o crescimento do patrimônio, como o ponto
  de diagnóstico foi feito para fazer («uma empresa tem um crescimento»).

---

## Apêndice — os 100 ativos

| Ativo | Grupo | Payout | ROE norm. | `g` motor | `g` ROE×ret. | `g` regra | Justo, motor | Justo, ROE×ret. | Justo, regra | Preço |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| ABCB4 | ROE × retenção | 36% | 14,3% | 11,1% | 9,1% | 9,1% | R$ 22,76 | R$ 22,95 | R$ 22,95 | R$ 25,05 |
| ABEV3 | alta pagadora | 81% | 18,2% | 9,1% | 3,5% | 9,1% | R$ 10,25 | R$ 9,34 | R$ 10,25 | R$ 15,87 |
| ALOS3 | ROE × retenção | 33% | 6,0% | 4,9% | 4,0% | 4,0% | R$ 12,81 | R$ 13,04 | R$ 13,04 | R$ 28,44 |
| ALPA4 | sem dado | — | 7,6% | 4,9% | — | — | R$ 3,43 | R$ 3,43 | R$ 3,43 | R$ 13,02 |
| ALUP11 | ROE × retenção | 57% | 17,1% | 4,9% | 7,3% | 7,3% | R$ 18,25 | R$ 18,70 | R$ 18,70 | R$ 33,40 |
| AMER3 | pouco capital | — | −9,6% | 8,2% | — | 6,4% | R$ 1,51 | R$ 1,51 | R$ 1,60 | R$ 4,99 |
| ANIM3 | ROE × retenção | 0% | −0,6% | 4,9% | −0,6% | −0,6% | R$ 1,93 | R$ 1,49 | R$ 1,49 | R$ 2,90 |
| AZEV4 | sem dado | — | −24,8% | 4,9% | — | — | R$ 0,31 | R$ 0,31 | R$ 0,31 | R$ 1,39 |
| AZZA3 | ROE × retenção | 49% | 20,1% | 4,9% | 10,2% | 10,2% | R$ 12,34 | R$ 9,42 | R$ 9,42 | R$ 15,77 |
| B3SA3 | ROE × retenção | 67% | 19,0% | −0,8% | 6,3% | 6,3% | R$ 4,52 | R$ 5,09 | R$ 5,09 | R$ 17,37 |
| BBAS3 | ROE × retenção | 41% | 14,3% | 10,5% | 8,4% | 8,4% | R$ 26,72 | R$ 27,10 | R$ 27,10 | R$ 22,12 |
| BBDC3 | ROE × retenção | 41% | 14,1% | 7,8% | 8,4% | 8,4% | R$ 12,00 | R$ 11,94 | R$ 11,94 | R$ 16,17 |
| BBDC4 | ROE × retenção | 41% | 14,1% | 7,8% | 8,4% | 8,4% | R$ 11,82 | R$ 11,75 | R$ 11,75 | R$ 18,33 |
| BBSE3 | ROE × retenção | 74% | 85,8% | 4,9% | 22,4% | 22,4% | R$ 38,04 | R$ 64,63 | R$ 64,63 | R$ 39,77 |
| BEEF3 | alta pagadora | 149% | 7,7% | 16,9% | 0,0% | 9,1% | R$ 9,53 | R$ 5,38 | R$ 8,21 | R$ 4,08 |
| BHIA3 | pouco capital | — | −19,6% | 0,0% | — | 6,4% | R$ 1,35 | R$ 1,35 | R$ 0,95 | R$ 0,78 |
| BMGB4 | alta pagadora | 76% | 7,3% | 3,7% | 1,7% | 9,4% | R$ 2,42 | R$ 2,60 | R$ 1,98 | R$ 6,08 |
| BPAC11 | ROE × retenção | 26% | 20,2% | 16,8% | 15,0% | 15,0% | R$ 16,95 | R$ 17,08 | R$ 17,08 | R$ 60,48 |
| BRAP4 | commodity | 52% | 15,3% | −1,3% | 7,4% | 4,9% | R$ 18,99 | R$ 21,41 | R$ 21,19 | R$ 21,64 |
| BRAV3 | commodity | 9% | 7,7% | 4,9% | 7,1% | 4,9% | R$ 30,25 | R$ 31,03 | R$ 30,25 | R$ 17,75 |
| BRSR6 | ROE × retenção | 42% | 11,5% | 6,0% | 6,7% | 6,7% | R$ 15,85 | R$ 15,70 | R$ 15,70 | R$ 14,98 |
| CEAB3 | pouco capital | 7% | 12,4% | 0,0% | 11,5% | 6,4% | R$ 4,45 | R$ 3,04 | R$ 3,57 | R$ 9,35 |
| CMIG4 | ROE × retenção | 53% | 20,3% | 5,2% | 9,5% | 9,5% | R$ 6,43 | R$ 6,42 | R$ 6,42 | R$ 11,22 |
| COGN3 | alta pagadora | 976% | −1,0% | 0,0% | −0,0% | 8,1% | R$ 0,70 | R$ 0,70 | recusada | R$ 2,34 |
| CPFE3 | ROE × retenção | 69% | 28,4% | 7,1% | 8,8% | 8,8% | R$ 24,52 | R$ 24,99 | R$ 24,99 | R$ 44,73 |
| CPLE3 | ROE × retenção | 69% | 11,3% | 8,4% | 3,5% | 3,5% | R$ 1,71 | R$ 2,29 | R$ 2,29 | R$ 15,92 |
| CVCB3 | pouco capital | — | −3,9% | 0,0% | — | 8,1% | R$ 1,44 | R$ 1,44 | R$ 1,67 | R$ 1,61 |
| CXSE3 | alta pagadora | 84% | 33,1% | 4,9% | 5,3% | 9,4% | R$ 9,76 | R$ 9,86 | R$ 10,72 | R$ 20,06 |
| CYRE3 | ROE × retenção | 30% | 16,0% | 4,9% | 11,2% | 11,2% | R$ 3,50 | R$ 1,64 | R$ 1,64 | R$ 25,33 |
| CYRE4 | ROE × retenção | 30% | 16,0% | 4,9% | 11,2% | 11,2% | R$ 3,06 | R$ 1,14 | R$ 1,14 | R$ 24,96 |
| DIRR3 | alta pagadora | 84% | 16,6% | 4,8% | 2,6% | 3,8% | R$ 1,75 | R$ 1,73 | R$ 1,74 | R$ 10,13 |
| EGIE3 | alta pagadora | 76% | 35,2% | 15,8% | 8,3% | 7,8% | R$ 20,64 | R$ 17,74 | R$ 17,55 | R$ 30,46 |
| EMBJ3 | ROE × retenção | 6% | −3,2% | 12,7% | −3,0% | −3,0% | R$ 0,22 | R$ 1,88 | R$ 1,88 | R$ 96,52 |
| EQTL3 | ROE × retenção | 64% | 17,8% | 4,9% | 6,3% | 6,3% | R$ 26,33 | R$ 27,24 | R$ 27,24 | R$ 39,48 |
| EZTC3 | ROE × retenção | 44% | 10,0% | 4,9% | 5,6% | 5,6% | R$ 5,46 | R$ 5,27 | R$ 5,27 | R$ 12,86 |
| FESA4 | commodity | 41% | 12,6% | 9,7% | 7,5% | 4,9% | R$ 2,16 | R$ 2,25 | R$ 2,40 | R$ 5,68 |
| FRAS3 | ROE × retenção | 40% | 19,3% | 4,9% | 11,6% | 11,6% | R$ 9,16 | R$ 10,51 | R$ 10,51 | R$ 23,20 |
| GGBR4 | commodity | 42% | 9,5% | 4,9% | 5,6% | 4,9% | R$ 16,33 | R$ 16,17 | R$ 16,33 | R$ 25,06 |
| GRND3 | ROE × retenção | 21% | 14,2% | 8,8% | 11,2% | 11,2% | R$ 2,19 | R$ 2,08 | R$ 2,08 | R$ 3,76 |
| HAPV3 | sem dado | — | −0,3% | 0,0% | — | — | R$ 2,91 | R$ 2,91 | R$ 2,91 | R$ 6,72 |
| HYPE3 | ROE × retenção | 52% | 13,0% | 7,2% | 6,3% | 6,3% | R$ 2,11 | R$ 2,38 | R$ 2,38 | R$ 23,53 |
| IGTI11 | ROE × retenção | 37% | 9,0% | 0,5% | 5,7% | 5,7% | R$ 0,85 | recusada | recusada | R$ 25,76 |
| IRBR3 | pouco capital | 0% | 2,4% | 0,0% | 2,4% | 9,4% | R$ 25,42 | R$ 23,74 | R$ 18,47 | R$ 61,93 |
| ISAE4 | ROE × retenção | 44% | 17,2% | 12,2% | 9,6% | 9,6% | R$ 30,00 | R$ 29,72 | R$ 29,72 | R$ 27,28 |
| ITSA4 | ROE × retenção | 53% | 17,8% | 9,9% | 8,3% | 8,3% | R$ 8,81 | R$ 8,80 | R$ 8,80 | R$ 14,05 |
| ITUB3 | ROE × retenção | 51% | 18,6% | 9,8% | 9,0% | 9,0% | R$ 22,39 | R$ 22,36 | R$ 22,36 | R$ 46,25 |
| ITUB4 | ROE × retenção | 51% | 18,6% | 9,8% | 9,0% | 9,0% | R$ 21,76 | R$ 21,75 | R$ 21,75 | R$ 42,35 |
| JHSF3 | ROE × retenção | 25% | 15,5% | 4,9% | 11,6% | 11,6% | R$ 8,20 | R$ 7,55 | R$ 7,55 | R$ 11,83 |
| KEPL3 | pouco capital | 60% | 24,3% | 4,9% | 9,8% | 9,1% | R$ 5,24 | R$ 5,54 | R$ 5,51 | R$ 6,58 |
| LEVE3 | alta pagadora | 89% | 37,5% | 0,0% | 4,2% | 9,1% | R$ 25,30 | R$ 30,22 | R$ 36,26 | R$ 32,67 |
| LREN3 | ROE × retenção | 51% | 13,4% | 16,8% | 6,5% | 6,5% | R$ 5,71 | R$ 6,72 | R$ 6,72 | R$ 11,21 |
| MDIA3 | ROE × retenção | 51% | 9,3% | 8,1% | 4,6% | 4,6% | R$ 9,66 | R$ 10,88 | R$ 10,88 | R$ 17,05 |
| MDNE3 | ROE × retenção | 15% | 9,1% | 4,9% | 7,8% | 7,8% | R$ 2,67 | R$ 2,04 | R$ 2,04 | R$ 24,71 |
| MGLU3 | pouco capital | — | 4,9% | 4,9% | — | 6,4% | R$ 5,65 | R$ 5,65 | R$ 5,39 | R$ 5,57 |
| MOTV3 | ROE × retenção | 27% | 12,9% | — | 9,4% | 9,4% | recusada | R$ 2,17 | R$ 2,17 | R$ 16,38 |
| MULT3 | ROE × retenção | 39% | 13,8% | 5,9% | 8,4% | 8,4% | R$ 2,43 | R$ 1,95 | R$ 1,95 | R$ 29,83 |
| NATU3 | ROE × retenção | 9% | 11,0% | 0,0% | 10,0% | 10,0% | R$ 1,76 | R$ 1,44 | R$ 1,44 | R$ 8,03 |
| PETR3 | commodity | 90% | 22,3% | 3,8% | 2,3% | 4,9% | R$ 30,17 | R$ 29,52 | R$ 30,64 | R$ 54,26 |
| PETR4 | commodity | 90% | 22,3% | 3,8% | 2,3% | 4,9% | R$ 30,85 | R$ 30,15 | R$ 31,35 | R$ 48,92 |
| PGMN3 | pouco capital | 38% | 8,9% | 17,2% | 5,5% | 6,4% | R$ 6,23 | R$ 5,50 | R$ 5,61 | R$ 3,80 |
| PINE4 | pouco capital | 43% | 3,1% | 1,4% | 1,8% | 9,4% | R$ 10,40 | R$ 10,50 | R$ 12,79 | R$ 11,67 |
| PNVL3 | pouco capital | 27% | 9,5% | — | 6,9% | 6,4% | recusada | R$ 1,49 | R$ 1,56 | R$ 12,95 |
| POMO3 | ROE × retenção | 62% | 14,3% | 4,9% | 5,4% | 5,4% | R$ 0,17 | R$ 0,14 | R$ 0,14 | R$ 4,19 |
| POMO4 | ROE × retenção | 62% | 14,3% | 4,9% | 5,4% | 5,4% | R$ 0,16 | R$ 0,13 | R$ 0,13 | R$ 4,43 |
| POSI3 | ROE × retenção | 33% | 11,6% | 4,9% | 7,8% | 7,8% | R$ 4,56 | R$ 4,02 | R$ 4,02 | R$ 3,48 |
| PRIO3 | commodity | 0% | 47,0% | 4,9% | 46,9% | 4,9% | R$ 10,25 | recusada | R$ 10,25 | R$ 63,91 |
| PSSA3 | pouco capital | 56% | 19,2% | 8,4% | 8,4% | 9,4% | R$ 25,34 | R$ 25,35 | R$ 25,40 | R$ 50,04 |
| RADL3 | pouco capital | 41% | 20,1% | 14,4% | 11,9% | 6,4% | R$ 7,37 | R$ 7,15 | R$ 6,61 | R$ 19,54 |
| RANI3 | commodity | 47% | 25,7% | 6,1% | 13,6% | 4,9% | R$ 6,89 | R$ 7,02 | R$ 6,78 | R$ 7,97 |
| RDOR3 | alta pagadora | 91% | 12,0% | 0,0% | 1,1% | 8,1% | R$ 15,88 | R$ 16,29 | R$ 19,05 | R$ 37,05 |
| RIAA3 | alta pagadora | 76% | 6,8% | 6,8% | 1,6% | 6,4% | R$ 4,65 | R$ 5,33 | R$ 4,70 | R$ 7,05 |
| SANB11 | ROE × retenção | 35% | 13,7% | 4,4% | 8,8% | 8,8% | R$ 18,29 | R$ 16,77 | R$ 16,77 | R$ 30,37 |
| SANB3 | ROE × retenção | 35% | 13,7% | 4,4% | 8,8% | 8,8% | R$ 9,26 | R$ 8,51 | R$ 8,51 | R$ 15,08 |
| SANB4 | ROE × retenção | 35% | 13,7% | 4,4% | 8,8% | 8,8% | R$ 9,45 | R$ 8,71 | R$ 8,71 | R$ 15,04 |
| SAPR11 | ROE × retenção | 24% | 17,0% | 10,0% | 13,0% | 13,0% | R$ 36,74 | R$ 35,62 | R$ 35,62 | R$ 34,74 |
| SAPR4 | ROE × retenção | 24% | 17,0% | 10,0% | 13,0% | 13,0% | R$ 7,92 | R$ 7,73 | R$ 7,73 | R$ 6,82 |
| SAUD3 | pouco capital | 74% | 35,5% | 0,0% | 9,3% | 8,1% | R$ 1,20 | R$ 1,61 | R$ 1,57 | R$ 15,02 |
| SBFG3 | ROE × retenção | 13% | 10,0% | 4,9% | 8,7% | 8,7% | R$ 1,23 | R$ 0,36 | R$ 0,36 | R$ 8,74 |
| SBSP3 | ROE × retenção | 18% | 16,4% | 8,6% | 13,4% | 13,4% | R$ 3,58 | R$ 3,09 | R$ 3,09 | R$ 26,84 |
| SEER3 | alta pagadora | 387% | 6,5% | 4,9% | 0,0% | 8,1% | R$ 16,96 | R$ 15,44 | R$ 17,85 | R$ 13,87 |
| SHUL4 | ROE × retenção | 32% | 21,6% | 4,9% | 14,6% | 14,6% | R$ 3,39 | R$ 3,13 | R$ 3,13 | R$ 4,35 |
| SLCE3 | ROE × retenção | 55% | 16,1% | 8,9% | 7,2% | 7,2% | R$ 4,38 | R$ 4,34 | R$ 4,34 | R$ 17,35 |
| SMTO3 | ROE × retenção | 40% | 19,0% | 10,8% | 11,4% | 11,4% | R$ 25,07 | R$ 25,06 | R$ 25,06 | R$ 19,74 |
| SUZB3 | commodity | 16% | 22,1% | 4,9% | 18,7% | 4,9% | R$ 29,89 | R$ 28,88 | R$ 29,89 | R$ 47,30 |
| TAEE11 | alta pagadora | 75% | 23,7% | 10,5% | 5,9% | 7,8% | R$ 21,71 | R$ 20,28 | R$ 20,98 | R$ 40,51 |
| TAEE4 | alta pagadora | 75% | 23,7% | 10,5% | 5,9% | 7,8% | R$ 7,71 | R$ 7,17 | R$ 7,43 | R$ 13,72 |
| TEND3 | pouco capital | — | 13,2% | 0,0% | — | 3,8% | R$ 5,21 | R$ 5,21 | R$ 5,08 | R$ 31,48 |
| TGMA3 | pouco capital | 74% | 23,9% | 4,9% | 6,3% | 6,0% | R$ 15,24 | R$ 15,52 | R$ 15,46 | R$ 35,25 |
| TOTS3 | ROE × retenção | 40% | 14,5% | 4,9% | 8,7% | 8,7% | R$ 7,72 | R$ 7,81 | R$ 7,81 | R$ 34,37 |
| UNIP6 | commodity | 93% | 29,3% | 4,9% | 1,9% | 4,9% | R$ 46,10 | R$ 41,19 | R$ 46,10 | R$ 57,04 |
| USIM3 | commodity | 39% | 5,9% | 0,0% | 3,6% | 4,9% | R$ 0,44 | recusada | recusada | R$ 6,64 |
| USIM5 | commodity | 39% | 5,9% | 0,0% | 3,6% | 4,9% | R$ 0,41 | recusada | recusada | R$ 7,03 |
| VALE3 | commodity | 59% | 16,6% | 3,3% | 6,9% | 4,9% | R$ 70,25 | R$ 74,57 | R$ 72,17 | R$ 75,48 |
| VBBR3 | commodity | 39% | 29,5% | — | 17,9% | 4,9% | recusada | recusada | R$ 1,60 | R$ 37,70 |
| VIVT3 | ROE × retenção | 71% | 7,7% | 0,0% | 2,2% | 2,2% | R$ 8,30 | R$ 7,67 | R$ 7,67 | R$ 30,51 |
| VLID3 | ROE × retenção | 41% | 7,7% | 8,4% | 4,5% | 4,5% | R$ 6,10 | R$ 7,27 | R$ 7,27 | R$ 17,70 |
| VULC3 | ROE × retenção | 72% | 28,2% | 7,3% | 7,9% | 7,9% | R$ 13,75 | R$ 13,93 | R$ 13,93 | R$ 13,29 |
| WEGE3 | pouco capital | 53% | 29,9% | 10,8% | 14,1% | 9,1% | R$ 12,53 | R$ 13,27 | R$ 12,15 | R$ 50,74 |
| WIZC3 | ROE × retenção | 60% | 50,5% | 4,9% | 20,2% | 20,2% | R$ 13,97 | R$ 17,48 | R$ 17,48 | R$ 7,87 |
| YDUQ3 | ROE × retenção | 63% | 5,5% | 4,9% | 2,0% | 2,0% | R$ 0,53 | R$ 1,09 | R$ 1,09 | R$ 9,92 |
