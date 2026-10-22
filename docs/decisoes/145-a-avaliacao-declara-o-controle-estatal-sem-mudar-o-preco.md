---
numero: 145
titulo: A avaliação declara o controle estatal, com a fonte do Formulário Cadastral, sem mudar o preço justo
status: aceita
origem: voce
data: 2026-10-02
citacao: >
  Maravilha. Pode fazer as 4 medições e fazer o download.
afeta:
  - packages/equisim_core/lib/src/services/cvm/shareholder_control.dart
  - packages/equisim_core/lib/src/entities/valuation.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - lib/data/repositories/shareholder_control_repository.dart
  - lib/di/providers.dart
  - lib/presentation/valuation/valuation_providers.dart
  - lib/presentation/shared/domain_copy.dart
  - tool/controle_empacotar.dart
  - tool/validation/congelado.dart
  - tool/gabarito_cascata.dart
  - tool/backtest_valuation.dart
  - assets/cvm/controle.json
  - docs/validacao/estatais.md
substitui: []
---

## Contexto

O usuário perguntou, em 02/10/2026, se a taxa de desconto das estatais não
deveria ser maior que a das outras companhias, e se havia teoria que
sustentasse o ajuste (item B46, apontamento de 02/10). O parecer propôs quatro
passos, e o usuário autorizou os quatro e o download do prêmio-país: conferir
o beta das estatais contra o encolhimento ao setor, medir o lambda de Damodaran
pela sensibilidade ao risco soberano, simular o efeito de um prêmio a mais no
preço e no backtest, e declarar o controle estatal na avaliação.

A medição ([estatais.md](../validacao/estatais.md)) achou que o motor dá às
estatais potencial muito acima do das privadas, hoje e em todas as coortes, e
dentro do mesmo setor — mas que o risco do controlador público não aparece onde
o CAPM o cobraria: o beta das estatais é **menor** que o das privadas, o
encolhimento ao setor quase não o mexe, e a exposição delas ao risco soberano,
além do que o Ibovespa explica, não é maior.

## Decisão

**A avaliação de uma companhia de controle estatal leva a ressalva
`controleEstatal` e um aviso que diz o que foi medido. O preço justo não muda.**

1. **A espécie de controle vem do Formulário Cadastral da CVM**
   (`Especie_Controle_Acionario`), que é fonte primária e anual. O histórico de
   cada companhia sai de `ShareholderControlHistory.fromFilings`, com a data da
   privatização tirada da coluna `Data_Especie_Controle_Acionario` quando ela é
   plausível — Eletrobras em 17/06/2022, Copel em 11/08/2023, Sabesp em
   22/07/2024 —, e chega ao aplicativo pelo pacote `assets/cvm/controle.json`,
   gerado por `tool/controle_empacotar.dart`, pela raiz do código de
   negociação.
2. **"Estatal Holding" é estatal**, como a Petrobras declara. A espécie vale
   na data da avaliação; no backtest, na data de cada coorte.
3. **O aviso diz o porquê de não cobrar.** O risco do controlador público —
   preço, tarifa, crédito e indicação decididos por outros objetivos que o
   lucro — está no fluxo que o minoritário pode esperar receber, e não no beta
   nem na exposição ao risco soberano. É a posição da teoria de agência
   (Jensen e Meckling, 1976; Shleifer e Vishny, 1994) e da prática de não somar
   à taxa um prêmio de risco específico que a medição não sustenta (Damodaran).
4. **A montagem do aplicativo nas ferramentas leva a mesma ressalva** — a
   entrada congelada, o gabarito e o backtest —, para que o gabarito continue
   sendo o espelho do aplicativo.

**Cobrar das estatais um prêmio a mais no custo do capital próprio não está
decidido aqui.** A medição do efeito está no item B46 e em
[estatais.md](../validacao/estatais.md); a escolha é do usuário e do
orientador.

## Consequências aceitas

- **A ressalva informa e não corrige.** O potencial das estatais continua
  acima do das privadas, e quem lê a tela passa a saber que o motor não cobra o
  risco do controle — e por quê.
- **O backtest grava a ressalva no campo `ressalvas`** desde a execução de
  02/10/2026, refeita pelo item B47; a ressalva não muda preço nem ordem.
- **O pacote envelhece como os outros da entrada congelada**: a privatização
  que acontecer depois dele só aparece quando ele for regerado.
