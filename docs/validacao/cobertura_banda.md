# A banda cobre o que aconteceu? — item C2

Medido em 14/09/2026 por `tool/cobertura_banda.py`, sobre
`docs/validacao/backtest_aplicativo.json` (de
`dart run tool/backtest_valuation.dart --montagem aplicativo`). Dados em
[cobertura_banda.json](cobertura_banda.json). Decisão:
[92](../decisoes/092-a-incerteza-e-a-faixa-calibrada-e-os-cenarios-sao-sensibilidade.md).

## 1. A amostra

As coortes de 30/09 de 2018 a 2025 com a **montagem do aplicativo na data de
cada uma**: curva do Tesouro daquele dia, CVM recebida até ali, setor da B3, prazo
das outorgas do Formulário de Referência recebido até ali — conferido: lido em
14/09/2026, o prazo reproduz o pacote do aplicativo em 35 de 35 tickers — e beta
de retorno total. A contagem oficial da B3 fica de fora, porque é de hoje.

São 2.633 observações, 845 avaliadas. Com o horizonte já terminado em
04/09/2026 e a distribuição de Monte Carlo com os 10 mil sorteios do aplicativo:
698 em 12 meses (coortes de 2018 a 2024) e 491 em 36 (2018 a 2022). As 38
avaliações que combinam as duas vias não têm banda (decisão 38) e ficam fora da
§2; entram na §4, que só precisa do preço justo.

## 2. O que se compara

O preço justo `V` é valor, e não previsão de preço. A leitura observável é a que
o projeto declara: o preço converge ao valor em 36 meses (decisão 26), pelo
caminho que anualiza o potencial, `P_h = P₀ · (V/P₀)^(h/36)`. Cada borda da banda
vai ao horizonte pelo mesmo caminho.

O realizado `W` é o preço mais os proventos reinvestidos na data ex — o retorno
total da decisão 89 —, porque `V` inclui a distribuição e o preço depois da data
ex não. Sobre o retorno de preço, e com o preço justo capitalizado pelo custo do
capital próprio até o horizonte, a conclusão não muda (§3).

## 3. As bandas declaradas não cobrem

| banda | nominal | 12 meses | 36 meses |
|---|---:|---:|---:|
| Monte Carlo `P5–P95` | 90% | **8,2%** | **7,7%** |
| Monte Carlo `P10–P90` | 80% | 6,9% | 6,1% |
| Monte Carlo `P25–P75` | 50% | 3,2% | 2,9% |
| cenários, pessimista a otimista | — | 12,6% | 13,2% |
| `P5–P95` sobre o retorno de preço | 90% | 8,9% | 8,6% |
| `P5–P95` com o justo capitalizado pelo `Ke` | 90% | 9,7% | 11,4% |

Fora da `P5–P95`, o realizado fica **acima** em 70,6% e 71,3% dos casos, e
abaixo em 21,2% e 21,0%.

**Por que — nível, largura e convergência:**

| | 12 meses | 36 meses |
|---|---:|---:|
| realizado ÷ mediana da distribuição, na mediana | 2,09× | 2,11× |
| largura mediana da banda, `P95 ÷ P5` | 1,31× | 1,32× |
| largura de 90% do realizado em torno do justo | 43,3× | 46,9× |
| desvio de `log(V/P₀)` | 1,24 | 1,33 |
| desvio de `log(W/P₀)` | 0,38 | 0,81 |
| `b` em `log(W/P₀) = a + b·log(V/P₀)` | **0,06** | **0,24** |
| `b` que a decisão 26 supõe | 0,33 | 1,00 |

A banda desloca premissas — crescimento em 4 p.p., desconto em 2 — e mede o
quanto o preço justo **responde** a elas. O preço justo, porém, erra o realizado
por um fator que tem desvio de 1,2 a 1,3 em log, e o preço converge a ele **um
quarto do caminho em 36 meses**: por coorte, `b` vai de 0,10 a 0,31. A largura da
banda quase não sabe onde o erro é maior — correlação de postos de +0,15 e +0,07
com o erro absoluto.

## 4. A recalibragem, fora da amostra

Cada coorte de teste é medida só com as coortes cujo horizonte já tinha terminado
na data dela: em 12 meses, a de 2018 calibra a de 2019, as de 2018 e 2019 a de
2020, e assim até 2024; em 36, a de 2018 calibra a de 2021, e as de 2018 e 2019 a
de 2022. Toda avaliação com preço justo positivo entra.

| forma | nominal | 12 meses (651) | 36 meses (231) | largura de 90% |
|---|---:|---:|---:|---:|
| **em torno do justo**: quantis de `log(W/V)` | 90% | **90,2%** | **91,8%** | 42 a 50× em 12m; 60 a 98× em 36m |
| | 80% | **80,3%** | **78,8%** | |
| | 50% | **54,2%** | **52,8%** | |
| convergência parcial: resíduo de `log(W/P₀)` sobre `log(V/P₀)` | 90% | 85,4% | 78,4% | 2,6 a 3,5× em 12m; 5,7 a 8,3× em 36m |
| | 80% | 79,4% | 68,0% | |
| | 50% | 57,8% | 43,7% | |
| só o preço: quantis de `log(W/P₀)` | 90% | 86,2% | 78,8% | 2,8 a 3,8× em 12m; 5,4 a 9,3× em 36m |
| | 80% | 81,0% | 64,1% | |
| | 50% | 58,5% | 43,3% | |

**Só a faixa em torno do justo fica a até 5 p.p. da nominal nos dois
horizontes.** As outras duas são dez vezes mais estreitas e calibram em 12 meses
por pouco, mas não em 36: com duas coortes de calibragem, o choque comum a uma
coorte inteira — o mercado subindo ou caindo junto — não se estima. A faixa em
torno do justo calibra porque a largura dela vem da dispersão do próprio preço
justo contra o preço, que é estável de uma coorte para outra.

**Por coorte**, a de 90% vai de 85,6% a 93,8% em 12 meses, e a de 50%, de 44,4%
a 67,9%. Em 36 meses, 92,9% e 90,7%.

**Por terço de potencial**, a de 90% cobre 85,6%, 100% e 84,5% em 12 meses, e
95,1%, 97,5% e 80,9% em 36: a calibração é marginal. A faixa sabe o quanto o
motor erra em média, e não em qual ativo erra mais — no terço de maior potencial,
ela é curta.

## 5. O que vai para o aplicativo

> **Substituído em 15/09/2026.** O pacote passou a sair da amostra com as
> deslistadas (decisão 94), e a faixa do aplicativo é a da §7. A tabela abaixo é
> a das listadas, de 14/09/2026.

Com todas as coortes, a faixa em torno do justo é:

| horizonte | 50% | 80% | 90% |
|---|---|---|---|
| 12 meses (730) | 1,04 a 4,17× | **0,62 a 9,21×** | 0,43 a 16,97× |
| 36 meses (509) | 1,03 a 4,65× | **0,51 a 9,75×** | 0,35 a 16,05× |

A tela de avaliação mostra a de 80% em reais, nos dois horizontes, com a
cobertura fora da amostra ao lado. Pacote em
`assets/validacao/banda_calibrada.json`; o teste
`test/data/calibrated_band_asset_test.dart` reprova a suíte se ele faltar ou se
alguma cobertura sair de 5 p.p. da nominal.

## 6. O que isto não diz

**Não é previsão de preço.** A faixa de 50% começa no próprio preço justo e vai a
quatro vezes ele: o preço justo ficou, na mediana, na metade do que o papel valeu
depois — o nível que a §0 do plano e a [fase1_padrao.md](fase1_padrao.md) já
mostravam.

**É a amostra dos sobreviventes.** Papel que quebrou entre a coorte e o resgate
não está no universo, e a cauda de baixo do realizado está subrepresentada: a
cobertura verdadeira é menor que a medida, na medida desse viés. Remedir com as
deslistadas do A3.4 é o C2b — **feito em 15/09/2026, na §7**: a cobertura se
manteve, e a cauda de baixo não pesou.

**Os 36 meses têm 231 observações de teste em duas coortes vizinhas**, e o
critério foi atingido com pouca folga na de 80%.

## 7. Com as deslistadas — item C2b

> **Medido sobre a montagem com o preço na base de ações de hoje.** A §8 remede
> na base da data, e lá a faixa não cobre.

Medido em 15/09/2026 por `python tool/cobertura_banda.py`, sobre
`docs/validacao/backtest_aplicativo_deslistadas.json` — a montagem do aplicativo
por data **com as deslistadas da ponte**, listadas e deslistadas na mesma
execução ([habilidade_aplicativo.md](habilidade_aplicativo.md) §2). Dados em
[cobertura_banda_deslistadas.json](cobertura_banda_deslistadas.json). Decisão:
[94](../decisoes/094-a-faixa-calibrada-sai-da-amostra-com-as-deslistadas.md).

**A pergunta que a §6 deixou**: a faixa dos sobreviventes cobre o mundo em que
também há quem saiu da bolsa? A remedição é cruzada — calibrada nas listadas ou
em todas, testada em cada grupo — e fora da amostra, como na §4.

| calibrada em | testada em | 12 meses: 90 / 80 / 50% | n | 36 meses: 90 / 80 / 50% | n |
|---|---|---|---:|---|---:|
| listadas | listadas | 90,2 / 80,3 / 54,2 | 651 | 91,8 / 78,8 / 52,8 | 231 |
| listadas | deslistadas | 87,8 / 76,8 / 47,6 | 82 | 96,2 / 84,6 / 53,8 | 26 |
| **listadas** | **todas** | **89,9 / 79,9 / 53,5** | 733 | **92,2 / 79,4 / 52,9** | 257 |
| todas | listadas | 91,4 / 81,6 / 54,7 | 651 | 92,6 / 81,4 / 48,9 | 231 |
| todas | deslistadas | 90,2 / 80,5 / 50,0 | 82 | 96,2 / 88,5 / 50,0 | 26 |
| **todas** | **todas** | **91,3 / 81,4 / 54,2** | 733 | **93,0 / 82,1 / 49,0** | 257 |

**As duas faixas passam no critério na amostra com as deslistadas.** O pacote do
aplicativo passou a sair dela.

**A cauda de baixo não pesou, e a de cima sim:**

| realizado ÷ justo | P5 | mediana | P95 |
|---|---:|---:|---:|
| listadas, 12 meses | 0,43 | 2,11 | 16,97 |
| deslistadas, 12 meses | 0,53 | 3,58 | 30,40 |
| listadas, 36 meses | 0,35 | 2,11 | 16,05 |
| deslistadas, 36 meses | 0,50 | 3,26 | 21,32 |

As deslistadas avaliadas terminaram acima das listadas em relação ao preço justo.
É o que se esperaria de saídas por aquisição ou oferta de fechamento de capital; o
motivo da saída de cada companhia não foi levantado.

**A faixa do aplicativo, com todas as coortes e as deslistadas:**

| horizonte | 50% | 80% | 90% |
|---|---|---|---|
| 12 meses (831) | 1,11 a 4,61× | **0,64 a 10,67×** | 0,43 a 19,35× |
| 36 meses (597) | 1,14 a 4,81× | **0,55 a 10,86×** | 0,36 a 18,85× |

**Com as deslistadas, as bandas declaradas continuam onde estavam**: a `P5–P95`
cobre 7,9% em 12 meses e 6,7% em 36; os cenários discretos, 11,9% e 12,4%.

**O que continua limitação:** o teste nas deslistadas sozinhas é pequeno — 26
observações em 36 meses —; a calibração é marginal, e no terço de maior potencial
a faixa de 90% cobre 83,9% e 82,3%; e as 126 companhias com ação em bolsa e sem
ponte seguem fora.

## 8. Na base da data, trimestral — e a faixa deixa de cobrir

Medido em 15/09/2026 por `python tool/cobertura_banda.py`, sobre
`docs/validacao/backtest_trimestral.json` — as 31 coortes trimestrais, com as
deslistadas da ponte ampliada (C1d) e **o preço, a contagem e o valor de mercado
na base de ações da data** (C3). Dados em
[cobertura_banda_trimestral.json](cobertura_banda_trimestral.json) e, só com as
coortes de 30/09, em
[cobertura_banda_setembro.json](cobertura_banda_setembro.json). Decisão:
[97](../decisoes/097-a-coorte-forma-preco-contagem-e-valor-de-mercado-na-base-da-data.md).

**Por que remedir.** As §§2 a 7 foram medidas com o preço da coorte na base de
ações de hoje (ver [ponte_por_papel.md](ponte_por_papel.md) §1): o preço justo
estava errado pelo produto dos eventos de ações posteriores, e o realizado sobre o
justo, também. O instrumento corrigido mede outra coisa.

**A faixa em torno do justo, fora da amostra:**

| amostra | 12 meses: 90 / 80 / 50% | n | 36 meses: 90 / 80 / 50% | n |
|---|---|---:|---|---:|
| base de hoje, anual, com as deslistadas (§7) | 91,3 / 81,4 / 54,2 | 733 | 93,0 / 82,1 / 49,0 | 257 |
| **base da data, trimestral, com as deslistadas** | **84,8 / 74,9 / 49,1** | 3.163 | **83,6 / 73,0 / 47,0** | 1.278 |
| base da data, só 30/09 | 84,4 / 75,0 / 48,5 | 732 | 81,8 / 72,5 / 45,7 | 258 |

**Na base da data, a faixa não cobre a até 5 p.p. em nenhum dos dois
horizontes**, nas faixas de 90% e 80%. O R2 deixa de estar atingido.

**Onde ela falha.** Em 12 meses, nas primeiras coortes de teste — as de 2019,
calibradas com uma a quatro coortes de 2018, cobrem de 63% a 75% na de 90% — e no
terço de maior potencial, onde cobre 68,9%; de 2020 em diante, 81% a 93%. Em 36
meses, as dez coortes de teste de 2021 a 2023, calibradas só com as de 2018 a
2020, cobrem de 79% a 91%, e o terço de maior potencial, 64,8%. A largura de 90%
em 12 meses cresce de 15 para 23 vezes o preço justo à medida que a calibragem
ganha coortes.

**O que foi tentado, e não fechou.** Cinco variantes exploratórias, e depois uma
fixada por escrito antes de rodar:

| forma | 12 meses | 36 meses |
|---|---|---|
| marginal, como a §4 | 84,8 / 74,9 / 49,1 | 83,6 / 73,0 / 47,0 |
| por terço de potencial | 86,6 / 76,2 / 45,9 | 81,1 / 70,9 / 42,2 |
| marginal, com quatro coortes de calibragem no mínimo | 86,4 / 76,9 / 50,7 | 83,9 / 74,3 / 49,1 |
| por terço, com quatro coortes no mínimo | 88,7 / 78,1 / 47,4 | 84,4 / 72,7 / 44,3 |
| por terço, só 30/09 | 87,2 / 77,5 / 48,0 | 79,5 / 74,4 / 41,5 |
| **aninhada**: o nível de cada coorte escolhido pela varredura fora da amostra dentro da calibragem dela | 91,8 / 84,2 / **57,8** | 83,6 / 73,0 / 47,0 |

A aninhada acerta a de 90% em 12 meses e passa da de 50%; em 36 meses não há
coorte interna para escolher o nível, e ela é a marginal. **Pela regra fixada
antes, nenhuma outra variante foi tentada nesta rodada.** As alternativas
estreitas da §4, que a §4 descartou por não calibrar em 36 meses, continuam não
calibrando em 36 — 83,6/72,8/43,7% a "só o preço" —, e em 12 meses passam a
calibrar: 86,5/78,5/50,3%.

**A convergência quase some.** Em `log(W/P₀) = a + b·log(V/P₀)`, o `b` é de 0,019
em 12 meses e de 0,077 em 36, contra 0,06 e 0,24 da §3: na base da data, o preço
converge ao preço justo menos de um décimo do caminho em 36 meses. A largura
realizada de 90% em torno do justo é de 28 vezes em 12 meses e de 41 em 36.

**As bandas declaradas continuam onde estavam**: a `P5–P95` de Monte Carlo cobre
7,1% em 12 meses e 8,3% em 36, e os cenários discretos, 10,9% e 13,2%.

**O que vai para o aplicativo** (decisão 97): a faixa em torno do justo desta
amostra, com a cobertura fora da amostra que ela mediu. O cartão só diz "8 de cada
10" quando a cobertura medida fica a até 5 pontos da nominal, e agora não fica: ele
diz a cobertura e que a faixa não está calibrada.

| horizonte | 50% | 80% | 90% |
|---|---|---|---|
| 12 meses (3.550) | 1,26 a 4,29× | **0,76 a 8,16×** | 0,54 a 12,81× |
| 36 meses (2.610) | 1,29 a 4,86× | **0,69 a 9,97×** | 0,41 a 15,56× |
