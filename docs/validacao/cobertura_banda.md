# A banda cobre o que aconteceu? — item C2

Medido em 14/09/2026 por `tool/cobertura_banda.py`, sobre
`docs/validacao/backtest_aplicativo.json` (de
`dart run tool/backtest_valuation.dart --montagem aplicativo`). Dados em
[cobertura_banda.json](cobertura_banda.json). Decisão:
[92](../decisoes/092-a-incerteza-e-a-faixa-calibrada-e-os-cenarios-sao-sensibilidade.md).

> **Remedido em 21/09/2026, sobre o motor da Fase 3.** O item C5 restaurou a
> base bruta — CVM ingerida, COTAHIST, Tesouro, FRE, registro e complemento da
> B3 — e o backtest foi reexecutado: **10.919 observações, 31 coortes**. Os
> números abaixo, salvo onde a seção diz o contrário, são os da leitura anterior;
> o JSON ao lado é o de hoje. **A forma escolhida continua passando**: 90% nominal cobre 88,1% em 12 meses e 89,3% em 36, com desvio máximo de 2,6 p.p. contra o limite de 5 da §9 — agora sobre o motor da Fase 3, que é o que o item C2c pedia.
>
> **E de novo em 22/09/2026, sobre o motor que fecha a Fase 3** — com as versões
> antigas dos documentos (item B8) e o juro da rota derivada pela curva (item
> B24): **87,8%** em 12 meses e **88,4%** em 36, desvio máximo de **2,2** e
> **2,8 p.p.** A forma não foi reescolhida, e o pacote do aplicativo foi regerado.
> **Com o item B26** (o prêmio de crédito que sumia sem despesa financeira):
> **87,8%** e **88,9%**, desvios de 2,2 e **3,5 p.p.** — continua dentro dos 5.

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

**Remedida na quarta rodada**, sobre a execução com a volatilidade do papel, que
reproduz esta com um papel a mais no universo da fonte: 84,8 / 74,9 / **49,0**%
e 83,6 / 73,0 / 47,0% — o terceiro decimal. **O que vai ao aplicativo mudou na
§10**: a forma fixada antes de medir (§9) cobre, e é ela que o pacote leva.

## 9. A forma fixada antes de medir — quarta rodada, item C2b

**Escrito em 15/09/2026, antes de qualquer cobertura desta forma ser calculada, e
não alterado depois.** O resultado fica na §10. O que já tinha sido visto quando
este texto foi escrito está declarado abaixo.

**O que já se sabia, e de onde a forma sai.**

1. **As deslistadas não são a causa.** Calibrada em todas as companhias, a faixa
   de 90% cobre 90,4% das deslistadas em 12 meses e 96,3% em 36, contra 84,1% e
   82,1% das listadas ([cobertura_banda_trimestral.json](cobertura_banda_trimestral.json), bloco `c2b`).
2. **O choque comum às coortes é pequeno, e a cauda de baixo muda.** O desvio da
   mediana de `log(W/V)` entre coortes é de 0,18 em 12 meses e 0,22 em 36, contra
   0,98 e 1,13 dentro delas. O P5 de `log(W/V)` vai de +0,05 a +0,27 nas coortes
   de 2018 para −0,54 a −1,08 nas de 2021 e 2022, em 12 meses; em 36, de −0,23 a
   +0,09 para −1,06 a −1,26. É um regime de dispersão, e não de nível.
3. **O centro da forma do aplicativo está errado.** Ela impõe `b = 1` em
   `log(W/P₀) = a + b·log(V/P₀)`, e o medido é 0,019 em 12 meses e 0,077 em 36
   (§8); por isso cobre 68,9% e 64,8% no terço de maior potencial.
4. **A calibragem de 36 meses tem pouca informação.** Cada coorte de teste é
   calibrada com no máximo dez coortes sobrepostas — 1,4 janela independente pela
   estrutura da [decisão 96](../decisoes/096-o-t-da-habilidade-e-corrigido-pela-sobreposicao-contra-o-critico-dela.md).
5. **Seis formas já foram medidas** na terceira rodada (§8). Esta é a sétima, e a
   única desta rodada.

**A forma: convergência parcial na escala da volatilidade do papel.** É a
simulação histórica filtrada (Barone-Adesi, Giannopoulos e Vosper, 1999) sobre a
convergência parcial da §4: a dispersão que muda de regime é levada pela
volatilidade que se conhece na data, e o centro é o quanto o preço de fato
convergiu.

- `σ` é o desvio-padrão amostral dos retornos logarítmicos diários do papel nos
  252 pregões até a data, na série que a própria avaliação usa — a janela do
  beta —, anualizado por √252. Com menos de 120 retornos, a observação fica sem
  `σ`.
- Na calibragem, `a` e `b` saem por mínimos quadrados de `r = log(W/P₀)` sobre
  `u = log(V/P₀)`, e `z = (r − a − b·u) / σ`. As bordas são os quantis de `z` em
  `(1 − q)/2` e `(1 + q)/2`.
- A faixa de um papel é `P₀·exp(a + b·u + σ·z_inferior)` a
  `P₀·exp(a + b·u + σ·z_superior)`.

**A medição é a da §8, sem mudança.** Cada coorte de teste é calibrada só com as
coortes cujo horizonte já tinha terminado na data dela, com 30 observações no
mínimo; 12 e 36 meses; retorno total; listadas e deslistadas; preço justo
positivo. Só entram observações com `σ`, e as formas de controle — em torno do
justo, a do aplicativo, e a convergência parcial sem escala — são medidas sobre
exatamente as mesmas observações.

**O critério é o do R2**: cobertura a até 5 p.p. da nominal nas faixas de 90, 80 e
50%, em 12 e em 36 meses.

**O que se faz com o resultado.**

- **Passa nos dois horizontes**: a forma vai ao aplicativo, o cartão diz a
  frequência, e o C2b fecha. O C2c passa a ser remedir esta forma sobre o motor da
  Fase 3, sem escolher outra.
- **Não passa em algum**: a forma vai ao aplicativo se o maior desvio dela nas
  seis leituras não for maior que o da forma em torno do justo nas mesmas
  observações; se for, o aplicativo fica com a do justo. O cartão diz a cobertura
  medida. O C2b fecha com a forma fixada e medida, e o R2 fica com o C2c, que
  remede esta forma sobre o motor da Fase 3 — sem escolher outra — ou declara, por
  decisão, por que a amostra não fecha o R2.
- **Em nenhum caso outra forma é medida nesta rodada.**

São informados, sem entrar no critério: a cobertura por coorte, por terço de
potencial, nas listadas e nas deslistadas, só nas coortes de 30/09, e quantas
observações ficaram sem `σ`.

## 10. O resultado da forma fixada — e a faixa passa a cobrir

Medido em 15/09/2026 por `python tool/cobertura_banda.py`, sobre a mesma
montagem da §8 reexecutada com a volatilidade do papel em cada observação
(`docs/validacao/backtest_trimestral.json`). A execução reproduz a da §8 —
10.863 observações idênticas, três valores de liquidez e um papel a mais que a
fonte passou a listar, 10.874 no total. Decisão:
[100](../decisoes/100-a-faixa-calibrada-sai-da-volatilidade-do-papel-e-o-justo-entra-com-o-peso-medido.md).

**A forma da §9 cobre nos dois horizontes, e é a única que cobre:**

| fora da amostra | 12 meses: 90 / 80 / 50% | desvio | 36 meses: 90 / 80 / 50% | desvio |
|---|---|---:|---|---:|
| **convergência na escala da volatilidade** | **87,9 / 79,0 / 50,3** | **2,1 p.p.** | **88,2 / 80,4 / 51,2** | **1,8 p.p.** |
| em torno do justo (a do aplicativo até aqui) | 84,6 / 74,9 / 48,9 | 5,4 p.p. | 83,5 / 72,8 / 46,6 | 7,2 p.p. |
| convergência parcial, sem a escala | 85,9 / 78,3 / 49,5 | 4,1 p.p. | 82,6 / 72,5 / 43,9 | 7,5 p.p. |

As três sobre as mesmas observações: 3.136 de teste em 12 meses e 1.271 em 36.
Ficaram de fora 34 observações em 12 meses e 30 em 36, de 3.551 e 2.611
elegíveis, por não terem 120 retornos na janela.

**É a escala que conserta, e não o centro.** A convergência parcial sozinha
melhora 12 meses e piora 36; com a volatilidade dividindo o resíduo, os dois
passam. O que a §9 diagnosticou era isso: a dispersão muda de regime entre as
coortes, e a volatilidade que se conhece na data carrega parte dessa mudança.

**Onde ela continua desigual.** Por coorte de teste, a cobertura de 90% vai de
59,8% (30/09/2019) a 100% (30/09/2023) em 12 meses, e de 70,2% (30/06/2021) a
96,6% (31/03/2023) em 36 — uma dispersão maior que a da faixa em torno do justo
(63,6% a 93,3%, e 79,4% a 90,7%). **Ela calibra na média das coortes, não em cada
uma**, e as piores continuam sendo as primeiras, calibradas com pouca coorte.
Por terço de potencial ela é uniforme, o que a do justo não era: 88,1 / 88,5 /
87,0% em 12 meses e 83,0 / 90,6 / 90,9% em 36, contra 88,1 / 97,4 / 68,9% e
91,6 / 94,8 / 64,3%. Nas deslistadas cobre 86,0% e 94,1%; nas listadas, 88,1% e
87,5%. Só nas coortes de 30/09: 88,7 / 82,3 / 56,8% e 85,9 / 72,9 / 50,2%.

**O preço justo entra com o peso que a medição deu, e ele é pequeno.** O centro é
`a + b·log(V/P₀)` com `a = 0,080` e `b = 0,028` em 12 meses, e `a = 0,144` e
`b = 0,083` em 36. Dobrar o preço justo move a faixa 2% em 12 meses e 6% em 36 —
o resto é o preço de hoje e a volatilidade do papel. **A faixa que cobre não é
uma faixa em torno do preço justo**, e o cartão do aplicativo passou a dizer
isso.

**A faixa de 80% que o aplicativo mostra**, por volatilidade do papel:

| σ do papel | 12 meses | 36 meses |
|---|---|---|
| 30% ao ano | 0,76 a 1,57 × o preço | 0,68 a 2,11 × o preço |
| 60% ao ano | 0,53 a 2,26 × o preço | 0,40 a 3,87 × o preço |

Contra 0,76 a 8,16 × o **preço justo** em 12 meses e 0,69 a 9,97 × em 36, da
forma anterior. A faixa ficou muito mais estreita porque passou a ser sobre o
preço, e não sobre um preço justo que erra o realizado por um fator de dezenas.

**O que isto não diz.** Não diz que o preço justo está certo: o erro dele contra
o realizado continua o da §8, e é justamente por isso que `b` é pequeno. Não diz
que a faixa de 36 meses está demonstrada: cada coorte de teste é calibrada com o
equivalente a 1,4 janela independente (§9), e dez coortes de teste sobrepostas
não são dez observações. **O que ela diz é que a incerteza que o aplicativo
declara passou a conter o que aconteceu na frequência que promete**, fora da
amostra, nos dois horizontes — e é isso que o R2 pede.

## 11. A mesma forma sobre o motor da decisão 102 — uma primeira réplica

A decisão 102 mudou o preço justo de toda a via da firma, e o backtest foi
reexecutado em 16/09/2026. `python tool/cobertura_banda.py` refez a medição da §10
**sem mudar nada da forma nem da regra**: a convergência parcial na escala da
volatilidade, com `a`, `b` e os `z` recalibrados nas coortes do motor novo. É uma
réplica sobre um motor diferente daquele em que a forma foi escolhida — não é o
C2c, que remede sobre o motor que a Fase 3 inteira deixar.

| fora da amostra | 12 meses: 90 / 80 / 50% | desvio | 36 meses: 90 / 80 / 50% | desvio |
|---|---|---:|---|---:|
| §10, motor de 15/09 | 87,9 / 79,0 / 50,3 | 2,1 p.p. | 88,2 / 80,4 / 51,2 | 1,8 p.p. |
| **motor de 16/09** | **88,2 / 78,7 / 51,6** | **1,8 p.p.** | **88,9 / 78,7 / 49,6** | **1,3 p.p.** |
| em torno do justo, mesmas observações | 84,1 / 73,1 / 44,9 | 6,9 p.p. | 84,1 / 75,1 / 47,3 | 5,9 p.p. |

Sobre 2.966 observações de teste em 12 meses e 1.193 em 36; ficaram sem
volatilidade 30 de 3.365 e 26 de 2.497. **A forma continua cobrindo, e a regra
continua mandando-a ao aplicativo.** Por coorte, a de 90% vai de 54,6% a 100% em 12
meses e de 72,0% a 97,1% em 36 — a mesma desigualdade da §10. Só nas coortes de
30/09: 88,8 / 81,4 / 57,1% e 86,4 / 75,6 / 50,0%.

O centro mudou pouco: `a = 0,078` e `b = 0,023` em 12 meses, `a = 0,130` e
`b = 0,070` em 36. O preço justo continua entrando com peso pequeno.
