---
numero: 152
titulo: O Equisim passa a TypeScript, e o Dart sai do repositório
status: aceita
origem: voce
data: 2026-10-22
citacao: >
  Apague o núcleo Dart e porte todos os scripts
afeta:
  - src/
  - src/core/
  - src/core/lang/
  - src/copy/verdict-copy.ts
  - public/assets/
  - test/
  - test/parity/
  - tool/
  - tool/README.md
  - tool/run.ts
  - tool/cascade-golden.ts
  - tool/c7-preregistered.ts
  - tool/c7/protocol.ts
  - tool/lib/sqlite-cache.ts
  - tool/setup.sh
  - tool/setup.ps1
  - scripts/qa-local.mjs
  - scripts/qa/rules.ts
  - scripts/qa/advisor/lentes.ts
  - scripts/capture-screens.ts
  - package.json
  - firebase.json
  - README.md
  - CLAUDE.md
  - docs/motor/
  - docs/estudo/
substitui: []
retira:
  - assets/b3/emissores.json
  - assets/b3/proventos.json
  - assets/cvm/LEIAME.txt
  - assets/cvm/capital.json
  - assets/cvm/controle.json
  - assets/cvm/documentos.json
  - assets/cvm/outorgas.json
  - assets/cvm/units.json
  - assets/mercado/beta_prior.json
  - assets/mercado/multiplos_setoriais.json
  - assets/mercado/premio_implicito.json
  - assets/tesouro/curva.json
  - assets/validacao/banda_calibrada.json
  - assets/validacao/habilidade.json
  - lib/audit
  - lib/audit/audit_bus.dart
  - lib/data
  - lib/data/config/api_config.dart
  - lib/data/datasources/local/cache_database.dart
  - lib/data/datasources/remote/bcb_datasource.dart
  - lib/data/datasources/remote/brapi_datasource.dart
  - lib/data/datasources/remote/tesouro_datasource.dart
  - lib/data/dtos/brapi_dtos.dart
  - lib/data/isolate/valuation_runner.dart
  - lib/data/network/api_client.dart
  - lib/data/repositories/b3_registry_repository.dart
  - lib/data/repositories/beta_prior_repository.dart
  - lib/data/repositories/calibrated_band_repository.dart
  - lib/data/repositories/capital_events_repository.dart
  - lib/data/repositories/cash_dividends_repository.dart
  - lib/data/repositories/concession_term_repository.dart
  - lib/data/repositories/cvm_fundamentals_repository.dart
  - lib/data/repositories/manual_valuation_repository.dart
  - lib/data/repositories/market_premium_repository.dart
  - lib/data/repositories/market_repositories.dart
  - lib/data/repositories/peer_multiples_repository.dart
  - lib/data/repositories/risk_free_curve_repository.dart
  - lib/data/repositories/shareholder_control_repository.dart
  - lib/data/repositories/skill_reading_repository.dart
  - lib/data/repositories/unit_composition_repository.dart
  - lib/di/providers.dart
  - lib/presentation/audit/logs_page.dart
  - lib/presentation/backtest
  - lib/presentation/backtest/backtest_page.dart
  - lib/presentation/backtest/backtest_providers.dart
  - lib/presentation/components
  - lib/presentation/export/csv_export.dart
  - lib/presentation/goals
  - lib/presentation/goals/goal_page.dart
  - lib/presentation/goals/skill_copy.dart
  - lib/presentation/shared
  - lib/presentation/shared/domain_copy.dart
  - lib/presentation/shared/failure_copy.dart
  - lib/presentation/shell
  - lib/presentation/shell/app_shell.dart
  - lib/presentation/study
  - lib/presentation/study/study_page.dart
  - lib/presentation/theme
  - lib/presentation/valuation
  - lib/presentation/valuation/manual_copy.dart
  - lib/presentation/valuation/manual_valuation_page.dart
  - lib/presentation/valuation/saved_valuations.dart
  - lib/presentation/valuation/saved_valuations_card.dart
  - lib/presentation/valuation/valuation_page.dart
  - lib/presentation/valuation/valuation_providers.dart
  - lib/views
  - packages/equisim_core/lib/equisim_core.dart
  - packages/equisim_core/lib/src/audit/calculation_trace.dart
  - packages/equisim_core/lib/src/entities/fundamentals.dart
  - packages/equisim_core/lib/src/entities/portfolio.dart
  - packages/equisim_core/lib/src/entities/price_series.dart
  - packages/equisim_core/lib/src/entities/share_issue.dart
  - packages/equisim_core/lib/src/entities/valuation.dart
  - packages/equisim_core/lib/src/failures/failure.dart
  - packages/equisim_core/lib/src/repositories
  - packages/equisim_core/lib/src/repositories/repositories.dart
  - packages/equisim_core/lib/src/services/b3/b3_registry.dart
  - packages/equisim_core/lib/src/services/b3/cash_dividends.dart
  - packages/equisim_core/lib/src/services/b3/corporate_events.dart
  - packages/equisim_core/lib/src/services/backtest
  - packages/equisim_core/lib/src/services/backtest/portfolio_backtest.dart
  - packages/equisim_core/lib/src/services/cvm/capital_events.dart
  - packages/equisim_core/lib/src/services/cvm/cvm_bridge.dart
  - packages/equisim_core/lib/src/services/cvm/cvm_chart.dart
  - packages/equisim_core/lib/src/services/cvm/cvm_document_codec.dart
  - packages/equisim_core/lib/src/services/cvm/cvm_series.dart
  - packages/equisim_core/lib/src/services/cvm/fre_concessions.dart
  - packages/equisim_core/lib/src/services/cvm/fundamentals_merge.dart
  - packages/equisim_core/lib/src/services/cvm/share_count_history.dart
  - packages/equisim_core/lib/src/services/cvm/shareholder_control.dart
  - packages/equisim_core/lib/src/services/cvm/trailing_twelve_months.dart
  - packages/equisim_core/lib/src/services/cvm/unit_composition.dart
  - packages/equisim_core/lib/src/services/goal/feasibility.dart
  - packages/equisim_core/lib/src/services/metrics/beta.dart
  - packages/equisim_core/lib/src/services/metrics/beta_shrinkage.dart
  - packages/equisim_core/lib/src/services/metrics/market_leverage.dart
  - packages/equisim_core/lib/src/services/portfolio
  - packages/equisim_core/lib/src/services/portfolio/expected_return.dart
  - packages/equisim_core/lib/src/services/portfolio/transversal_ordering.dart
  - packages/equisim_core/lib/src/services/valuation
  - packages/equisim_core/lib/src/services/valuation/calibrated_band.dart
  - packages/equisim_core/lib/src/services/valuation/capital_base.dart
  - packages/equisim_core/lib/src/services/valuation/concession_sectors.dart
  - packages/equisim_core/lib/src/services/valuation/cost_of_capital.dart
  - packages/equisim_core/lib/src/services/valuation/cyclical_sectors.dart
  - packages/equisim_core/lib/src/services/valuation/dcf.dart
  - packages/equisim_core/lib/src/services/valuation/eligibility.dart
  - packages/equisim_core/lib/src/services/valuation/financial_sectors.dart
  - packages/equisim_core/lib/src/services/valuation/growth_estimator.dart
  - packages/equisim_core/lib/src/services/valuation/growth_guards.dart
  - packages/equisim_core/lib/src/services/valuation/implied_premium.dart
  - packages/equisim_core/lib/src/services/valuation/levered_rates.dart
  - packages/equisim_core/lib/src/services/valuation/manual_valuation.dart
  - packages/equisim_core/lib/src/services/valuation/manual_valuation_record.dart
  - packages/equisim_core/lib/src/services/valuation/peer_multiples.dart
  - packages/equisim_core/lib/src/services/valuation/scenario_engine.dart
  - packages/equisim_core/lib/src/services/valuation/skill_reading.dart
  - packages/equisim_core/lib/src/services/valuation/yield_curve.dart
  - packages/equisim_core/lib/src/time/brazilian_calendar.dart
  - packages/equisim_core/lib/src/usecases
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/usecases/portfolio_usecases.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - packages/equisim_core/lib/src/usecases/resolve_beta_prior.dart
  - packages/equisim_core/lib/src/value_objects/money.dart
  - packages/equisim_core/pubspec.yaml
  - pubspec.yaml
  - test/core/manual_valuation_record_test.dart
  - test/data/b3_tesouro_package_asset_test.dart
  - test/data/brapi_datasource_test.dart
  - test/data/cache_repository_test.dart
  - test/data/calibrated_band_asset_test.dart
  - test/data/cvm_fundamentals_repository_test.dart
  - test/data/cvm_package_asset_test.dart
  - test/data/tesouro_datasource_test.dart
  - test/data/valuation_runner_test.dart
  - test/tool/base_da_data_test.dart
  - test/tool/c7_test.dart
  - test/tool/capital_fre_test.dart
  - test/tool/poder_r3_test.dart
  - test/tool/regression_test.dart
  - test/ui/saved_valuations_test.dart
  - test/ui/study_user_valuation_test.dart
  - tool/b3/proventos.dart
  - tool/b3_cotahist.dart
  - tool/b3_deslistadas_contagem.dart
  - tool/b3_empacotar.dart
  - tool/b3_eventos_conferir.dart
  - tool/b3_proventos_empacotar.dart
  - tool/backfill_macro.dart
  - tool/backtest_valuation.dart
  - tool/base_negativa.dart
  - tool/beta_ida_volta.dart
  - tool/beta_liquidez.dart
  - tool/beta_prior_empacotar.dart
  - tool/beta_setorial.dart
  - tool/beta_sincronia.dart
  - tool/c7/protocolo.dart
  - tool/c7_leitura.dart
  - tool/c7_preregistrado.dart
  - tool/c7_selar.dart
  - tool/capital_empacotar.dart
  - tool/casos_de_estudo.dart
  - tool/cenario.dart
  - tool/concessao.dart
  - tool/conferir_calculo_manual.dart
  - tool/controle_empacotar.dart
  - tool/coortes/base_da_data.dart
  - tool/coortes/contagem_conferida.dart
  - tool/coortes/deslistadas.dart
  - tool/coortes/eventos_de_acoes.dart
  - tool/curva_empacotar.dart
  - tool/curva_ligar.dart
  - tool/custos_simulacao.dart
  - tool/cvm/codigos_fca.dart
  - tool/cvm/csv.dart
  - tool/cvm/documentos.dart
  - tool/cvm/emissoes_fre.dart
  - tool/cvm/outorgas_por_data.dart
  - tool/cvm/setor_cvm.dart
  - tool/cvm_empacotar.dart
  - tool/cvm_ingerir.dart
  - tool/cvm_ligar.dart
  - tool/cvm_ponte.dart
  - tool/dcf_reverso.dart
  - tool/deep_audit.dart
  - tool/exercicio_vazio.dart
  - tool/fade_terminal.dart
  - tool/fluxo_explicito.dart
  - tool/fre_outorgas.dart
  - tool/gabarito_cascata.dart
  - tool/horizonte.dart
  - tool/insumos_compartilhados.dart
  - tool/minoritario.dart
  - tool/multiplos.dart
  - tool/multiplos_empacotar.dart
  - tool/multiplos_ordenacao.dart
  - tool/padrao_ligar.dart
  - tool/perpetuidade.dart
  - tool/poder_r3.dart
  - tool/ponte_por_papel.dart
  - tool/premio_de_mercado.dart
  - tool/premio_implicito.dart
  - tool/probe_premium.dart
  - tool/proventos_conferir.dart
  - tool/recusas.dart
  - tool/regressao_condicional.dart
  - tool/retorno_esperado.dart
  - tool/reversao_roic.dart
  - tool/tamanho.dart
  - tool/unit_empacotar.dart
  - tool/validation/congelado.dart
  - tool/validation/out_of_sample.dart
  - tool/validation/regression.dart
  - tool/via_acionista.dart
  - tool/vias.dart
  - web/ASSETS.md
---

## Contexto

Até aqui o Equisim era um aplicativo Flutter sobre um núcleo de domínio em Dart
puro (`packages/equisim_core`), e as ferramentas de medição de `tool/` eram
scripts Dart sobre esse núcleo. A reconstrução web pedida pelo Otávio refez o
aplicativo em TypeScript (Vite, React, Tailwind, Firebase Web) e portou o
núcleo regra por regra para `src/core`. Durante o porte, os dois núcleos
conviveram, e as ferramentas continuavam a rodar sobre o Dart.

Dois motores no mesmo repositório são duas cópias de cada regra: uma correção
feita numa e esquecida na outra, e as medições de `docs/validacao/` deixando de
descrever o motor do aplicativo. É o risco que a decisão 132 fechou para a
cópia dos insumos, em escala maior. Daí o pedido: apagar o núcleo Dart e
portar todos os scripts.

## Decisão

**O Equisim passa a ser TypeScript de ponta a ponta, e o Dart sai do
repositório.** Mudam a linguagem e a plataforma; o método não muda.

1. **O núcleo é `src/core`, TypeScript puro.** Zero dependência de execução,
   sem rede, sem arquivo, sem relógio e sem navegador, travado por
   `test/core/purity.test.ts` — a mesma regra que valia para o
   `packages/equisim_core`. As diferenças de semântica entre as duas linguagens
   (arredondamento `round` contra `Math.round`, `%` com sinal, `DateTime`,
   `Random`, `toStringAsFixed`) ficam num só lugar, `src/core/lang/`, que
   reproduz a do Dart compilado para a web.

2. **A prova de que o método não mudou é a paridade** (`test/parity/`). O
   núcleo Dart, compilado para JavaScript pelo dart2js, gravou em 23/10/2026 a
   saída de 371 ativos em treze montagens da cascata, mais os serviços
   (valuation manual, DCF reverso, simulação, metas, ordenação transversal,
   calendário). O núcleo TypeScript refaz a bateria e a suíte exige igualdade
   exata: número com número por `Object.is`, texto com texto e a impressão
   SHA-256 de cada um dos 3.894 rastros de auditoria. Na gravação, zero
   divergências. O gabarito é a fotografia do Dart e **não se regrava a partir
   do TypeScript**; uma mudança de método deliberada o muda junto, com decisão
   própria.

3. **Os 97 arquivos de `tool/` (76 ferramentas e 21 bibliotecas) viram módulos
   TypeScript** sobre o mesmo `src/core` e o mesmo `src/data` do aplicativo,
   com nome em inglês e `kebab-case`, rodando por `npm run tool -- <nome>`. O
   mapa de cada `.dart` para o `.ts` que o substitui está no
   [README de tool/](../../tool/README.md). Argumentos, caminhos de saída e
   campos de JSON continuam os de antes, em português, para que os relatórios
   de `docs/validacao/` e os scripts Python sigam lendo o que liam. O cache das
   ferramentas (`tool/lib/sqlite-cache.ts`, sobre `node:sqlite`) usa as mesmas
   tabelas do cache que o aplicativo Flutter deixava, de modo que um
   `validation_cache.sqlite` já gravado continua valendo.

4. **Saem do repositório** o `packages/equisim_core`, o `lib/` do Flutter, as
   pastas de plataforma, o `pubspec.yaml`, os testes `.dart` e os scripts
   `.dart` de `tool/` — os caminhos que decisões anteriores citavam estão em
   `retira`. Os pacotes de dados vão de `assets/` para `public/assets/`, de
   onde o Vite os serve. Nenhum arquivo Dart fica na árvore: o harness que
   gravou o gabarito (`test/parity/dart/`) sai também e se restaura do commit
   `7480c5a`, com o núcleo do commit `1e83fad`, quando for preciso regravar.

5. **O que o aplicativo anterior decidiu, o aplicativo web mantém.** O
   valuation confirmado vai à coleção `valuations` do Firestore e ao painel de
   logs (decisão 150), a tela Estudo mostra o valuation do usuário quando ele
   discorda do motor (decisão 151), o retorno esperado da carteira não usa o
   preço justo, e a exportação do rastro continua no formato 2, pelo canal
   `equisim_audit_channel_v1`.

6. **Limiares do veredito do modo Essencial.** A tela nova resume a avaliação
   numa frase (`src/copy/verdict-copy.ts`). Os limiares são de apresentação e
   não mudam conta nenhuma: distância abaixo de **10%** entre o preço e o
   preço justo é "perto" (menos do que ±1 p.p. na taxa de desconto move um DCF
   típico), e a partir de **100%** o número é lido como sintoma, o mesmo
   limiar da marca ⚠ que a tela Estudo do Flutter já usava.

7. **As ferramentas do repositório passam a falar da árvore nova.** O gate
   local (`scripts/qa-local.mjs`) aplica as regras de linha a `.ts`/`.tsx`,
   procura `DateTime.now()`, `new Date()` e `Date.now()` diretos em
   `src/core`, e confere o sistema de design contra `src/styles.css`. O
   auditor e o conselheiro (`scripts/qa/`) trocam os idiomas do Dart pelos do
   JavaScript. A captura de telas é `scripts/capture-screens.ts`. O
   `tool/setup.sh` e o `tool/setup.ps1` preparam o Node.

## Consequências aceitas

- **O C7 continua precisando do SDK do Flutter.** O motor pré-registrado é o
  núcleo Dart do commit selado (decisões 133 e 138), e
  `tool/c7-preregistered.ts` o roda naquele commit com `flutter pub get` e
  `dart run`. A impressão do núcleo é procurada nas duas árvores, a Dart de
  antes (`packages/equisim_core/lib`) e a TypeScript de hoje (`src/core`). A
  série «motor da data» das selagens futuras sai do TypeScript, com impressão
  nova.

- **O gabarito da cascata (`tool/cascade-golden.ts`) precisa ser regravado
  antes de `--conferir`.** A impressão é a mesma conta (FNV-1a de 64 bits), mas
  sobre o rastro escrito pelo JSON do JavaScript, que grava `1` onde o Dart
  gravava `1.0`. Um gabarito gravado pelo Dart não confere, sem que número
  algum tenha mudado.

- **Os dados dos casos de estudo não foram refeitos.** `npm run tool --
  study-cases` lê a entrada congelada do gabarito (`data/gabarito/`), que não
  é versionada. Os números de `docs/estudo/casos/` são os que o
  `tool/casos_de_estudo.dart` produziu; a paridade garante que o núcleo novo
  dá os mesmos sobre a mesma entrada, e quem tiver a entrada congelada deve
  refazê-los para que a proveniência aponte para o `.ts`.

- **A escrita de alguns valores muda, sem que o número mude:**
  - número inteiro guardado como `double` sai sem o `.0` no JSON (`10`, e não
    `10.0`), que é como o JavaScript escreve número;
  - `NaN` e infinito saem como `null` no JSON, pela regra do `JSON.stringify`;
    o `jsonEncode` do Dart interrompia a gravação com erro;
  - `geradoPor` e as linhas de proveniência apontam para o `.ts`, e os
    caminhos de pacote para `public/assets/`;
  - o `compact` do backtest arredonda todo número a seis algarismos, e não só
    `double`; os inteiros da linha ficam muito abaixo de um milhão, onde isso
    não muda nada;
  - a ingestão da CVM sem CSV anual falha com a pasta na mensagem, onde o
    Dart falhava com `Bad state: No element`.

- **Ordem e último bit podem diferir do Dart da máquina virtual.** A
  ordenação do JavaScript é estável desde o ECMAScript 2019, e o `List.sort`
  do Dart não garante estabilidade: em empate, uma ferramenta pode listar em
  outra ordem. O gabarito de paridade foi gravado pelo dart2js, de modo que o
  aplicativo web reproduz o Flutter web bit a bit; contra as ferramentas, que
  rodavam na máquina virtual do Dart, funções transcendentes (`pow`, `exp`,
  `log`) podem diferir no último bit.

- **As ferramentas reproduzem o original, inclusive onde ele perdia dado.** O
  `withMarket` do backtest refaz cada exercício campo a campo como o Dart fazia,
  e os campos que o Dart não listava saem vazios. Corrigir isso muda as
  medições, e pede decisão própria.

- **Credencial.** O Vite embarca no bundle toda variável `VITE_*`. Em produção
  o token da brapi fica no proxy (`VITE_BRAPI_PROXY_URL`); `VITE_BRAPI_TOKEN`
  serve só ao desenvolvimento. As ferramentas leem `BRAPI_TOKEN`, sem o
  prefixo, só no Node. A `GEMINI_API_KEY` continua em `.env.qa`.

- **Node 22.13 ou mais recente para as ferramentas.** O aplicativo compila no
  Node 20.19; o cache das ferramentas usa o `node:sqlite`, que só sai de trás
  da opção experimental no 22.13.
