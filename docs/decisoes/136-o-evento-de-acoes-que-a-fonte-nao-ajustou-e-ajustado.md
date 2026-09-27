---
numero: 136
titulo: O evento de ações que a fonte de preços não ajustou é ajustado — na série do beta e da faixa, e no retorno das coortes
status: aceita
origem: voce
data: 2026-09-24
citacao: >
  Ao executar mudanças no código, realize a execução das lentes e correção dos
  problemas apontados por elas.
afeta:
  - packages/equisim_core/lib/src/services/b3/corporate_events.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - packages/equisim_core/lib/src/entities/price_series.dart
  - packages/equisim_core/test/corporate_events_complete_test.dart
  - tool/coortes/eventos_de_acoes.dart
  - tool/capital_empacotar.dart
  - tool/backtest_valuation.dart
  - test/tool/capital_fre_test.dart
  - assets/cvm/capital.json
substitui: []
---

## Contexto

Achado ao medir o B28 (decisão 135). Para separar emissão de bonificação, comparei
o fechamento bruto do COTAHIST com o `close` da fonte de mercado em volta de cada
mudança de contagem do FRE. **A fonte ajusta desdobramento e grupamento, e não
toda bonificação.** No dia ex de uma bonificação que ela ajustou, a razão entre o
bruto e o dela salta pelo fator; na que ela não ajustou, a razão fica parada e
os dois caem juntos. Das mudanças de contagem com salto no bruto, a fonte ajustou
67 e deixou 133 como vieram: as bonificações anuais do Bradesco de 2018 a 2022,
a de 100% da SLC em 2019, as da Renner, da Itaúsa, da Klabin em 2024, da Marcopolo
em 2024.

**Numa série assim, o dia ex é uma queda que não aconteceu**, de `1 − 1/fator`:
9% numa bonificação de 10%, 50% numa de 100%. Ela entrava em três lugares:

- **no retorno das coortes**, que é a variável de desfecho do R2 e do R3 — o
  retorno de preço é a razão entre dois fechamentos da fonte, e toda janela que
  atravessava uma bonificação não ajustada perdia o fator. Uma janela de 36
  meses do Bradesco atravessava três;
- **no beta e na volatilidade da faixa**, nas coortes e no aplicativo, que leem
  a mesma série;
- **no corte de liquidez**, pelo volume, que a fonte também não ajustava.

## Decisão

1. **Os eventos de ações de cada ativo saem de quatro fontes**: o quadro de
   eventos do FRE, localizado no preço bruto; o registro da B3; o `DISMES` do
   COTAHIST para fator grande; e a mudança de contagem do FRE que o preço
   confirma — troca de `DISMES` com o salto do fator. **O preço confirma, e não
   o primeiro salto parecido**: a AMER3 caiu 38% em 16/01/2023, na semana da
   fraude, e isso casava com uma mudança de contagem de 1,62.
2. **No backtest, que tem o COTAHIST, a resposta é exata**: o evento ficou sem
   ajuste quando, no dia dele, o fator entre o bruto e a fonte não salta, o
   bruto cai pelo fator e o `DISMES` troca. A série da fonte é corrigida uma vez
   por ativo, antes de qualquer coorte, e o retorno, a base da data, o beta e a
   volatilidade leem a corrigida.
3. **No aplicativo, que não tem o bruto, decide o salto da série**: o evento é
   completado quando o salto do dia ex está mais perto de `1/fator` que de 1 e a
   até 3% dele — 6% em desdobramento —, e com fator de pelo menos 3%. Abaixo
   disso, um provento de banco passaria por bonificação. A avaliação diz o que
   ajustou.

## O que foi medido

**Nas coortes, a série de 57 papéis foi completada.** O retorno de 12 meses muda
em 278 das 1.575 observações que o têm, com mediana de +8,5% entre as que mudam,
e o de 36 meses em 509 de 1.127, com mediana de +9,3%. Os maiores são os das
bonificações grandes: SHUL4 de 2018 e 2020 (+97% em 12 meses, +263% em 36), SLCE3
de 2018 e 2019, MDNE3 de 2023 e 2025, ROMI3 de 2020. **O retorno perdido estava
concentrado em quem bonifica**, e quem bonifica é quem retém lucro: o defeito não
era ruído, era viés contra um grupo.

**O beta e a volatilidade mudam junto**: o custo de capital próprio muda em
1.614 observações, e no máximo 41 delas são da decisão 137, que mexe no valor de
mercado e com ele na alavancagem.

**No aplicativo, dez ativos têm evento completado** na série de hoje — ABCB4,
ALUP11, FRAS3, GGBR4, ITSA4, LEVE3, LREN3, MDNE3, POMO4 e SLCE3 —, e a avaliação
diz, em aviso, o que foi ajustado. O preço justo muda em oito deles, de −0,6%
(ITSA4) a +0,8% (MDNE3), pelo beta.

O efeito no R2 e no R3, junto com as decisões 135 e 137, está na 135.

## Consequências aceitas

**No aplicativo, a regra do salto erra dos dois lados, e pouco.** Uma bonificação
não ajustada com o mercado andando mais de 3% no dia fica como veio; uma
bonificação já ajustada com um pregão de mais de 6% de queda no dia ex seria
ajustada de novo. As duas são raras, e o pacote é regerado a cada build.

**Fator abaixo de 2% fica de fora nas duas pontas.** O efeito dele na série é
desse tamanho, e o salto não se separa de um pregão comum.
