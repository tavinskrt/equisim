# A habilidade do motor de agora, com as deslistadas — itens C1a e C1b

> **Medido com o preço da coorte na base de ações de hoje, e com o `t` da
> decisão 93.** Os dois foram corrigidos à tarde — o preço pela
> [decisão 97](../decisoes/097-a-coorte-forma-preco-contagem-e-valor-de-mercado-na-base-da-data.md),
> o `t` pela [96](../decisoes/096-o-t-da-habilidade-e-corrigido-pela-sobreposicao-contra-o-critico-dela.md).
> A leitura com o instrumento pronto está em
> [habilidade_trimestral.md](habilidade_trimestral.md).

Medido em 15/09/2026 por `dart run tool/regressao_condicional.dart --aplicativo`,
sobre `docs/validacao/backtest_aplicativo_deslistadas.json` (de
`dart run tool/backtest_valuation.dart --montagem aplicativo --com-deslistadas`).
Dados em [habilidade_aplicativo.json](habilidade_aplicativo.json). Decisão:
[93](../decisoes/093-as-deslistadas-entram-nas-coortes-e-o-t-e-o-menor.md).

## 1. O que mudou desde a §0 do plano

A §0 mediu, em 11/09/2026, o motor daquele dia sobre a fonte de mercado, no
retorno de preço, com o `t` que supõe coortes independentes e o universo listado
hoje. Esta medição muda as quatro coisas:

- **o motor é o do aplicativo na data de cada coorte** — curva do Tesouro, CVM
  recebida até ali, setor da B3, prazo das outorgas, beta de retorno total;
- **o retorno é o total**, com os proventos da B3 reinvestidos na data ex;
- **o `t` sai também com Newey-West**, e vale o menor dos dois (§3);
- **as deslistadas entram** (§2), na mesma execução das listadas.

Continua a regressão da §0: Fama-MacBeth em postos padronizados, por coorte, e o
segundo passo sobre as médias.

## 2. As deslistadas

Das 164 companhias da ponte do A3.2, 231 papéis têm contagem por data, pregões e
documentos da CVM. Em cada coorte entra o papel que negociava na data:

| coorte | negociando | fora por evento suspeito | observações | avaliadas |
|---|---:|---:|---:|---:|
| 2018 | 83 | 9 | 74 | 19 |
| 2019 | 80 | 10 | 70 | 22 |
| 2020 | 83 | 8 | 75 | 22 |
| 2021 | 79 | 7 | 72 | 17 |
| 2022 | 70 | 5 | 65 | 11 |
| 2023 | 51 | 5 | 46 | 8 |
| 2024 | 25 | 1 | 24 | 3 |
| 2025 | 21 | 3 | 18 | 4 |
| **total** | **492** | **48** | **444** | **106** |

**Evento suspeito** é evento declarado no FRE e não localizado no preço, ou salto
de mais de três vezes entre pregões a até 90 dias na série ajustada — o
grupamento de 2024 da KRSA3 e da NGRD3, que o FRE não declarou. Na janela de
cinco anos do beta, a observação sai; no horizonte do retorno, o retorno daquele
horizonte fica vazio.

As 444 observações são de 86 companhias; as 106 avaliadas, de 25. Das 338
recusadas, 217 caem só por liquidez. **O setor** é o da B3 em 148 observações e o
representante do setor da CVM em 295 (`tool/cvm/setor_cvm.dart`), que acerta as
três portas em 258 de 284 listadas conferidas sem a própria companhia.

**Na mesma execução, 40 das 2.633 linhas das listadas mudaram** em relação à
execução da rodada anterior, por deriva do cache. Toda comparação abaixo usa só
esta execução.

## 3. O erro-padrão das janelas sobrepostas (C1a)

Coortes anuais medidas em 36 meses se sobrepõem por dois anos, e o coeficiente
de uma carrega o choque das vizinhas. O `t` de Newey-West soma as
autocovariâncias dos coeficientes até a defasagem de duas coortes, com núcleo de
Bartlett; em 12 meses não há sobreposição, e a defasagem é zero.

**Com cinco coortes, a correção pode ir para o lado errado.** A autocorrelação de
primeira ordem dos coeficientes do potencial dado o P/B saiu de −0,13 sem as
deslistadas e −0,19 com elas; autocovariância negativa **estreita** o erro, e o
`t` de Newey-West subiu em vez de descer. Sobreposição de janela produz
autocorrelação positiva, e a negativa aqui é ruído de cinco pontos. Por isso vale
o **menor** dos dois `t` para o critério, até as coortes trimestrais (C1c).

A leitura por coortes que não se sobrepõem confirma que não há o que salvar: a
média do coeficiente dado o P/B nas coortes de 2018 e 2021 é de +0,06, e nas de
2019 e 2022, de −0,04; a de 2020 sozinha é de +0,30, e é ela que puxa a média.

## 4. O resultado

**36 meses**

| | sem deslistadas | com deslistadas |
|---|---:|---:|
| observações | 503 | 591 |
| IC do potencial | 0,186 (`t` 3,47) | 0,183 (`t` 3,75) |
| IC do P/B | 0,251 (`t` 5,89) | 0,247 (`t` 7,50) |
| **coef. do potencial dado o P/B** | **0,068** | **0,070** |
| `t` comum / Newey-West | 1,04 / 1,49 | 1,24 / 1,81 |
| **`t` para o R3** | **1,04** | **1,24** |
| coef. dado o P/B e o L/P | 0,057 (`t` 0,59) | 0,048 (`t` 0,45) |
| IC incremental | 0,053 (`t` 1,10) | 0,046 (`t` 0,87) |
| coortes com coeficiente positivo | 4 de 5 | 4 de 5 |

**12 meses**

| | sem deslistadas | com deslistadas |
|---|---:|---:|
| observações | 722 | 823 |
| IC do potencial | 0,105 (`t` 1,54) | 0,095 (`t` 1,53) |
| IC do P/B | 0,135 (`t` 3,23) | 0,138 (`t` 2,82) |
| **coef. do potencial dado o P/B** | **0,050** (`t` 0,64) | **0,037** (`t` 0,57) |
| coortes com coeficiente positivo | 4 de 7 | 3 de 7 |

**O R3 continua reprovado.** O potencial ordena sozinho — IC de 0,18 em 36 meses —,
e ordena menos que o P/B; condicionado a ele, o que sobra tem `t` de 1,24 com as
deslistadas. O retorno total, a montagem do aplicativo e as deslistadas não
mudam a conclusão da §0.

## 5. O que isto não diz

- **As deslistadas são poucas**: 88 observações a mais em 36 meses. O viés que
  elas tiram é o das companhias da ponte; as 126 com ação em bolsa e sem ponte
  seguem fora.
- **O setor da CVM erra a porta em 9% das listadas**, e numa deslistada sem
  classificação da B3 a precedência do ciclo pode estar trocada.
- **O papel que sai da bolsa leva o último preço** até o fim do horizonte. O
  motivo da saída — aquisição, oferta, quebra — não foi levantado.
- **Cinco coortes de 36 meses** continuam sendo cinco pontos. O C1c é o que dá
  série para o erro-padrão.
