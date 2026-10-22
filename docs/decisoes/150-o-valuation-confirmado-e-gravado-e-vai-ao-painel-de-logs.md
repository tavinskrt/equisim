---
numero: 150
titulo: O valuation confirmado é gravado com as premissas e o resultado, e vai ao painel de logs
status: aceita
origem: voce
data: 2026-10-22
citacao: >
  We need a feature where, once the user edits and confirms the valuation, the
  system saves both the input values used and the calculated outputs, such as
  the fair price and other results. However, this persisted data must not be
  restricted strictly to the valuation tab; it must also be reflected and
  logged in the logs panel.
afeta:
  - packages/equisim_core/lib/src/services/valuation/manual_valuation_record.dart
  - packages/equisim_core/lib/equisim_core.dart
  - lib/data/repositories/manual_valuation_repository.dart
  - lib/di/providers.dart
  - lib/presentation/valuation/saved_valuations.dart
  - lib/presentation/valuation/saved_valuations_card.dart
  - lib/presentation/valuation/manual_valuation_page.dart
  - lib/presentation/valuation/valuation_page.dart
  - lib/presentation/audit/logs_page.dart
  - lib/presentation/shell/app_shell.dart
  - firestore.rules
  - docs/motor/07-aplicativo.md
  - docs/AUDITORIA_DE_CALCULOS.md
  - test/core/manual_valuation_record_test.dart
  - test/ui/saved_valuations_test.dart
substitui: []
---

## Contexto

A tela "Editar valuation" (decisão 147) recalcula o preço enquanto se digita,
e nada do que ela mostrava sobrevivia a fechar a tela: quem refazia a conta do
motor com os próprios números perdia a conta ao voltar. Em 22/10/2026 o usuário
pediu que, ao confirmar o valuation editado, o sistema guarde os valores de
entrada e os resultados — o preço justo e o resto —, e que isso não fique
restrito à aba Valuation, mas também se reflita e se registre no painel de logs.

## Decisão

**Confirmar grava o retrato da conta, e o mesmo retrato vai ao painel de logs.**

1. **O registro é do núcleo** (`ManualValuationRecord`), em Dart puro: as
   premissas do usuário, as do motor de que elas partiram, o `ManualOutcome`
   inteiro que `ManualValuation.evaluate` devolveu — a ponte, os dez anos, o
   terminal, os avisos — e a decomposição contra o motor, com a data da
   avaliação, o preço de mercado e o preço do motor daquele dia. **Nada é
   refeito ao reler**: o registro guarda o que a conta deu, e relê-lo um ano
   depois dá os números daquele dia. O instante da confirmação entra por
   parâmetro, como toda data no núcleo.
2. **A gravação é no Firestore**, coleção `valuations`, com o dono no documento
   e a regra de segurança conferindo que é quem está autenticado — o mesmo
   desenho dos estudos (`portfolios`). O documento leva o identificador do
   registro, e regravar não duplica.
3. **O painel de logs recebe um evento de cálculo** em
   `/core/valuation/manual/<ATIVO>`: as premissas no payload de entrada, o
   resultado no de saída, e seis fórmulas com os números do registro. Ele é
   emitido na confirmação e **de novo ao carregar o histórico gravado**, que é
   o que faz o painel refletir o que está persistido, e não só o que aconteceu
   na sessão — o histórico do painel vive em memória. O identificador do
   evento é o do registro, e o barramento descarta identificador repetido. O
   painel ganha o filtro "Valuations confirmados".
4. **Na aba Valuation**, o cartão "Seus valuations salvos" mostra os do ativo,
   do mais recente ao mais antigo, com as premissas e o resultado de cada um, e
   deixa reabrir na edição ou apagar.

## Consequências aceitas

- **O valuation salvo não é validado**, como o cálculo do usuário não é
  (decisão 147): a faixa calibrada e a habilidade medida continuam sendo do
  preço do motor.
- **Reabrir aplica os números salvos à conta congelada de hoje**, que pode ter
  mudado com dados novos; o preço reaberto pode diferir do gravado, e o gravado
  é que vale como registro.
- **Sem a auditoria ligada não há painel**, e o valuation é gravado do mesmo
  jeito. Gravar no painel um registro que o armazenamento recusou, como se
  tivesse sido salvo, foi descartado: a recusa vai ao painel como falha, com o
  motivo.
- **A regra nova do Firestore precisa ser publicada** (`firebase deploy --only
  firestore:rules`); sem ela, a gravação é recusada por permissão e a tela diz
  isso.
- **Armazenamento local**, em vez do Firestore, foi descartado: o valuation é
  dado do usuário, como os estudos, e no navegador compartilhado ele se
  misturaria entre contas.
