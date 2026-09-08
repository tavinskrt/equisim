# Auditoria cruzada do motor de avaliação

Executada em 08/09/2026 sobre o cache de produção — 373 papéis do universo
negociável da B3, data de referência 04/09/2026 — e cruzada com um relatório
independente produzido por outro modelo a pedido do orientando.

O que este documento faz é **separar o que se confirmou do que não se
confirmou**, com o número que decide cada caso, e registrar o que nenhum dos
dois lados tinha visto. As correções que saíram daqui estão na
[decisão 31](../decisoes/031-escala-do-preco-tributo-e-invariancia-das-guardas.md).

## 0. Método

Duas ferramentas, as duas rodando sobre a **mesma camada de dados do
aplicativo**, sem reimplementação paralela:

| Ferramenta | O que faz |
|---|---|
| [`tool/deep_audit.dart`](../../tool/deep_audit.dart) | Roda a cascata inteira nos 373 papéis, em `N = 10` e `N = 5`, e despeja por ativo as grandezas intermediárias que o resultado não carrega: as quatro contagens de papéis, a série de retorno com e sem os exercícios de prejuízo, os vereditos de cada guarda, os componentes do custo de capital |
| [`tool/probe_dcf.dart`](../../tool/probe_dcf.dart) | Isola hipóteses de defeito sobre premissas sintéticas, onde a resposta certa é conhecida |

Consultas diretas ao cache SQLite completaram o que a cascata não expõe — a
conferência de `VPA × N = PL` em 4.917 exercícios, a razão `nopat ÷ EBIT` em
4.572, a distribuição de `alíquota efetiva`.

A linha de base é a execução com o código de 07/09/2026, imediatamente antes das
correções.

---

## 1. Veredito, item a item, do relatório externo

### Erro 1 — a armadilha das ações reconciliadas · **PROCEDE, com diagnóstico e remédio corrigidos**

**O que se confirmou.** O divisor da ponte por papel saía errado por mais de 5%
em **30 dos 120 avaliados**. Os dois casos que o relatório cita conferem
exatamente: a MOVI3 dividia por 152.068.530 em vez das 402.158.940 implícitas no
valor de mercado (2,645x), e a B3SA3 por 7,50 bilhões em vez de 5,05 (1,486x).

**O que o relatório errou.** Três coisas.

1. **A AZZA3 não é caso de contagem.** As quatro contagens dela coincidem em
   206.489.810 — corrente, do exercício, implícita no LPA e implícita no valor
   de mercado. O relatório não a acusa disso, mas o leitor pode concluir que
   sim; fica o registro.
2. **As "108 divergências severas" e os casos AMOB3, AVLL3 e AZUL3 não tocam
   preço nenhum.** Eles são medidos sobre os 373 papéis, e nenhum dos três passa
   na Porta 0. O número que afeta resultado publicado é 30 em 120.
3. **O remédio proposto quebraria o motor.** "Eliminar o fallback para
   `sharesOutstandingAsOf`" destruiria as bases contábeis: `VPA × N_exercício`
   reconstrói o patrimônio publicado em **4.461 de 4.462** exercícios do cache,
   e a contagem corrente o reconstrói em **nenhum**. Sem ela não há ROIC, Φ,
   crescimento nem retenção. E "reconciliar via `marketCap ÷ marketPrice`" sem
   ressalva levaria o MILS3 — R$ 760 mil de capitalização contra R$ 9,6 milhões
   de volume mediano por pregão — a um potencial de mais de 240.000%.

**O que ficou estabelecido, e o relatório não tinha.** O árbitro que a
[decisão 25](../decisoes/025-reconstrucao-do-motor-de-avaliacao.md) homologou —
`N = lucro ÷ LPA` — é **tautológico para esta pergunta**: os dois campos vêm das
mesmas demonstrações, então ele só pode confirmar a contagem do exercício. E
confirma, em todos os 30 divergentes. Ele responde bem à pergunta contábil, que
era a do MILS3; não responde à pergunta da ponte.

**Correção adotada.** A ponte divide pela contagem implícita no valor de mercado
quando as duas concordam, e pela **maior** das duas quando divergem — porque
nenhum campo do dado arbitra e divisor pequeno demais infla o preço justo. Ver a
§2.1 abaixo, onde os quatro árbitros candidatos são medidos e descartados um a
um.

### Erro 2 — B3SA3 e o conflito de portas · **PROCEDE, e por um motivo melhor que o alegado**

**O que se confirmou.** A Porta 1 exigia setor financeiro **e** dívida bruta
nula. Dos 28 papéis com `servicos-financeiros` no perfil, **5 caíam para a via
da firma** por terem passivo oneroso: B3SA3, BRBI11, CSUD3, CXSE3 e WIZC3. Na
B3SA3, R$ 14,9 bilhões de captação viravam dívida líquida subtraída do valor da
firma.

**O que o relatório não viu.** A justificativa registrada no código para exigir
dívida nula **não vale na taxonomia que o código compara**. Ela cita a RENT3
chegando classificada como `Finance` — isso é a taxonomia da *listagem*, e a
porta compara contra a do *perfil*, onde a RENT3 e a MOVI3 vêm como
`consumo-ciclico`. Conferido papel a papel: os 28 do setor são bancos,
seguradoras, resseguradora, corretora, bolsa e serviços financeiros diversos. Não
havia locadora a barrar.

**O que o relatório exagerou.** Atribui os −81,2% inteiros à porta. Parte era
divisor: com a contagem certa, a B3SA3 sai de −81,2% para −74,7%.

### Erro 3 — o extermínio das empresas excelentes · **NÃO PROCEDE como defeito; duas das quatro alegações são falsas**

O nível conservador da distribuição é **consequência declarada e homologada** das
decisões [25](../decisoes/025-reconstrucao-do-motor-de-avaliacao.md) e
[27](../decisoes/027-recalibragem-apos-a-primeira-validacao.md): estrutura a
termo do desconto mais terminal neutro. A decisão 27 registra a mediana de
−39,4% e a aceita explicitamente. Chamar isso de defeito é discordar de uma
decisão, o que é legítimo — mas exige decisão nova, não correção de código.

Dentro do item, quatro alegações:

| Alegação | Veredito |
|---|---|
| Crescimento medido pelo capital contábil e não pelo negócio | **É o método homologado** pela decisão 25 (`g = ROIC × RI`, mediana das variações da base). Discutível, não defeituoso |
| `maxGrowthStdError = 0,03` barra 47,5% dos ativos | **Número e causa errados.** O bloqueio alcança **55,8%** (67 de 120), e o piso de precisão responde por **22**; os outros **45** caem no teste de discordância entre estimadores. Afrouxar o parâmetro apontado destravaria um terço do que o relatório promete |
| "Usa o CDI diário de pico como taxa livre de risco", gerando WACC de 18% a 20% na perpetuidade | **Falso.** O motor tem estrutura a termo desde a decisão 25: a taxa livre de risco vai de **14,09%** no primeiro ano a **9,40%** no terminal, e a perpetuidade desconta ao custo de capital de equilíbrio, na casa de 13%. Os 18% citados são a taxa **do primeiro ano**, que desconta um décimo do valor |
| Só 7 de 120 passam no *moat* | **Verdadeiro, e deliberado.** A decisão 30 nomeia os sete e registra a lista como verificação de que a isenção cíclica não vazou |

### Erro 4 — a alíquota efetiva no WACC · **PROCEDE, e o problema é maior que o descrito**

**O que se confirmou.** O escudo fiscal usava a alíquota efetiva do exercício,
confinada a `[0; 0,50]`. Entre os avaliados: **9 no teto de 50%**, **9 nulas**
(escudo desligado), mediana de **19,2%**.

**O que o relatório não viu, e que fecha o argumento.** O `nopat` que a fonte
publica é, em **4.572 de 4.572** exercícios do cache, exatamente `EBIT × 0,66` —
ou seja, **o fluxo da firma já vinha apurado à alíquota estatutária de 34%**. O
numerador e o denominador do mesmo desconto usavam convenções tributárias
diferentes. E o ramo de derivação `EBIT × (1 − alíquota efetiva)` é **código
morto**: `ebit` e `nopat` estão preenchidos exatamente nos mesmos 4.580
exercícios.

**Correção adotada.** Alíquota marginal estatutária de 34%, limitada pela
capacidade de usá-la: com `EBIT < despesa financeira`, a dedução excedente não
abate imposto no exercício, e o escudo vale `34% × min(1, cobertura)` — o
tratamento de Damodaran.

### Erro 5 — o custo da dívida e o IFRS 16 · **PROCEDE, e é mais frequente que o descrito; o efeito alegado não**

**O que se confirmou.** A WEGE3 saía com 47,3% ao ano de custo de dívida
implícito, confinado no teto. E o problema é geral: **70 dos 120 avaliados**
caíam fora da banda defensável, com valores de até 100% ao ano. Os 70 recebiam
**o mesmo** `Rf + 10%` — a empresa de caixa líquido e a alavancada, sem
distinção.

**O que o relatório exagerou.** Ele sugere que isso explica os −76,1% da WEGE3.
Não explica: o peso da dívida dela na estrutura de capital é de **2,07%**, e o
custo da dívida move o WACC em cerca de 0,15 ponto percentual. Onde o defeito
morde é em alavancado — MGLU3 com 52% de dívida, AMER3 com 64%.

**Correção adotada.** Classificação sintética por cobertura de juros, no formato
de Damodaran, aplicada **uniformemente**. A alternativa — observado dentro da
banda, tabela fora dela — reintroduziria o mesmo defeito que este motor passou a
caçar: corte binário sobre grandeza contínua, com duas empresas de mesma
cobertura recebendo custos diferentes conforme a razão observada caísse de um
lado ou de outro de uma borda sem conteúdo econômico.

### Erro 6 — a descontinuidade da ponte de equity · **PROCEDE integralmente**

Os números conferem: a MOVI3 saía de R$ 35,39 em dez anos para R$ 9,47 em cinco,
com a via mudando de firma para acionista. Quatro dos 120 trocavam de via entre
os dois horizontes.

A fundamentação teórica do relatório também procede: com a dívida líquida
consumindo quase todo o valor da firma, o capital próprio é uma opção sobre os
ativos, e o resíduo de subtração do DCF a subestima.

**O que foi feito, e o que não foi.** A migração continua sendo a arquitetura da
decisão 25 — trocá-la por modelo de opções é decisão nova. O que mudou é o caso
em que a migração **falha**: ela deixa de devolver um número sem conteúdo e passa
a produzir **recusa nomeada**, que é o que a decisão 25 exige de toda saída.
Sete ativos passaram a ser recusados com o motivo escrito, entre eles a AMER3 —
que saía a R$ 0,20 em dez anos e R$ 1,47 em cinco, um fator de 7,35 vindo só da
forma da curva de desconto.

**Fica em aberto**, e está registrado como tal na decisão 31.

### O "efeito falésia" (§2.3.4 do relatório) · **PROCEDE, e é o achado mais importante dele**

A deriva da tendência era `|inclinação| × horizonYears`, com o horizonte vindo da
tela. Medido: **13 dos 120 trocavam de veredito** entre `N = 5` e `N = 10`, e o
preço justo ia junto.

| Ativo | Preço justo 10a | Preço justo 5a | Razão |
|---|---:|---:|---:|
| AZZA3 | R$ 16,11 | R$ 57,48 | 3,57x |
| AMER3 | R$ 3,51 | R$ 10,96 | 3,12x |
| CYRE4 | R$ 7,48 | R$ 2,68 | 0,36x |
| CYRE3 | R$ 8,53 | R$ 3,40 | 0,40x |
| RDOR3 | R$ 13,02 | R$ 6,00 | 0,46x |
| LEVE3 | R$ 20,35 | R$ 9,70 | 0,48x |

O relatório mostrou só os casos para cima. O defeito corta nos dois sentidos, o
que é a evidência de que não é viés e sim instabilidade.

**O horizonte sozinho move pouco.** Medido em premissas sintéticas com a guarda
estável: `N = 5` contra `N = 10` muda o valor em **2%**. Toda a diferença de
3,57x da AZZA3 vinha do veredito da guarda virando.

### O desacoplamento entre tela e motor (§2.3.5) · **PROCEDE**

`ValuationSettings` injetava `projectionYears: 5` contra os 10 do núcleo, da
decisão 25 e de todas as rodadas de validação — com um teste do núcleo afirmando
os dez. **O número que o usuário via nunca foi o número validado.**

---

## 2. O que nenhum dos dois lados tinha visto

### 2.1 Nenhum campo do dado arbitra a contagem de papéis

Foram testados quatro candidatos a árbitro, e os quatro falham:

| Candidato | Por que não serve |
|---|---|
| `N = lucro ÷ LPA` | Tautológico: os dois campos vêm das mesmas demonstrações, e ele confirma a contagem do exercício em **todos** os divergentes |
| `marketCap ÷ preço` | É, na fonte, quase sempre `contagem corrente × preço`. Herda o defeito dela quando vem corrompida |
| Giro da capitalização (`VM ÷ volume mediano`) | Separa bem os quatro casos grosseiros — MILS3 com 0,1 pregão, COGN3 com 11,2, ANIM3 com 12,6, CPLE3 com 16,1, contra mediana de 251 no universo —, mas **deixa passar a SAPR**, cuja capitalização de 87,8 pregões é plausível e ainda assim está três vezes abaixo da escala do balanço |
| `enterpriseToEbitda` publicado | Seria independente, e é o único que pega a SAPR. Mas erra por mais de 2x em **12% dos ativos cujas duas contagens concordam** — o piso de ruído dele — e discorda entre classes da mesma empresa: SAPR4 acusa 3,01 e SAPR11, 1,47 |

A série de preços também não ajuda: o `close` da fonte já vem ajustado por ação
societária, e não há salto nenhum em dez anos, em ativo nenhum.

**É limitação de fonte, e passa a estar declarada como tal.** A brapi publica
duas contagens que discordam além de uma ação societária plausível em **85 de
359** ativos com as duas preenchidas, e nada no próprio dado resolve. Resolver de
verdade exige outra fonte para a base societária — CVM ou B3.

### 2.2 A janela do ciclo tinha viés de sobrevivência dentro da própria empresa

`CapitalSeries.returns` exigia `lucro > 0`. A mediana do "ciclo" passava a
descrever **só os anos bons** da empresa — e um ciclo é justamente o que alterna
bons e maus. **51 dos 119 avaliados** tinham ao menos um exercício descartado.

| Ativo | ROIC de ciclo sem os anos de prejuízo | Com eles | Viés |
|---|---:|---:|---:|
| CVCB3 | 33,80% | 0,55% | +33,3 p.p. |
| MGLU3 | 22,37% | 11,23% | +11,1 p.p. |
| MILS3 | 14,65% | 5,32% | +9,3 p.p. |
| SAUD3 | 54,79% | 49,66% | +5,1 p.p. |
| SMFT3 | 9,48% | 4,90% | +4,6 p.p. |

O viés não ficava contido: o fator de normalização da base é `ciclo ÷ atual`, e o
DCF é homogêneo de grau 1 no fluxo-base. Ele ia inteiro para o preço justo, e
sempre no sentido de inflá-lo. É a explicação que faltava para MGLU3 (+146,6%) e
QUAL3 (+68,0%) — que o relatório externo atribuiu a outras causas.

### 2.3 A retenção usava o retorno de um ano e o fluxo de outro

O freio de reinvestimento converte crescimento em retenção por `b_t = g_t /
ROIC_t`, e recebia sempre o **retorno do ciclo** — mesmo quando a base **não**
havia sido normalizada, caso em que o fluxo-base é o do exercício corrente.

Na AZZA3 isso significava exigir a retenção de uma empresa que rende 19,55% de um
fluxo que rende 7,82%. Medido em premissas sintéticas: **17% a mais de valor da
firma**.

A expressão correta fecha os três casos de uma vez: `ROIC_base = retorno_atual ×
fator`. Normalizado sem saturar, dá o retorno do ciclo; saturado, dá o que a
saturação impôs; não normalizado, dá o corrente.

### 2.4 As bandas de cenário não moviam a parte que decide o valor

`DiscreteScenarios.around` deslocava `discountRate` e deixava
`terminalDiscountRate` parado. Como o valor terminal responde por metade a
quatro quintos do total e desconta pela taxa de equilíbrio, os cenários
Pessimista e Otimista quase não o tocavam.

Medido num ativo típico — WACC corrente de 17,4%, terminal de 13,0%:

| | Pessimista | Otimista |
|---|---:|---:|
| Só a taxa corrente desloca (antes) | −11,2% | +12,9% |
| As duas deslocam (agora) | −19,8% | +30,9% |

A banda apresentada afirmava uma precisão que o modelo não tem. O piso que impede
a perpetuidade de divergir também protegia a taxa errada: guardava a corrente,
que não entra no *spread* da perpetuidade.

### 2.5 O rastro de auditoria descrevia uma conta que não era a feita

`_auditDcf` escrevia a projeção como `F_0 (1+g)^t ÷ (1+r)^t`, com `g` e `r`
constantes, e o valor terminal como Gordon com *spread*. A conta usa taxa,
crescimento e retenção **variando ano a ano**, fator de desconto **acumulado**, e
— com retorno terminal neutro — uma perpetuidade da qual o crescimento
**desaparece**.

Medido no mesmo ativo típico:

| Grandeza, ano 10 | O que a conta usa | O que o rastro escrevia | Razão |
|---|---:|---:|---:|
| Fluxo projetado | 1.060,56 | 2.593,74 | 2,45x |
| Fator de desconto | 4,1134 | 4,9737 | 1,21x |

O cabeçalho do bloco de auditoria afirma que "nenhuma linha aqui recalcula nada",
e duas chamadas a `math.pow` recalculavam — errado. Para um artefato cuja
finalidade declarada é reprodutibilidade acadêmica, o rastro exibir uma derivação
que não fecha com o próprio resultado ao lado é defeito material.

---

## 3. O que mudou, medido

Universo de 373 papéis, 119 avaliados depois (120 antes; a AMER3 passou a ser
recusada com motivo nomeado, não silenciosamente).

### 3.1 A cauda de potenciais irreais fechou

| | Antes | Depois |
|---|---:|---:|
| Máximo | +336,4% | +170,2% |
| p95 | +122,5% | +40,0% |
| p75 | −14,5% | −26,3% |
| Mediana | −44,8% | −47,5% |
| p25 | −66,2% | −68,6% |
| Mínimo | −95,5% | −96,5% |
| Ativos com \|potencial\| > 100% | 7 | 2 |

### 3.2 Os casos que o relatório externo nomeou

| Ticker | Potencial 10a antes → depois | Potencial 5a antes → depois |
|---|---:|---:|
| AZZA3 | −8,9% → **−41,2%** | +224,9% → **−27,6%** |
| MOVI3 | +336,4% → **+170,2%** | +16,8% → **−55,7%** |
| AMER3 | −36,8% → **recusa nomeada** | +97,5% → −73,5% |
| MYPK3 | −9,9% → **−13,4%** | +115,3% → **−2,0%** |
| PGMN3 | +222,1% → **−29,4%** | +257,8% → **−21,9%** |
| MGLU3 | +146,6% → **−38,5%** | +160,8% → **−24,7%** |
| B3SA3 | −81,2% → **−74,7%** | −80,4% → **−73,2%** |
| WEGE3 | −76,1% → −75,0% | −75,7% → −74,9% |
| TOTS3 | −79,2% → −77,4% | −77,9% → −76,1% |
| RADL3 | −72,9% → −68,6% | −72,1% → −69,0% |
| VIVT3 | −78,9% → −75,5% | −77,0% → −73,2% |

As quatro últimas mudam pouco, e é o esperado: elas nunca foram caso de defeito,
e sim do conservadorismo declarado das decisões 25 e 27.

### 3.3 A dependência do horizonte caiu, e o que sobra tem causa única

| | Antes | Depois |
|---|---:|---:|
| Ativos com \|fv₅/fv₁₀ − 1\| > 25% | 14 | 9 |
| Ativos com \|fv₅/fv₁₀ − 1\| > 100% | 3 | 1 |

**O que sobra é inteiramente a ponte de equity.** Os cinco maiores desvios
remanescentes — POSI3, MOVI3, SBSP3, CYRE4, CYRE3 — são todos troca de via pela
pós-condição de participação do capital próprio. Nenhum vem mais da Guarda 1.

### 3.4 Custo de capital

| | Antes | Depois |
|---|---:|---:|
| Ativos com custo da dívida substituído | 70 (no teto, todos iguais) | 96 (ordenados por cobertura) |
| Ativos com WACC no piso da taxa livre de risco | 13 | 3 |
| WACC corrente, mediana | 17,40% | 17,84% |

O piso do WACC caindo de 13 para 3 é o sinal de que o custo da dívida deixou de
ser inconsistente com a alavancagem: antes, dívida barata demais em estrutura
pesada empurrava o desconto para baixo do soberano.

### 3.5 Roteamento

| | Antes | Depois |
|---|---:|---:|
| Via da firma | 74 | 64 |
| Via do acionista | 46 | 55 |
| Vantagem competitiva residual | 7 | 8 |
| Ponte por contagem de mercado | — | 109 |
| Ponte por contagem contábil (conservadora) | — | 10 |
| Recusas nomeadas por ponte de equity | 0 | 7 |

---

## 4. O que fica em aberto

1. **A ponte de equity continua sendo uma chave binária.** É a única fonte
   remanescente de instabilidade ao horizonte, e a teoria de opções reais indica
   que o resíduo de subtração subestima o capital próprio de empresa muito
   alavancada. Trocar a migração por um modelo de opções é decisão nova.

2. **A base societária não é reconciliável dentro da fonte.** A regra da maior
   contagem é conservadora por escolha, e erra nessa direção onde a contagem do
   exercício é a estagnada e a maior — B3SA3 e RENT3, entre outras. Resolver
   exige CVM ou B3 como segunda fonte.

3. **A cobertura de juros herda a contaminação que veio consertar.** Ela usa a
   mesma despesa financeira que carrega arrendamento e variação cambial, e por
   isso subestima a cobertura de quem tem IFRS 16 relevante.

4. **17 dos 120 avaliados não têm setor no perfil**, o que a
   [decisão 30](../decisoes/030-isencao-ciclica-da-trava-de-saude.md) já
   registrou. Com a Porta 1 roteando por setor, o efeito cresceu: ITSA4, SANB4,
   BRSR6 e PINE4 nunca podem acionar a porta de instituição financeira. O remédio
   — resolver o perfil pela raiz do ticker — continua sendo mudança de camada de
   dados.

5. **O nível conservador da distribuição não foi tratado, e não é defeito.**
   Mediana de −47,5%. Ela vem da estrutura a termo e do terminal neutro, aceitos
   pelas decisões 25 e 27. Mexer ali é decisão nova, e é a discussão que o
   relatório externo levantou sob o rótulo de "extermínio das empresas
   excelentes".

---

## 7. Segunda auditoria: o rastro exportado pelo aplicativo

Executada em 08/09/2026 sobre o JSON de auditoria que o próprio aplicativo
exporta — 18 avaliações, 267 cálculos, com o motor já sob as decisões 31 e 32.
Nove apontamentos. **Dois se confirmaram e viraram a
[decisão 33](../decisoes/033-rating-arbitrado-e-consistencia-da-base-acionaria.md);
cinco não se confirmaram contra o dado; dois já estavam implementados.**

### 7.1 O que se confirmou

**O prêmio de crédito estava errado contra as empresas mais sólidas.** A
classificação por cobertura de juros, adotada pela decisão 31, herdou a
contaminação que veio consertar: a despesa financeira está no denominador dela.

| Ativo | Cobertura | Dív. líq./EBITDA | Prêmio antes | Prêmio depois |
|---|---:|---:|---:|---:|
| ABEV3 | 3,77x | −0,57x (caixa líquido) | 2,4 p.p. | 1,0 p.p. |
| WEGE3 | 3,68x | −0,30x (caixa líquido) | 2,4 p.p. | 1,0 p.p. |
| RADL3 | 1,50x | 0,70x | 7,5 p.p. | 1,3 p.p. |
| SAPR11 | 0,76x | 0,60x | **10,0 p.p.** | 1,3 p.p. |
| AZZA3 | 1,26x | 1,17x | 7,5 p.p. | 1,8 p.p. |

Na AZZA3, o custo de dívida de 21,6% e o WACC inicial de 18,20% que o
apontamento nomeia caíram para 15,9% e 16,44%.

**A contagem de ações de um exercício pode vir quebrada sem que nada denuncie.**
A EQTL3 traz 246.152 ações em 2024 contra 1,50 bilhão em 2023 — fator de cinco
mil —, com VPA de R$ 121.419,23. O patrimônio sai certo porque o erro se cancela
em `VPA × N`; o divisor da ponte, que usa `N` sozinho, sairia cinco mil vezes
errado numa análise datada entre as duas divulgações.

### 7.2 O que já estava implementado

| Apontamento | Situação |
|---|---|
| Travar instituição financeira no modelo de lucro distribuível | **Feito pela decisão 31.** No rastro, BBAS3, BBSE3 e BPAC11 saem os três em `DCF sobre lucro distribuível`, descontados ao Ke e sem ponte de dívida |
| Aplicar o multiplicador da cesta nas *units* | **Já medido e aplicado.** A razão sai de `ações × preço ÷ valor de mercado`: 5,005 na KLBN11, 5,005 na SAPR11, 2,995 na BPAC11 — arredondadas para 5, 5 e 3. O divisor da ponte já está em unidades negociadas |

### 7.3 O que não se confirmou

**A base acionária da VIVT3 não está duplicada.** A contagem do exercício vai de
1,69 bilhão (2019–2023) a 3,26 bilhões (2024) e 3,23 bilhões (2025), e o VPA
acompanha na direção oposta — R$ 41,67 para R$ 21,40. O produto `VPA × N` fica
**estável em R$ 69 a 70 bilhões em toda a série**. Foi desdobramento, e a fonte o
refletiu corretamente. A contagem corrente de 3.226.546.700 bate com o exercício
de 2025 e com `valor de mercado ÷ preço` (3,20 bilhões).

**As *units* não estão fracionadas.** KLBN11 e BPAC11 reconciliam exatamente
entre demonstrações e mercado (1,248 contra 1,247 bilhão de units; 3,890 contra
3,896 bilhões). Só a SAPR11 diverge — 302,2 milhões de units pelas demonstrações
contra 100,7 milhões pelo mercado —, e essa divergência já é tratada pela regra
da maior contagem da decisão 31, com a ressalva `escalaIncerta` no resultado.

**O motor não usa CapEx em lugar nenhum**, de modo que não há como ele tratar
aquisição de reserva como queima perpétua de caixa. O que prende a PRIO3 é outra
coisa, e está no rastro: Φ de 86,1 barra a vantagem residual por crescimento
inorgânico, e o erro-padrão de 9,9 p.p. no estimador de crescimento derruba a
taxa para a âncora de inflação.

**Indexar o crescimento terminal à inflação não muda nada.** Com retorno terminal
neutro — `ROIC_∞ = WACC_∞`, que é o padrão desde a decisão 25 — a álgebra colapsa
para `VT = fluxo_{N+1} ÷ r` e **o crescimento perpétuo sai da fórmula**. Ele só
volta a pesar onde a vantagem residual é comprovada, e ali já está no teto de
6,86% do crescimento nominal da economia. Dos ativos regulados no rastro, EQTL3 e
SAPR11 usam o terminal neutro; a EGIE3 tem a vantagem e já está no teto.

**As premissas de WEGE3, RADL3 e TOTS3 não estão estáticas**, e cada uma tem
motivo próprio e medido:

| Ativo | Crescimento | Vantagem residual |
|---|---|---|
| WEGE3 | 10,84% identificado no próprio histórico | **Comprovada** — ROIC de ciclo de 25,1% contra custo de equilíbrio de 13,2% |
| RADL3 | 14,37% identificado | Barrada por rentabilidade: ROIC de ciclo de 17,55% contra os 18,2 p.p. que o excedente exige. Erra por 0,7 ponto, e o corte é o da decisão 27 |
| TOTS3 | Cai para a âncora de inflação: os dois estimadores discordam em 7,6 p.p., 5,5 erros-padrão | Barrada por Φ de 1,13 contra o teto de 0,60 da decisão 28 — a base cresceu por aquisição |

### 7.4 O que foi recusado com medição: arrendamento na ponte de equity

O apontamento pede expurgar o passivo de arrendamento da dívida líquida "caso
essas despesas continuem dentro do fluxo operacional". **A condição não se
verifica**, e removê-lo seria um erro no sentido perigoso.

Sob IFRS 16 / CPC 06 R2, obrigatório no Brasil desde 2019, o passivo de
arrendamento e o ativo de direito de uso entram **juntos** no balanço, e o
aluguel se parte em depreciação do direito de uso — dentro do EBIT — e juro —
abaixo dele. Conferido pela concordância das duas rotas do capital investido, que
é o teste de qualidade que a própria entidade declara:

| Ativo | Capital investido pelo financiamento | Pelo operacional | Razão |
|---|---:|---:|---:|
| PETR4 | R$ 751,0 bi | R$ 896,8 bi | 1,19 |
| VIVT3 | R$ 82,2 bi | R$ 93,5 bi | 1,14 |
| RENT3 | R$ 58,5 bi | R$ 59,9 bi | 1,02 |
| AZZA3 | R$ 10,1 bi | R$ 8,7 bi | 0,86 |

Se o passivo estivesse na dívida sem o ativo correspondente no imobilizado, a
rota do financiamento seria sistematicamente maior. Ela não é. A depreciação
sobre o imobilizado confirma pelo outro lado: 0,32 na VIVT3 e 0,28 na RADL3,
contra 0,09 na PETR4 e na WEGE3, que não têm loja alugada.

Como o NOPAT é anterior ao juro do arrendamento, o fluxo descontado é devido
também ao arrendador — e deduzir o passivo na ponte é o tratamento consistente,
que é o de Damodaran depois do IFRS 16. Removê-lo subtrairia obrigação real e
inflaria o capital próprio.

**Isolar o juro bancário do arrendamento e do câmbio, como o apontamento pede
para a AZZA3, a fonte não permite:** ela publica uma única despesa financeira. A
alavancagem responde à mesma pergunta com dado que existe, e é o que a decisão 33
adota.
