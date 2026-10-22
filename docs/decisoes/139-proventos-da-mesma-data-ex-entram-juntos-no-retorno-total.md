---
numero: 139
titulo: Os proventos da mesma data ex entram juntos no fator de retorno total
status: aceita
origem: voce
data: 2026-09-25
citacao: >
  Ao executar mudanças no código, realize a execução das lentes e correção dos
  problemas apontados por elas.
afeta:
  - packages/equisim_core/lib/src/services/b3/cash_dividends.dart
  - packages/equisim_core/test/cash_dividends_test.dart
substitui: []
---

## Contexto

A lente `nucleo` apontou, em 25/09/2026, que `TotalReturn.factor` — o fator de
reinvestimento dos proventos no retorno total das coortes, que é a variável de
desfecho do R2 e do R3 e o que a faixa calibrada mede (decisões 89 e 92) —
tratava cada provento como um dia à parte.

O retorno do dia ex é `(P_ex + D_1 + D_2)/P_com`, e o fator de reinvestimento é
`1 + (D_1 + D_2)/P_ex`. **A conta multiplicava `(1 + D_1/P_ex)(1 + D_2/P_ex)`**,
e inventava o termo cruzado `D_1·D_2/P_ex²`: um provento rendendo sobre o outro
no mesmo dia. Dividendo e juro sobre capital próprio saem juntos com frequência.
O termo é pequeno — um centésimo de ponto percentual para dois proventos de 1% —,
e é defeito: o R1 promete nenhum defeito conhecido, e não nenhum defeito grande.

O índice de retorno total do beta (`TotalReturnIndex.build`) já somava os
rendimentos do dia, e não tinha o defeito.

## Decisão

**Os proventos com a mesma data ex entram juntos**: os rendimentos sobre o preço
ex somam, e o fator do dia é um só. Sem o pregão ex, o preço ex sai do preço com
direito menos **todos** os proventos do dia — `D/P_ex = (D/P_com) / (1 − ΣD/P_com)`
—, e não menos cada um separadamente. O imposto do juro sobre capital próprio
continua saindo do que se recebe, e não da queda do preço. As contagens de
aplicados, aproximados e sem preço continuam por provento.

## O que foi medido

**Maior do que a conta de segunda ordem sugeria, porque o termo compõe.** No
backtest refeito, o retorno total de 36 meses muda em 2.189 das 7.537
observações que o têm, de 164 papéis, com mediana de 0,07 p.p. em módulo; o de
12 meses, em 1.925 de 10.426, mediana de 0,03 p.p. **Quase todas caem** (2.143 e
1.891): era o termo cruzado saindo. As que sobem (46 e 34) são as de preço ex
aproximado, que agora desconta todos os proventos do dia do preço com direito,
e não um de cada vez.

**A cauda é da Petrobras.** De 2021 a 2023 ela pagou de três a seis proventos
por data ex, com rendimento de 10% a 20% no dia — em 12/08/2022, dois
dividendos e um juro somando R$ 6,73 sobre R$ 36,25 —, e o termo cruzado,
composto nas nove datas da janela, chegava a 3% do fator. **Numa janela de
retorno total de +360%, isso é 12 p.p.**: a PETR4 de 30/09/2020 vai de +359,6% a
+347,2% em 36 meses, e as coortes de 30/06/2020 a 31/03/2022 perdem de 8 a 12
p.p. A MDNE3 de 31/03/2023 perde 12,8.

**Nenhum veredito muda.** O termo grande está em poucos papéis, e a ordenação
dentro de cada coorte quase não sente: o critério do R3 vai de 0,0578 a 0,0580,
com `t` corrigido de 0,335 a 0,336; o IC do book-to-market, de 0,1600 a 0,1599. A
faixa calibrada cobre 87,6 / 79,5 / 50,9% em 12 meses e 88,1 / 80,0 / 53,0% em
36, contra 87,6 / 79,4 / 50,9% e 88,1 / 80,1 / 53,0% antes — e o pacote dela foi
regerado ([habilidade_trimestral.md](../validacao/habilidade_trimestral.md) §11).

## Consequências aceitas

**A faixa calibrada é remedida** pelo backtest refeito, e o pacote dela
(`assets/validacao/banda_calibrada.json`) é regerado com a leitura nova.
