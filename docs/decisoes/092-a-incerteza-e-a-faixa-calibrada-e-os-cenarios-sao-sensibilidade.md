---
numero: 92
titulo: A incerteza do preço justo é a faixa calibrada fora da amostra nas coortes, e a banda de cenários passa a se declarar sensibilidade
status: aceita
origem: voce
data: 2026-09-14
citacao: >
  Por ora, essa tarefa irá contemplar os itens D1, C2 e C0.
afeta:
  - packages/equisim_core/lib/src/services/valuation/calibrated_band.dart
  - packages/equisim_core/lib/equisim_core.dart
  - packages/equisim_core/test/calibrated_band_test.dart
  - lib/data/repositories/calibrated_band_repository.dart
  - lib/di/providers.dart
  - lib/presentation/valuation/valuation_page.dart
  - assets/validacao/banda_calibrada.json
  - pubspec.yaml
  - test/data/calibrated_band_asset_test.dart
  - tool/cobertura_banda.py
  - tool/backtest_valuation.dart
  - docs/validacao/cobertura_banda.md
  - docs/validacao/cobertura_banda.json
  - scripts/qa/rules.ts
  - CLAUDE.md
substitui: []
---

## Contexto

O item C2 do plano, que é a condição R2 do motor de referência: a banda que o
motor declara tem de conter o resultado realizado na frequência que diz conter,
fora da amostra, em 12 e 36 meses — ou ser recalibrada até conter.

A tela de avaliação mostrava duas bandas: os cenários discretos, pessimista e
otimista, que deslocam crescimento em 3 p.p. e as taxas de desconto em 2 p.p.; e,
com o Monte Carlo ligado, `P5` e `P95` de premissas sorteadas, com a frase "em X%
dos cenários o preço justo supera o preço de mercado". Nenhuma das duas tinha
sido confrontada com o que aconteceu.

**O que se compara.** O preço justo é valor, e não previsão de preço; a única
leitura observável dele é a que o próprio projeto declara, a convergência em 36
meses da [decisão 26](026-horizonte-de-convergencia-de-36-meses.md). O realizado
é o preço mais os proventos reinvestidos na data ex — o retorno total da
[decisão 89](089-proventos-voltam-como-dado-conferido.md) —, porque o valor
apurado inclui a distribuição e o preço depois da data ex não.

## Decisão

1. **A banda de cenários não mede incerteza, e passa a dizer isso.** Nas coortes
   da montagem do aplicativo — de 2018 a 2024 em 12 meses, e a 2022 em 36:

   | banda declarada | nominal | cobre em 12 meses | cobre em 36 meses |
   |---|---:|---:|---:|
   | Monte Carlo `P5–P95` | 90% | 8,2% | 7,7% |
   | Monte Carlo `P25–P75` | 50% | 3,2% | 2,9% |
   | pessimista a otimista | — | 12,6% | 13,2% |

   Erra no nível e na largura: o realizado fica acima da banda em 71% dos casos,
   a 2,1 vezes a mediana dela, e a banda tem 1,3 vez de largura contra 43 a 47
   vezes da dispersão realizada em torno do preço justo. **O cartão de cenários
   passa a se declarar sensibilidade**, e a frase do Monte Carlo diz "sorteios de
   premissas" e que sorteio de premissa não é probabilidade de preço. Nenhum
   número da cascata muda.

2. **A incerteza declarada é a faixa calibrada**: os quantis centrais da razão
   entre o realizado e o preço justo nas coortes, aplicados ao preço justo de
   hoje (`CalibratedBand`). Fora da amostra — cada coorte medida só com as coortes
   cujo horizonte já tinha terminado na data dela —, ela cobre:

   | nominal | 12 meses (651 de teste, 6 coortes) | 36 meses (231, 2 coortes) |
   |---|---:|---:|
   | 90% | 90,2% | 91,8% |
   | 80% | 80,3% | 78,8% |
   | 50% | 54,2% | 52,8% |

   Todas a até 5 p.p. da nominal. A tela mostra a de 80%, em 12 e 36 meses, com
   a cobertura fora da amostra ao lado; o pacote
   `assets/validacao/banda_calibrada.json` sai de `tool/cobertura_banda.py` com
   todas as coortes, e é versionado.

3. **A faixa é em torno do preço justo, e não do preço.** Duas alternativas
   foram medidas e recusadas: a de convergência parcial, `log(W/P₀) = a +
   b·log(V/P₀)` com os quantis do resíduo, e a do preço sozinho. São dez vezes
   mais estreitas e **não calibram em 36 meses** — 78,4% e 78,8% para 90% —,
   porque o choque comum a uma coorte inteira não se estima com duas coortes de
   calibragem. A faixa em torno do justo calibra porque a largura dela é dominada
   pela dispersão do próprio preço justo contra o preço, que é estável entre
   coortes.

4. **Provento entra aqui como dado conferido, e só aqui além da decisão 89.** A
   faixa é medida sobre o retorno total das coortes e apresentada como tal. A
   simulação da carteira, a cascata e o retorno esperado continuam de preço.

## Consequências aceitas

**A faixa é larga, e é isso que ela diz.** Em 12 meses, oito em cada dez
avaliações terminaram entre 0,62 e 9,2 vezes o preço justo; nove em cada dez,
entre 0,43 e 17. É o tamanho do erro do preço justo contra o que aconteceu, e é
coerente com a §0: o potencial não ordena além do book-to-market, e o preço
converge ao valor justo **um quarto do caminho em 36 meses** — `b = 0,24` na
regressão acima, onde a decisão 26 supunha `b = 1`.

**A calibração é marginal, não condicional.** No terço de maior potencial a
faixa de 90% cobre 84,5% em 12 meses e 80,9% em 36; no terço do meio, 100% e
97,5%. Ela sabe o quanto o motor erra em média, e não em qual ativo erra mais.

**Os 36 meses têm duas coortes de teste.** A cobertura agregada está dentro do
critério; por coorte ela oscila mais — em 12 meses, a de 50% cobre de 44,4% em
2019 a 67,9% em 2023.

**É a amostra dos sobreviventes.** Quem quebrou entre a coorte e o resgate não
está nela, e a borda de baixo da faixa está alta na medida desse viés. A
cobertura precisa ser remedida com as deslistadas (C2b) antes de a condição R2
ser dada por atingida.

**A faixa vale para a montagem padrão.** Ela foi medida sem a contagem oficial
da B3, que é de hoje e não existe nas coortes, e com as premissas padrão; mudar
horizonte ou prêmio de risco na configuração muda o preço justo sem mudar a
faixa medida.

Ver [cobertura_banda.md](../validacao/cobertura_banda.md).
