---
numero: 93
titulo: As deslistadas entram nas coortes com a montagem do aplicativo por data, e o t da habilidade é o menor entre o comum e o de Newey-West
status: aceita
origem: voce
data: 2026-09-15
citacao: >
  autorizo o prosseguimento da implantação da Fase 2, com os itens C2b, C0b,
  C1a e C1b.
afeta:
  - tool/backtest_valuation.dart
  - tool/coortes/deslistadas.dart
  - tool/cvm/setor_cvm.dart
  - tool/cvm/documentos.dart
  - tool/cvm/outorgas_por_data.dart
  - tool/cvm_baixar.py
  - tool/b3/proventos.dart
  - tool/b3_complemento_baixar.py
  - tool/regressao_condicional.dart
  - tool/validation/regression.dart
  - test/tool/regression_test.dart
  - docs/validacao/backtest_aplicativo_deslistadas.json
  - docs/validacao/habilidade_aplicativo.md
  - docs/validacao/habilidade_aplicativo.json
substitui: []
---

## Contexto

Os itens C1a e C1b do plano. O teste de habilidade — o `t` do potencial
condicionado ao book-to-market em 36 meses, que o R3 exige acima de 2 — tinha
dois defeitos declarados desde a §0: o erro-padrão supunha coortes independentes,
e as janelas de 36 meses de coortes vizinhas se sobrepõem em dois anos; e a
amostra era o universo listado hoje, com o viés de sobrevivência nos dois lados.

O A3.4 deixou as deslistadas prontas — contagem de ações por data, eventos
localizados no preço, eventos não localizados, proventos —, e a rodada do C2 deixou
a montagem do aplicativo por data em `tool/backtest_valuation.dart`.

## Decisão

1. **As deslistadas da ponte entram nas coortes** (`--com-deslistadas`), cada uma
   com o que existia na data da coorte:
   - **a CVM pelo CNPJ**, com os documentos recebidos até ali, mesclada a
     exercícios de mercado sintéticos — a contagem do FRE no fim do exercício, a
     contagem vigente na data e o valor de mercado dela ao fechamento do dia. A
     decisão 70 continua valendo: nenhuma contagem vem da CVM;
   - **o fechamento do COTAHIST filtrado pelo ISIN do papel**, ajustado só pelos
     eventos com data ex até a data; o volume financeiro alimenta a Porta 0;
   - **os proventos da classe**, pelo nome de pregão, no beta e no retorno total;
   - **o prazo das outorgas** do Formulário de Referência recebido até ali;
   - **o setor da B3**, que o portal devolve para 62 dos 231 papéis, e, para os
     outros, a classificação da B3 que representa o setor de atividade da FCA
     (`tool/cvm/setor_cvm.dart`): para cada setor da CVM, a combinação das três
     portas da maioria das listadas que têm os dois cadastros. Conferida nas
     próprias listadas **sem a companhia**, acerta a Porta 1 em 281 de 284, a
     precedência do ciclo em 264 e o prazo determinado em 281; as três juntas, em
     258.
2. **Fica fora a janela que atravessa evento suspeito**: evento declarado e não
   localizado no preço, como o C1b pedia, e também **salto de mais de três vezes
   entre pregões a até 90 dias** na série já ajustada — o grupamento de 2024 da
   KRSA3 e da NGRD3, que o FRE não declarou, e a TOYB3 dividida por 270 mil em
   2015. Na janela de cinco anos do beta, a observação sai; no horizonte do
   retorno, o retorno daquele horizonte fica vazio. Das 492 observações de
   deslistadas que negociavam na data, 48 saíram.
3. **O papel que deixa de negociar leva o último preço até o fim do horizonte**,
   sem remuneração depois, e os proventos até a última data ex. Aquisição e oferta
   de fechamento de capital encerram no preço da oferta; quebra encerra no último
   negócio, que não é zero.
4. **O `t` do segundo passo de Fama-MacBeth sai também com Newey-West**
   (`Regression.neweyWestMean`), com núcleo de Bartlett e defasagem igual à
   sobreposição das janelas — `h/12 − 1`, duas coortes em 36 meses e nenhuma em
   12. Com o fator `k/(k−1)`, defasagem zero devolve exatamente o `t` comum.
5. **Para o critério do R3 vale o menor dos dois.** Com cinco coortes, a
   autocovariância estimada é ruído: a dos coeficientes do potencial dado o P/B
   saiu **negativa** — −0,13 sem as deslistadas, −0,19 com elas —, e aí o
   Newey-West **estreita** o erro que a sobreposição deveria alargar, levando o
   `t` de 1,24 a 1,81. O menor dos dois fica até as coortes trimestrais (C1c)
   darem série longa o bastante para a autocovariância significar alguma coisa.
6. **Toda comparação com e sem as deslistadas sai da mesma execução**: entre esta
   e a da rodada anterior, 40 das 2.633 linhas das listadas mudaram por deriva do
   cache.

## Consequências aceitas

**O resultado, no retorno total** (ver
[habilidade_aplicativo.md](../validacao/habilidade_aplicativo.md)):

| 36 meses | sem deslistadas | com deslistadas |
|---|---:|---:|
| observações | 503 | 591 |
| coef. do potencial dado o P/B | 0,068 | 0,070 |
| `t` comum | 1,04 | 1,24 |
| `t` de Newey-West | 1,49 | 1,81 |
| **`t` para o R3** | **1,04** | **1,24** |

**O R3 continua reprovado, agora sobre o motor de hoje e sem o viés que dava para
tirar.** Em 12 meses o coeficiente é de 0,037 com as deslistadas, `t` 0,57.

**A amostra de deslistadas é pequena.** Das 164 companhias da ponte, 86 têm
observação e 25 chegam a ser avaliadas, em 106 observações — as outras caem na
Porta 0, quase todas por liquidez. As 126 companhias com ação em bolsa e sem ponte
continuam fora.

**O setor da CVM erra a porta em 9% das listadas.** O erro mais comum é de ciclo:
siderúrgica classificada como metalurgia de material de transporte, e o contrário.
Numa deslistada sem classificação da B3, a precedência do ciclo pode estar trocada.

**A escolha do menor `t` é conservadora de propósito**: um critério de aprovação
não pode ser atingido por ruído na estimativa do próprio erro-padrão.
