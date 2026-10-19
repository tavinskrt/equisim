---
numero: 149
titulo: Toda a suíte de testes mora em test/, separada pelo que testa
status: aceita
origem: voce
data: 2026-10-19
citacao: >
  Consegue agora mover toda a suíte de testes para uma pasta separada no
  diretório? Como tests/ aí você vai separando o que é do núcleo, o que é da
  ui, e etc? Apenas para uma melhor organização para que quando formos analisar
  fique mais encontrável o que é código e o que não é
afeta:
  - test/README.md
  - test/core/
  - test/data/
  - test/ui/
  - test/tool/
  - pubspec.yaml
  - packages/equisim_core/pubspec.yaml
  - tool/setup.sh
  - tool/setup.ps1
  - scripts/gerar-estado.mjs
  - scripts/qa/advisor/lentes.ts
substitui: []
retira:
  - packages/equisim_core/test/audit_integrity_test.dart
  - packages/equisim_core/test/audit_test.dart
  - packages/equisim_core/test/b3_registry_test.dart
  - packages/equisim_core/test/base_de_patrimonio_test.dart
  - packages/equisim_core/test/beta_shrinkage_test.dart
  - packages/equisim_core/test/beta_total_return_test.dart
  - packages/equisim_core/test/brazilian_calendar_test.dart
  - packages/equisim_core/test/calibrated_band_test.dart
  - packages/equisim_core/test/capital_posterior_test.dart
  - packages/equisim_core/test/cash_dividends_test.dart
  - packages/equisim_core/test/concession_horizon_test.dart
  - packages/equisim_core/test/corporate_events_complete_test.dart
  - packages/equisim_core/test/corporate_events_test.dart
  - packages/equisim_core/test/cvm_bridge_test.dart
  - packages/equisim_core/test/cvm_chart_test.dart
  - packages/equisim_core/test/cvm_series_test.dart
  - packages/equisim_core/test/equity_from_firm_test.dart
  - packages/equisim_core/test/financial_sectors_test.dart
  - packages/equisim_core/test/fre_concessions_test.dart
  - packages/equisim_core/test/fundamentals_merge_test.dart
  - packages/equisim_core/test/levered_rates_test.dart
  - packages/equisim_core/test/market_anchors_test.dart
  - packages/equisim_core/test/peer_multiples_test.dart
  - packages/equisim_core/test/portfolio_test.dart
  - packages/equisim_core/test/real_nominal_test.dart
  - packages/equisim_core/test/result_and_rates_test.dart
  - packages/equisim_core/test/share_count_history_test.dart
  - packages/equisim_core/test/trailing_twelve_months_test.dart
  - packages/equisim_core/test/usecases_test.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - packages/equisim_core/test/valuation_inputs_copy_test.dart
  - packages/equisim_core/test/valuation_test.dart
  - packages/equisim_core/test/yield_curve_test.dart
  - test/presentation
  - test/presentation/calibrated_band_card_test.dart
  - test/presentation/domain_copy_test.dart
  - test/presentation/failure_copy_test.dart
  - test/presentation/logs_page_test.dart
---

## Contexto

Os testes moravam em dois lugares: os do núcleo em
`packages/equisim_core/test/`, dentro do pacote, e os do aplicativo em `test/`,
com as telas em `test/presentation/` e, na raiz, o `widget_test.dart` que o
`flutter create` gera e que só afirma que `true` é verdadeiro. Quem abria o
repositório para analisar não tinha um lugar só onde estivesse tudo o que é
teste, e o nome `presentation` não dizia de imediato que ali eram as telas.
Em 19/10/2026 o usuário pediu a suíte inteira numa pasta só, separada entre o
que é do núcleo, o que é da interface e o resto.

## Decisão

**Toda a suíte mora em `test/`, na raiz, uma subpasta por camada de código:
`core/` (o núcleo), `data/` (fontes, cache, repositórios e pacotes de dados),
`ui/` (telas, componentes e controladores) e `tool/` (os scripts de medição).
`fixtures/` e `qa_fixtures/` seguem como estão: são dados, e não teste.**

1. **`packages/equisim_core/test/` vira `test/core/`**, arquivo por arquivo, com
   o mesmo nome; **`test/presentation/` vira `test/ui/`**. `test/data/` e
   `test/tool/` não mudam de lugar. O `widget_test.dart` sai: não testava nada.
2. **A pasta é `test/`, e não `tests/`.** É o nome que o Dart define para os
   testes de um pacote e o único que o `flutter test` varre sem argumentos — o
   comando procura `test/` e aborta se não a achar. `qa_fixtures/` já registrava
   o mesmo motivo: um `tests/` ao lado de `test/`, com uma letra de diferença,
   seria armadilha permanente.
3. **Os testes do núcleo rodam a partir da raiz.** Um `flutter test` roda a
   suíte inteira. Eles continuam sem nada do Flutter — importam o `test` do
   Dart, que passa a ser dependência de desenvolvimento declarada do aplicativo
   (já estava resolvido no `pubspec.lock`, na mesma versão, como transitivo) —,
   e por isso `dart test test/core` os roda na VM pura. O núcleo perde as
   dependências de desenvolvimento `test` e `coverage`, que só serviam à suíte.
4. **O teste de pureza lê o núcleo pelo caminho explícito**
   (`packages/equisim_core/lib`, `packages/equisim_core/pubspec.yaml`) e confere
   primeiro que o pubspec lido é o do `equisim_core`. Dentro do pacote ele lia
   `lib/` e `pubspec.yaml` relativos à pasta de onde rodava; da raiz, esses
   nomes seriam os do aplicativo, e a guarda passaria a vigiar o pacote errado.

**Os caminhos em `retira` não foram apagados: foram movidos**, pela regra do
item 1. São os testes que decisões anteriores listam em `afeta`; sem esta
lista, o estado os mostraria como referência quebrada. Cada decisão antiga
continua valendo, e o teste que ela cita está no endereço novo:
`packages/equisim_core/test/X` em `test/core/X`, `test/presentation/X` em
`test/ui/X`.

## Consequências aceitas

- **O núcleo deixa de ser autossuficiente em teste.** Quem copiar só
  `packages/equisim_core/` leva o motor sem a suíte dele. É o custo de ter os
  testes num lugar só; o pacote nunca foi publicado (`publish_to: 'none'`).
- **As regras de análise do aplicativo valem agora para os testes do núcleo**,
  e são mais estritas que as do pacote: nove alertas
  (`prefer_const_declarations`, `unnecessary_lambdas`) foram corrigidos no
  código, sem supressão.
- **O `flutter test` fica mais longo**, cerca de dois minutos, por somar os
  testes do núcleo; para só o núcleo, `dart test test/core` leva segundos.
- **As decisões antigas e o registro histórico citam os endereços velhos** no
  corpo do texto. Não se editam; o `retira` e esta decisão são o mapa.
