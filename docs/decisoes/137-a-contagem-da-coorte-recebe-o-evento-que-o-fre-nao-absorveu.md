---
numero: 137
titulo: A contagem por data da coorte recebe o evento de ações que o FRE ainda não absorveu
status: aceita
origem: voce
data: 2026-09-24
citacao: >
  Ao executar mudanças no código, realize a execução das lentes e correção dos
  problemas apontados por elas.
afeta:
  - tool/coortes/eventos_de_acoes.dart
  - tool/backtest_valuation.dart
  - test/tool/capital_fre_test.dart
substitui: []
---

## Contexto

Achado ao medir o B28 (decisão 135). A coorte forma a contagem de ações e o
valor de mercado pela contagem do Formulário de Referência na data (decisão 97).
**O quadro de eventos do FRE parou em 2022**, e daí em diante a contagem só muda
quando a companhia corrige o formulário — o que levou mais de um ano no Banco do
Brasil. O desdobramento de 2 para 1 de 16/04/2024 não estava na contagem de
30/06/2024, 30/09/2024, 31/12/2024 e 31/03/2025: **a coorte dividia pela
contagem de antes do evento com o preço de depois**. O valor de mercado saía pela
metade, R$ 76,5 bilhões contra R$ 153 bilhões, e o potencial pulava de −6% para
+100% nas três coortes de 2024.

## Decisão

**A contagem da data recebe o evento de ações que ela não absorveu**, dos mesmos
eventos da decisão 136, quando tudo isto vale:

- **a contagem está parada**: nenhuma mudança, por fator nenhum, de 400 dias
  antes do evento até a data da coorte. A aprovação costuma vir antes da data
  ex, e às vezes junto com outra operação — a AERI3 registrou o grupamento de
  20 para 1 antes da data ex e junto com uma emissão, com razão de 0,081, e
  aplicar o evento de novo tirava 95% do valor de mercado. **Se a contagem
  mexeu, o formulário tratou o evento**, e ela fica como veio;
- **a contagem cobre a data do evento**: o registro da B3 guarda eventos de
  1989, que já estão na primeira contagem;
- **o evento é recente**: de 2011 em diante e a até três anos da data da coorte,
  que cobrem com folga o atraso de correção medido;
- **o fator é de pelo menos 2%**, como na decisão 136.

## O que foi medido

**41 observações de 10 papéis** recebem o evento:

| papel | evento | coortes | efeito |
|---|---|---|---|
| BBAS3 | desdobramento 2:1, 16/04/2024 | 30/06/2024 a 31/03/2025 | valor de mercado dobra; potencial de +101% a +0,5% em 30/06/2024 |
| FESA3, FESA4 | desdobramento 4:1, 24/01/2024 | 2024 | valor de mercado ×4 |
| DIRR3 | desdobramento 3:1, 11/08/2025 | 30/09/2025 | valor de mercado ×3; potencial de −67% a −89% |
| ESTR4 | desdobramento 10:1, 01/06/2023 | 2023 e 2024 | valor de mercado ×10 |
| BHIA3 | grupamento 25:1, 15/12/2023 | 31/12/2023 | valor de mercado ÷25 |
| RCSL3, RCSL4 | grupamento 4:1, 31/05/2024 | 2024 | valor de mercado ÷4 |
| MATD3, SNSY5 | desdobramentos de 2021 e 2020 | | |

**No Banco do Brasil, o potencial de +100% nas coortes de 2024 era só a contagem
velha.** O efeito no R3, junto com as decisões 135 e 136, está na 135.

## Consequências aceitas

**Só vale nas coortes.** O aplicativo divide pela contagem oficial da B3, que é
atualizada pela própria bolsa e não tem o atraso do formulário.
