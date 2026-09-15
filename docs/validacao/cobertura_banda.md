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
deslistadas do A3.4 é o C2b.

**Os 36 meses têm 231 observações de teste em duas coortes vizinhas**, e o
critério foi atingido com pouca folga na de 80%.
