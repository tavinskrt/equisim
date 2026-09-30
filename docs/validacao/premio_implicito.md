# O prêmio de risco implícito no preço do mercado

Medido em 29/09/2026, a pedido do orientador, como segunda resposta à pergunta
«dá para capturar o prêmio de mercado do CAPM, em vez de fixá-lo em 5,5%?». A
primeira, o prêmio **histórico** do Ibovespa contra o CDI, está em
[premio_historico.md](premio_historico.md) e sai negativo na maior parte das
datas. Esta olha para a frente: qual retorno o preço de hoje das ações está
embutindo. **É medição: nada foi ligado no motor.**

Reproduz-se com:

```bash
dart run tool/premio_implicito.dart
```

O resultado completo, trimestre a trimestre, está em
[premio_implicito.json](premio_implicito.json).

---

## 1. A ideia, sem fórmula

O preço de uma ação é o valor, hoje, do dinheiro que ela vai pagar ao dono no
futuro. Isso vale também para a bolsa inteira: o valor de mercado de todas as
companhias juntas é o valor, hoje, de todos os dividendos que elas vão
distribuir.

Sabendo **o preço** (o valor de mercado somado) e **o dinheiro distribuído**
(os dividendos e o juro sobre capital próprio dos últimos doze meses), e
supondo **quanto esse dinheiro cresce** por ano, dá para descobrir a taxa de
retorno que faz as duas coisas baterem. Essa é a taxa que o mercado está
cobrando para carregar ações. Tirando dela a taxa do título prefixado de dez
anos, sobra o **prêmio implícito**: quanto o mercado está pedindo a mais para
ficar na bolsa em vez de no Tesouro.

É o método de Damodaran, que publica o prêmio implícito do S&P 500 todo mês.

## 2. A conta

Em cada data, com a bolsa inteira:

```
rendimento = dinheiro distribuído nos últimos 12 meses ÷ valor de mercado
r          = rendimento × (1 + g) + g           (a taxa que o preço embute)
prêmio     = (1 + r) ÷ (1 + prefixado de 10 anos) − 1
```

| Peça | De onde vem |
|---|---|
| Valor de mercado | Ações de cada companhia na data (Formulário de Referência, conferidas contra o preço — §3) vezes o fechamento da B3 (COTAHIST), espécie a espécie, pelo mesmo `ValorDeMercado.naData` do backtest |
| Dinheiro distribuído | Os proventos em dinheiro da B3 com data ex nos doze meses anteriores: dividendo e juro sobre capital próprio, bruto. De cada companhia, a soma de `provento ÷ preço com direito` na classe mais negociada, vezes o valor de mercado dela |
| `g`, o crescimento | O crescimento nominal da economia na data — IPCA e IBC-Br de dez anos, pelas âncoras de mercado do próprio aplicativo (`ResolveMarketAnchors`). É o teto que o motor usa para o crescimento na perpetuidade |
| Prefixado de 10 anos | A curva do Tesouro Direto na data (`TreasuryCurve`), a mesma de onde o motor tira a taxa livre de risco |

**Por que um estágio só.** Damodaran projeta cinco anos com o crescimento
previsto pelos analistas e depois uma perpetuidade. Sem consenso de analistas,
os dois estágios usam o mesmo `g`, e a conta de dois estágios vira a de um só.

**Por que o prefixado inteiro.** Em reais, Damodaran tira do título do governo
o risco de calote do país antes de chamá-lo de livre de risco. O motor não tira:
a taxa livre de risco dele é a curva do Tesouro como ela é (decisão 117, que
recusou o prêmio-país por contar duas vezes). Para o número servir ao motor, o
prêmio tem de ser medido contra a mesma taxa.

**Fisher, e não subtração**, como na medição histórica. O CAPM do motor soma
(`Ke = Rf + β × prêmio`); o prêmio que, somado, reproduz `r` com beta 1 é
`r − Rf`, um pouco maior em módulo — está ao lado nos números de hoje (§4).

**A versão normalizada** é a média dos prêmios implícitos dos trimestres dos
últimos cinco e dos últimos dez anos até a data. Suaviza o ciclo, como a média
de dez anos que Damodaran publica ao lado do número do mês. Só vale com pelo
menos 80% dos trimestres da janela.

**As datas.** O último dia de cada trimestre, de 31/03/2011 a 30/06/2026 — 62
trimestres —, e a data da entrada congelada, 14/09/2026. O COTAHIST local
começa em 2010, e o dinheiro distribuído pede doze meses antes da data.

---

## 3. Os dados, e dois defeitos que a medição achou

**As companhias são as listadas hoje**: as 292 do universo com ponte para a
CVM, menos duas sem contagem por data e nove sem o histórico de proventos (logo
abaixo) — 281. As que saíram da bolsa não têm os proventos no arquivo, e somar o
valor delas sem o dinheiro que pagaram derrubaria o rendimento. O agregado das
datas antigas é, portanto, o das companhias que sobreviveram até hoje. Na data
congelada entram 259 (as outras não negociaram perto da data), 185 delas com
provento nos doze meses, somando R$ 4,94 trilhões.

### 3.1 A contagem de ações erra de escala — item B43

A primeira rodada deu **R$ 144 trilhões** de valor de mercado em 30/06/2016, com
uma companhia valendo 99% da bolsa. Era a Ampla: ela agrupou as ações de
40.000 para 1 em dezembro de 2015 (de 3,9 trilhões para 98 milhões), e uma
correção do formulário, reenviada em maio de 2016, voltou aos 3,9 trilhões —
vezes o preço de depois do grupamento.

Conferindo o arquivo inteiro, o erro aparece **nos dois sentidos**. Às vezes a
correção repete a contagem velha (Ampla em 2016, IRB em 2024, Hapvida em 2025).
Às vezes a correção é o **único** registro de um grupamento de verdade: a
Magazine Luiza agrupou 10 para 1 em maio de 2024, e a contagem só cai de
7,39 bilhões para 739 milhões na correção de maio de 2025. A fonte da entrada
não separa os dois casos. **O preço separa**: num grupamento de dez para um, o
preço fica dez vezes maior de um pregão para o outro.

A regra desta medição parte da contagem mais recente e anda para trás. Mudança
de até três vezes vale como veio (emissão, recompra, conversão). Mudança maior
só vale se o preço bruto deu o salto correspondente entre a data da entrada e
400 dias depois (a aprovação vem meses antes da data ex), e passa a valer no
dia do salto. Sem o salto, a entrada é descartada. **275 entradas foram
descartadas**, a maioria de companhias que mudaram de tamanho por fusão ou
emissão grande, que ficam fora da soma antes da mudança: de 14 companhias fora
em 2011 a 2 em 2026, e nenhuma na data congelada.

**O mesmo defeito está no backtest**, que lê o mesmo arquivo sem conferir: a
HAPV3 de 2025 entra com valor de mercado de R$ 278 bilhões (quinze vezes o
real), a IRBR3 de 2024 com R$ 78 a 110 bilhões (trinta vezes), a MGLU3 de
30/06/2024 a 31/03/2025 com dez vezes o real — e a de 31/03/2025 foi avaliada,
com o divisor por ação dez vezes maior. Registrado como **B43**.

### 3.2 Nove emissores sem o histórico de proventos — item B44

A consulta de proventos da B3 é feita pelo nome de pregão, e o nome com barra
volta vazio: os **nove** emissores com barra no nome — `AMBEV S/A`,
`KLABIN S/A`, `CURY S/A`, `LIGHT S/A`, `IMC S/A`, `OUROFINO S/A`,
`EMBPAR S/A`, `HAGA S/A` e `WETZEL S/A` — vieram sem provento nenhum, e nenhum
emissor com barra veio com provento. Aqui eles ficam fora da soma: tratá-los
como companhias que não pagaram derrubaria o rendimento (só a Ambev é quase 5%
da bolsa).

**O mesmo defeito está no retorno total do backtest** (decisão 89): nas 66
observações avaliadas desses emissores (de 3.070), o retorno total é igual ao
de preço — Ambev e Klabin sem nenhum dividendo. E o pacote de proventos do
aplicativo também não tem os nove. Registrado como **B44**; corrigir pede
consultar a B3 de novo.

---

## 4. O prêmio implícito, trimestre a trimestre

Fim de cada ano, e a data congelada (os 62 trimestres estão no JSON):

| Data | Companhias | Valor (R$ bi) | Rendimento | g nominal | r implícito | Prefixado 10 anos | **Prêmio** | Média 5 anos | Média 10 anos |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 31/12/2011 | 143 | 1.437 | 4,79% | 11,08% | 16,40% | 11,35% | **4,54%** | — | — |
| 31/12/2012 | 153 | 1.575 | 3,71% | 10,00% | 14,08% | 9,23% | **4,44%** | — | — |
| 31/12/2013 | 153 | 1.660 | 3,87% | 9,26% | 13,49% | 13,21% | **0,25%** | — | — |
| 31/12/2014 | 156 | 1.432 | 4,89% | 8,69% | 14,00% | 12,34% | **1,48%** | 2,90% | — |
| 31/12/2015 | 156 | 1.164 | 4,54% | 8,12% | 13,03% | 16,52% | **−2,99%** | 2,09% | — |
| 31/12/2016 | 164 | 1.777 | 3,69% | 7,21% | 11,17% | 11,39% | **−0,20%** | 1,38% | — |
| 31/12/2017 | 177 | 2.331 | 3,42% | 6,72% | 10,37% | 10,31% | **0,06%** | 0,53% | — |
| 31/12/2018 | 176 | 2.841 | 4,41% | 6,82% | 11,53% | 9,20% | **2,14%** | 0,23% | 1,38% |
| 31/12/2019 | 182 | 3.786 | 4,02% | 5,95% | 10,22% | 6,85% | **3,15%** | 0,46% | 1,55% |
| 31/12/2020 | 207 | 4.270 | 2,68% | 5,00% | 7,81% | 6,89% | **0,85%** | 0,93% | 1,51% |
| 31/12/2021 | 247 | 3.902 | 6,93% | 5,76% | 13,09% | 10,71% | **2,14%** | 1,01% | 1,19% |
| 31/12/2022 | 249 | 3.704 | 9,41% | 5,74% | 15,69% | 12,69% | **2,66%** | 1,46% | 0,99% |
| 31/12/2023 | 251 | 4.309 | 7,34% | 5,98% | 13,76% | 10,34% | **3,10%** | 2,01% | 1,12% |
| 31/12/2024 | 253 | 3.622 | 7,09% | 6,73% | 14,30% | 15,16% | **−0,74%** | 1,66% | 1,06% |
| 31/12/2025 | 256 | 4.519 | 7,83% | 6,89% | 15,26% | 13,77% | **1,31%** | 1,52% | 1,23% |
| **14/09/2026** | 259 | 4.944 | 6,07% | 6,78% | 13,26% | 14,38% | **−0,98%** | **1,55%** | **1,23%** |

- **Nos 62 trimestres**, o prêmio implícito vai de −2,99% (31/12/2015) a
  +5,10% (30/06/2012), com mediana de 1,36%, e é **negativo em 12**.
- Por período, a média é de 2,09% de 2011 a 2015, 0,93% de 2016 a 2020 e 1,37%
  de 2021 a 2026.
- **Ele fica negativo quando o prefixado dispara**, e não quando a bolsa paga
  pouco: em 2015 o prefixado de dez anos foi a 16,5%, e em 2024 a 15,2%, com o
  rendimento das ações em 4,5% e 7,1%.
- **Hoje ele é −0,98%**: o preço de hoje embute 13,26% ao ano, e o prefixado de
  dez anos paga 14,38%. Na forma que o CAPM do motor soma (`r − Rf`), −1,12%.

## 5. A versão normalizada: positiva e estável

| | Implícito do trimestre | Média de 5 anos | Média de 10 anos | *Histórico de 10 anos* |
|---|---|---|---|---|
| Hoje | −0,98% | **1,55%** | **1,23%** | *+1,85%* |
| Hoje, na forma que soma (`r − Rf`) | −1,12% | 1,73% | 1,36% | — |
| Nas 31 coortes do backtest: faixa | −1,16% a +4,64% | +0,13% a +2,05% | +0,98% a +1,55% (28 coortes) | *−7,71% a +2,35%* |
| Mediana | 1,61% | 1,01% | 1,14% | *−1,77%* |
| **Datas com prêmio negativo** | 6 de 31 | **0 de 31** | **0 de 28** | *25 de 31* |

A média de dez anos só existe a partir de 31/12/2018 (antes disso a série não
tem 80% dos quarenta trimestres). A tabela coorte a coorte está no JSON
(`serie`, campos `normalizado5` e `normalizado10`).

**As médias não ficam negativas em nenhuma data**, e a de dez anos fica entre
1,0% e 1,6% o tempo todo. É o que faltava ao histórico, que dependia da janela e
era negativo em 25 de 31 datas.

**E os dois métodos concordam hoje.** O histórico de dez anos dá +1,85%; o
implícito normalizado, 1,2% a 1,6%. Por dois caminhos independentes — o que a
bolsa rendeu e o que o preço dela embute —, o prêmio sobre o prefixado brasileiro
na última década fica entre 1% e 2%. Nas datas das coortes eles se separam: o
histórico carrega a queda da bolsa de 2008 a 2016, e o implícito não.

---

## 6. O que cada um faz ao aplicativo

O universo inteiro reavaliado sobre a entrada congelada:

| Prêmio | Avaliados | Potencial mediano | Potencial acima de zero | Preço justo, na mediana | Postos contra 5,5% |
|---|---:|---:|---:|---:|---:|
| 5,5% fixo | 97 | −45,4% | 15 de 97 | — | 1,000 |
| Implícito de hoje (−0,98%) | 109 | −27,8% | 36 de 109 | +60,7% | 0,954 |
| Média de 5 anos (1,55%) | 108 | −37,7% | 25 de 108 | +31,1% | 0,984 |
| Média de 10 anos (1,23%) | 108 | −36,7% | 28 de 108 | +34,0% | 0,980 |

Os cinco casos do guia de estudo:

| Prêmio | WEGE3 | ITUB4 | VALE3 | SAPR11 | RENT3 |
|---|---:|---:|---:|---:|---|
| 5,5% fixo | R$ 12,53 | R$ 21,76 | R$ 70,25 | R$ 36,74 | recusada |
| Implícito de hoje (−0,98%) | R$ 19,16 | R$ 35,15 | R$ 101,99 | R$ 52,43 | recusada |
| Média de 5 anos (1,55%) | R$ 15,84 | R$ 28,45 | R$ 86,96 | R$ 45,18 | recusada |
| Média de 10 anos (1,23%) | R$ 16,19 | R$ 29,16 | R$ 88,63 | R$ 46,00 | recusada |
| **Preço de mercado** | R$ 50,74 | R$ 42,35 | R$ 75,48 | R$ 34,74 | R$ 35,59 |

**Com a média de cinco ou de dez anos, o preço justo sobe cerca de um terço na
mediana**, o potencial mediano vai de −45% para −37%, e a ordem entre as ações
quase não muda (0,98). O implícito de hoje, negativo, leva a −28% e mexe mais na
ordem (0,954).

## 7. A sensibilidade ao crescimento

O `g` é premissa: o crescimento de longo prazo dos dividendos igual ao da
economia. Um ponto a mais ou a menos nele move o prêmio em cerca de um ponto:

| | `g` − 1 p.p. | Central | `g` + 1 p.p. |
|---|---:|---:|---:|
| Implícito de hoje | −1,90% | −0,98% | −0,05% |
| Média de 5 anos | 0,60% | 1,55% | 2,51% |
| Média de 10 anos | 0,28% | 1,23% | 2,18% |

Mesmo com um ponto a mais de crescimento, as médias ficam em 2,2% a 2,5%, menos
da metade dos 5,5%.

---

## 8. O que isto quer dizer

1. **Dá para capturar o prêmio do mercado, olhando para a frente, sem sair
   negativo** — pela média de cinco ou de dez anos do implícito. Ela responde à
   pergunta do orientador com um número que se mede a cada data, que não depende
   de escolher a janela do passado e que fica positivo em todas as 31 datas do
   backtest.
2. **O número do mercado é muito menor que 5,5%.** Contra o prefixado
   brasileiro, o preço das ações embute de 1% a 1,6% de prêmio na média da
   década. Com beta 1, o motor exige hoje 19,9% ao ano (14,4% + 5,5%); o preço
   do mercado embute 13,3%.
3. **O implícito do trimestre não serve cru.** Ele fica negativo quando o
   prefixado dispara (2015, 2024 e hoje), e prêmio negativo faz o beta alto
   baratear o capital, como no histórico.
4. **Ele aproxima o motor do mercado, mas não fecha a distância.** Com a média
   de dez anos, o potencial mediano fica em −37%. A maior parte do desacordo de
   nível continua onde a decisão 116 o encontrou: na rentabilidade das
   companhias abaixo do custo de capital, que o terminal carrega (decisão 112).
5. **O efeito é de nível, não de ordem**: postos de 0,98 com as médias.
6. **Há uma circularidade a declarar se isto for ligado.** Um prêmio tirado do
   preço do mercado inteiro calibra o **nível** do motor pelo mercado — o
   potencial mediano chega mais perto de zero em parte por construção. O teste
   que continua valendo é o de **ordem** entre as ações (o R3), que um prêmio
   igual para todas não mexe.

## 9. O que isto não diz

- **Recompra de ações não entra** no dinheiro distribuído. Damodaran soma
  dividendos e recompras; aqui só os proventos em dinheiro da B3. Com recompra,
  o rendimento e o prêmio seriam maiores.
- **Os doze meses incluem proventos extraordinários** — os da Petrobras em 2022
  levam o rendimento a 9,4% no fim daquele ano. A média de cinco ou dez anos
  dilui, mas não tira.
- **O crescimento é premissa**, e a §7 mostra o tamanho dela.
- **As companhias são as sobreviventes** (§3), e o agregado não pondera como o
  Ibovespa: é a soma do valor de mercado das 259 companhias da data, e não a
  carteira teórica do índice.
- **O implícito das coortes não foi levado ao backtest.** A média de cinco anos
  existe nas 31 coortes e a de dez anos em 28, só com dado até a data de cada
  uma; rodar o backtest com elas mediria o efeito sobre a faixa calibrada e a
  habilidade. Fica disponível — e depende do B43 e do B44, que mexem nas mesmas
  coortes.
- **Esta medição não é a da decisão 116.** Aquele «implícito» de −3,9% era o
  prêmio que zerava o potencial mediano **do motor**; este é o que iguala o
  preço **do mercado** aos dividendos. O de lá diz que o desacordo não é só do
  prêmio; o de cá diz qual prêmio o mercado está pagando.
