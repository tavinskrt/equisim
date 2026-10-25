# tool/ — medições, empacotadores e conferências

Tudo o que mede o motor, monta os pacotes de `public/assets/` ou confere uma
fonte de dados mora aqui. Até a [decisão 152](../docs/decisoes/152-o-equisim-passa-a-typescript-e-o-dart-sai-do-repositorio.md)
eram scripts Dart sobre `packages/equisim_core`; agora são módulos TypeScript
sobre o **mesmo núcleo que o aplicativo usa**, `src/core`, e a camada de dados
dele, `src/data`. Não há segunda implementação do motor para as ferramentas.

## Como rodar

```bash
npm run tool                                  # lista as ferramentas
npm run tool -- <ferramenta> [argumentos]     # executa uma
npm run tool -- implied-premium --so-serie    # exemplo
```

O despachante é [`run.ts`](run.ts): cada ferramenta é um arquivo `tool/<nome>.ts`
que exporta `main(args)`, e o nome é o do arquivo sem a extensão. Os
argumentos continuam os de antes, em português (`--montagem aplicativo`,
`--trimestral`, `--saida`), e os arquivos que cada ferramenta grava também: o
caminho, o nome e os campos do JSON não mudaram, para que os relatórios em
`docs/validacao/` e os scripts Python continuem lendo o que liam.

**Requisitos.** Node 22.13 ou mais recente: o cache das ferramentas usa o
módulo `node:sqlite`, que saiu de trás da opção experimental nessa versão. O
aplicativo em si roda no Node 20. As ferramentas que vão à rede leem
`BRAPI_TOKEN` (sem o prefixo `VITE_`) do `.env` da raiz ou do ambiente, **só no
Node** — ver [`validation/context.ts`](validation/context.ts). O Vite embarca no
bundle apenas as variáveis `VITE_*`, de modo que essa credencial nunca chega ao
navegador.

**O cache.** As medições que consultam a brapi guardam as respostas em
`docs/validacao/validation_cache.sqlite` ([`lib/sqlite-cache.ts`](lib/sqlite-cache.ts)),
com as mesmas tabelas do cache que o aplicativo Flutter deixava: um cache de
antes continua valendo. O teste [`test/tool/sqlite-cache.test.ts`](../test/tool/sqlite-cache.test.ts)
confere que ele responde como o cache do navegador à mesma sequência de
operações.

**Os dados brutos** (`data/`: CVM, COTAHIST, Formulário de Referência, Tesouro)
não são versionados. Os scripts Python que os baixam (`*_baixar.py`) e os que
leem as medições continuam em Python e não mudaram de nome.

## Convenções

- Nome de arquivo em inglês e em `kebab-case`; comentário, mensagem de console
  e campo de JSON em português, como antes.
- `assets/...` passou a `public/assets/...`, que é de onde o Vite serve os
  pacotes.
- Uma ferramenta que falha por falta de dado ou de credencial sai com código 2
  e diz o que rodar antes.

## O que mudou no resultado

Os números são os mesmos, porque o núcleo foi portado um a um e conferido
contra o gabarito do motor Dart (`test/parity/`). Mudou a **escrita** de
alguns valores, e a decisão 152 lista cada caso. Os que mais aparecem:

- número inteiro guardado como `double` sai sem o `.0` no JSON (`10`, e não
  `10.0`), que é como o JavaScript escreve número;
- `NaN` e infinito saem como `null` no JSON, onde o Dart interrompia a gravação
  com erro;
- `geradoPor` e as linhas de proveniência apontam para o `.ts`;
- a impressão digital da cascata (`cascade-golden`) é a mesma conta (FNV-1a de
  64 bits, em hexadecimal), mas sobre o rastro escrito pelo JSON do
  JavaScript: um gabarito gravado pelo Dart não confere, e precisa ser
  regravado sob o TypeScript antes de `--conferir`.

## Ferramentas (76)

| Antes (Dart) | Agora (TypeScript) | Comando | O que faz |
|---|---|---|---|
| `b3_cotahist.dart` | [`b3-cotahist.ts`](b3-cotahist.ts) | `npm run tool -- b3-cotahist` | A3 — COTAHIST da B3: eventos de ações e preço de quem deixou de existir. |
| `b3_deslistadas_contagem.dart` | [`b3-delisted-count.ts`](b3-delisted-count.ts) | `npm run tool -- b3-delisted-count` | A3.4 — contagem de ações e eventos por data, para as companhias deslistadas. |
| `b3_proventos_empacotar.dart` | [`b3-dividends-package.ts`](b3-dividends-package.ts) | `npm run tool -- b3-dividends-package` | A4 — empacota os proventos da B3 para o aplicativo. |
| `b3_eventos_conferir.dart` | [`b3-events-check.ts`](b3-events-check.ts) | `npm run tool -- b3-events-check` | A3.1 — o registro oficial da B3 contra a inferência pelo preço. |
| `b3_empacotar.dart` | [`b3-package.ts`](b3-package.ts) | `npm run tool -- b3-package` | A3.3 — empacota o registro de emissores da B3 para o aplicativo. |
| `backfill_macro.dart` | [`backfill-macro.ts`](backfill-macro.ts) | `npm run tool -- backfill-macro` | Estende o histórico das séries macro no cache de validação. |
| `backtest_valuation.dart` | [`backtest-valuation.ts`](backtest-valuation.ts) | `npm run tool -- backtest-valuation` | Validação preditiva do motor de avaliação, *point-in-time*. |
| `beta_liquidez.dart` | [`beta-liquidity.ts`](beta-liquidity.ts) | `npm run tool -- beta-liquidity` | B14 — o beta do papel pouco negociado, e o que ele faz com o nível. |
| `beta_prior_empacotar.dart` | [`beta-prior-package.ts`](beta-prior-package.ts) | `npm run tool -- beta-prior-package` | B11 — resolve o prior transversal do beta e o empacota para o aplicativo. |
| `beta_ida_volta.dart` | [`beta-round-trip.ts`](beta-round-trip.ts) | `npm run tool -- beta-round-trip` | A ida e a volta do beta não se cancelam. |
| `beta_setorial.dart` | [`beta-sector.ts`](beta-sector.ts) | `npm run tool -- beta-sector` | Beta desalavancado, e quanto o setor explica. |
| `beta_sincronia.dart` | [`beta-synchrony.ts`](beta-synchrony.ts) | `npm run tool -- beta-synchrony` | O beta e a negociação não síncrona. |
| `ponte_por_papel.dart` | [`bridge-by-share.ts`](bridge-by-share.ts) | `npm run tool -- bridge-by-share` | A ponte por papel nas coortes — item C3. |
| `ponte.dart` | [`bridge.ts`](bridge.ts) | `npm run tool -- bridge` | D7 — o efeito da ponte completa, isolado do dado novo. |
| `c7_preregistrado.dart` | [`c7-preregistered.ts`](c7-preregistered.ts) | `npm run tool -- c7-preregistered` | A série do motor pré-registrado do C7, produzida pelo commit dele (item C7, decisões 133 e 138). |
| `c7_leitura.dart` | [`c7-reading.ts`](c7-reading.ts) | `npm run tool -- c7-reading` | A leitura da réplica fora da amostra (item C7, decisões 129 e 133). |
| `c7_selar.dart` | [`c7-seal.ts`](c7-seal.ts) | `npm run tool -- c7-seal` | Sela as previsões das coortes novas (item C7, decisões 129 e 133). |
| `capital_empacotar.dart` | [`capital-package.ts`](capital-package.ts) | `npm run tool -- capital-package` | B28 e B29 — empacota os eventos de capital de cada ativo para o aplicativo. |
| `gabarito_cascata.dart` | [`cascade-golden.ts`](cascade-golden.ts) | `npm run tool -- cascade-golden` | D1 — gabarito da cascata: a condição para quebrar `evaluateLane`. |
| `concessao.dart` | [`concession.ts`](concession.ts) | `npm run tool -- concession` | D8 — a perpetuidade aplicada a contrato que acaba. |
| `regressao_condicional.dart` | [`conditional-regression.ts`](conditional-regression.ts) | `npm run tool -- conditional-regression` | Regressão condicional — o potencial informa o que os fatores ingênuos não informam? |
| `controle_empacotar.dart` | [`control-package.ts`](control-package.ts) | `npm run tool -- control-package` | B46 — empacota a espécie do controle acionário de cada emissor. |
| `divisor_contrafactual.dart` | [`counterfactual-divisor.ts`](counterfactual-divisor.ts) | `npm run tool -- counterfactual-divisor` | O divisor da ponte: quanto custa a regra do maior, e o que o backtest vê. |
| `curva_ligar.dart` | [`curve-link.ts`](curve-link.ts) | `npm run tool -- curve-link` | A2 — a curva de juros observada ligada ao motor, e o que ela move. |
| `curva_empacotar.dart` | [`curve-package.ts`](curve-package.ts) | `npm run tool -- curve-package` | A2.1 — empacota as cotações recentes do Tesouro para o aplicativo. |
| `cvm_ponte.dart` | [`cvm-bridge.ts`](cvm-bridge.ts) | `npm run tool -- cvm-bridge` | Constrói a ponte ticker -> CNPJ com as regras do núcleo, sobre o FCA real. |
| `cvm_conferir.dart` | [`cvm-check.ts`](cvm-check.ts) | `npm run tool -- cvm-check` | Roda o leitor do plano de contas da CVM sobre os arquivos REAIS. |
| `cvm_ingerir.dart` | [`cvm-ingest.ts`](cvm-ingest.ts) | `npm run tool -- cvm-ingest` | Ingestão da CVM: dos CSVs anuais para a série de documentos do motor. |
| `cvm_ligar.dart` | [`cvm-link.ts`](cvm-link.ts) | `npm run tool -- cvm-link` | A1.7 e A1.8 — a ingestão da CVM ligada ao motor, em três montagens. |
| `cvm_empacotar.dart` | [`cvm-package.ts`](cvm-package.ts) | `npm run tool -- cvm-package` | A1.9 — empacota os documentos da CVM do universo para o aplicativo. |
| `deep_audit.dart` | [`deep-audit.ts`](deep-audit.ts) | `npm run tool -- deep-audit` | Diagnóstico profundo do motor de avaliação — instrumentação por ativo. |
| `padrao_ligar.dart` | [`default-link.ts`](default-link.ts) | `npm run tool -- default-link` | Fase 1 — o que cada peça do eixo A move, somadas uma a uma, na mesma execução. |
| `proventos_conferir.dart` | [`dividends-check.ts`](dividends-check.ts) | `npm run tool -- dividends-check` | A4 — os proventos da B3 conferidos, e o retorno total nas coortes. |
| `dump_universo.dart` | [`dump-universe.ts`](dump-universe.ts) | `npm run tool -- dump-universe` | Grava o universo da fonte de preços, com nome e setor de cada ticker, em `docs/validacao/universo.json`. |
| `exercicio_vazio.dart` | [`empty-fiscal-year.ts`](empty-fiscal-year.ts) | `npm run tool -- empty-fiscal-year` | O exercício que a fonte publica sem demonstração de resultado. |
| `via_acionista.dart` | [`equity-route.ts`](equity-route.ts) | `npm run tool -- equity-route` | D2b — o destino da via do acionista sobre LPA. |
| `retorno_esperado.dart` | [`expected-return.ts`](expected-return.ts) | `npm run tool -- expected-return` | O retorno esperado da carteira e a âncora que faltava. |
| `fluxo_explicito.dart` | [`explicit-flow.ts`](explicit-flow.ts) | `npm run tool -- explicit-flow` | D4 — de onde vem o resíduo entre o preço justo e o de mercado. |
| `fre_outorgas.dart` | [`fre-grants.ts`](fre-grants.ts) | `npm run tool -- fre-grants` | A6 — o prazo das outorgas, do Formulário de Referência para o aplicativo. |
| `crescimento_fundamental.dart` | [`fundamental-growth.ts`](fundamental-growth.ts) | `npm run tool -- fundamental-growth` | O crescimento fundamental `g = ROE × (1 − payout)`, e o do PIB do setor para quem cresce sem reter — medição, sem ligar nada no motor. |
| `premio_historico.dart` | [`historical-premium.ts`](historical-premium.ts) | `npm run tool -- historical-premium` | O prêmio de risco medido do Ibovespa, no lugar dos 5,5% fixos — medição, sem ligar nada no motor. |
| `horizonte.dart` | [`horizon.ts`](horizon.ts) | `npm run tool -- horizon` | Item B6 — a varredura do horizonte de projeção. |
| `premio_implicito.dart` | [`implied-premium.ts`](implied-premium.ts) | `npm run tool -- implied-premium` | O prêmio de risco implícito no preço do mercado, e a versão normalizada — medição, sem ligar nada no motor. |
| `capital_investido.dart` | [`invested-capital.ts`](invested-capital.ts) | `npm run tool -- invested-capital` | As duas rotas do capital investido, que nunca se conferem. |
| `vias.dart` | [`lanes.ts`](lanes.ts) | `npm run tool -- lanes` | A discordância entre as duas vias, medida ativo a ativo. |
| `conferir_calculo_manual.dart` | [`manual-calculation-check.ts`](manual-calculation-check.ts) | `npm run tool -- manual-calculation-check` | Conferência do cálculo do usuário sobre o universo inteiro (decisão 147). |
| `premio_de_mercado.dart` | [`market-premium.ts`](market-premium.ts) | `npm run tool -- market-premium` | Item B3 — o prêmio de risco de mercado deixa de ser parâmetro. |
| `minoritario.dart` | [`minority-interest.ts`](minority-interest.ts) | `npm run tool -- minority-interest` | Item B23 — o minoritário nos pesos do custo médio de capital. |
| `multiplos_empacotar.dart` | [`multiples-package.ts`](multiples-package.ts) | `npm run tool -- multiples-package` | Item B5 — mede as medianas de múltiplos por grupo de pares e as empacota. |
| `multiplos_ordenacao.dart` | [`multiples-ranking.ts`](multiples-ranking.ts) | `npm run tool -- multiples-ranking` | Item B22 — o múltiplo de pares como ordenação, medido ao lado das três da decisão 103. |
| `multiplos.dart` | [`multiples.ts`](multiples.ts) | `npm run tool -- multiples` | Item B5 — mede a divergência entre o fluxo descontado e os múltiplos de pares, no universo. |
| `base_negativa.dart` | [`negative-base.ts`](negative-base.ts) | `npm run tool -- negative-base` | O exercício-base no prejuízo, e o que o motor faz com ele. |
| `normalizacoes.dart` | [`normalizations.ts`](normalizations.ts) | `npm run tool -- normalizations` | Por que o lucro de partida de cada ativo foi normalizado, e em que direção. |
| `perpetuidade.dart` | [`perpetuity.ts`](perpetuity.ts) | `npm run tool -- perpetuity` | B15 — o beta e a estrutura de capital com que a perpetuidade é descontada. |
| `probe_ponte.dart` | [`probe-bridge.ts`](probe-bridge.ts) | `npm run tool -- probe-bridge` | D7 — o que a fonte publica entre o valor da firma e o do acionista. |
| `probe_dcf.dart` | [`probe-dcf.ts`](probe-dcf.ts) | `npm run tool -- probe-dcf` | Sondas isoladas sobre o DCF: medem hipóteses de defeito sem tocar em dados de produção. |
| `probe_premium.dart` | [`probe-premium.ts`](probe-premium.ts) | `npm run tool -- probe-premium` | Sensibilidade da distribuição de potencial ao prêmio de risco de mercado. |
| `poder_r3.dart` | [`r3-power.ts`](r3-power.ts) | `npm run tool -- r3-power` | O poder do teste do R3: que habilidade o critério da decisão 96 conseguiria ver com a amostra que há. |
| `recusas.dart` | [`refusals.ts`](refusals.ts) | `npm run tool -- refusals` | Por que o motor recusa o que recusa. |
| `reapresentacao.dart` | [`restatement.ts`](restatement.ts) | `npm run tool -- restatement` | B8 — o tamanho da reapresentação no *point-in-time*. |
| `retorno_por_ativo.dart` | [`return-by-asset.ts`](return-by-asset.ts) | `npm run tool -- return-by-asset` | O retorno por ativo mede o ativo, ou o cronograma de aportes? |
| `dcf_reverso.dart` | [`reverse-dcf.ts`](reverse-dcf.ts) | `npm run tool -- reverse-dcf` | DCF reverso — o que o preço de mercado está implicando. |
| `grupamento.dart` | [`reverse-split.ts`](reverse-split.ts) | `npm run tool -- reverse-split` | O grupamento que a regra do maior sempre ignora. |
| `reversao_roic.dart` | [`roic-reversion.ts`](roic-reversion.ts) | `npm run tool -- roic-reversion` | B19 — a rentabilidade reverte à média? |
| `cenario.dart` | [`scenario.ts`](scenario.ts) | `npm run tool -- scenario` | Item B20 — a tradução do cenário de desconto para o `Ke` da rota derivada. |
| `selic_focus.dart` | [`selic-focus.ts`](selic-focus.ts) | `npm run tool -- selic-focus` | A Selic prevista no lugar da taxa livre de risco — o pedido do orientador, medido sobre a entrada congelada do gabarito. |
| `insumos_compartilhados.dart` | [`shared-inputs.ts`](shared-inputs.ts) | `npm run tool -- shared-inputs` | A1 — quanto da discordância entre as vias vem de medir a mesma coisa duas vezes? |
| `custos_simulacao.dart` | [`simulation-costs.ts`](simulation-costs.ts) | `npm run tool -- simulation-costs` | O efeito da tarifa da B3 sobre a simulação da carteira (item C4). |
| `tamanho.dart` | [`size.ts`](size.ts) | `npm run tool -- size` | Item B4 — o ajuste por tamanho no custo de capital. |
| `estatais.dart` | [`state-owned.ts`](state-owned.ts) | `npm run tool -- state-owned` | B46 — o risco do controle estatal: o beta, o lambda e o efeito no preço. |
| `casos_de_estudo.dart` | [`study-cases.ts`](study-cases.ts) | `npm run tool -- study-cases` | Os casos da documentação de estudo (`docs/estudo/casos/`), com tudo o que o aplicativo calcula para cada ativo, sobre a entrada congelada do gabarito (14/09/2026): insumos, CAPM, curva, exercícios publicados, resultado, cenários, Monte Carlo, faixa calibrada, múltiplos, ressalvas, avisos e o rastro de auditoria inteiro — o mesmo do painel de logs. |
| `fade_terminal.dart` | [`terminal-fade.ts`](terminal-fade.ts) | `npm run tool -- terminal-fade` | O degrau da vantagem competitiva, medido antes de ser trocado. |
| `unit_empacotar.dart` | [`unit-package.ts`](unit-package.ts) | `npm run tool -- unit-package` | B16 — empacota a composição declarada das units para o aplicativo. |
| `unit_vs_classe.dart` | [`unit-vs-class.ts`](unit-vs-class.ts) | `npm run tool -- unit-vs-class` | A unit e a classe que a compõe têm de concordar. |
| `unidade.dart` | [`unit.ts`](unit.ts) | `npm run tool -- unit` | A razão de unidade e a tolerância que aperta onde deveria afrouxar. |
| `validate.dart` | [`validate.ts`](validate.ts) | `npm run tool -- validate` | Executor de validação: invariantes, sensibilidade, exportação para Python e inferência. |

## Bibliotecas (21)

Módulos que as ferramentas importam e que não se executam sozinhos.

| Antes (Dart) | Agora (TypeScript) | O que faz |
|---|---|---|
| `b3/proventos.dart` | [`b3/dividends.ts`](b3/dividends.ts) | Leitores compartilhados dos itens A4 e A3.4: proventos da B3 e fechamento bruto do COTAHIST. |
| `c7/protocolo.dart` | [`c7/protocol.ts`](c7/protocol.ts) | O protocolo da réplica fora da amostra (item C7, decisões 129 e 133). |
| `coortes/base_da_data.dart` | [`cohorts/as-of-base.ts`](cohorts/as-of-base.ts) | A ponte por papel na data da coorte (item C3). |
| `coortes/contagem_conferida.dart` | [`cohorts/checked-count.ts`](cohorts/checked-count.ts) | A contagem de ações por data conferida contra o salto do preço (item B43). |
| `coortes/deslistadas.dart` | [`cohorts/delisted.ts`](cohorts/delisted.ts) | As companhias deslistadas, prontas para entrar nas coortes (item C1b). |
| `coortes/eventos_de_acoes.dart` | [`cohorts/share-events.ts`](cohorts/share-events.ts) | Os eventos de ações de uma companhia listada — desdobramento, grupamento e bonificação —, e o que eles fazem com a série da fonte e com a contagem por data das coortes (itens B29 e B30). |
| `cvm/csv.dart` | [`cvm/csv.ts`](cvm/csv.ts) | Leitor dos CSVs de dados abertos da CVM com campo aspado. |
| `cvm/setor_cvm.dart` | [`cvm/cvm-sector.ts`](cvm/cvm-sector.ts) | O setor das companhias deslistadas que a B3 não classifica (item C1b). |
| `cvm/documentos.dart` | [`cvm/documents.ts`](cvm/documents.ts) | Leitura da base ingerida (`data/cvm_exercicios.json`) para documentos do núcleo. |
| `cvm/codigos_fca.dart` | [`cvm/fca-codes.ts`](cvm/fca-codes.ts) | Códigos de negociação e composição de unit declarados na FCA da CVM. |
| `cvm/emissoes_fre.dart` | [`cvm/fre-issues.ts`](cvm/fre-issues.ts) | As emissões de ações por valor do Formulário de Referência, com a data em que cada uma ficou pública (item B28). |
| `cvm/outorgas_por_data.dart` | [`cvm/grants-by-date.ts`](cvm/grants-by-date.ts) | O prazo das outorgas como era conhecido numa data (item A6 nas coortes). |
| `validation/context.dart` | [`validation/context.ts`](validation/context.ts) | Dependências do executor de validação: os mesmos repositórios do aplicativo, sobre o cache SQLite em arquivo. |
| `validation/congelado.dart` | [`validation/frozen.ts`](validation/frozen.ts) | A entrada congelada do gabarito, para quem só quer medir sobre ela. |
| `validation/inference_export.dart` | [`validation/inference-export.ts`](validation/inference-export.ts) | Séries sintéticas e determinísticas para conferir as primitivas estatísticas do núcleo fora dele. |
| `validation/invariants.dart` | [`validation/invariants.ts`](validation/invariants.ts) | Identidades que o motor precisa satisfazer, conferidas ativo a ativo. |
| `validation/ibovespa_longo.dart` | [`validation/long-ibovespa.ts`](validation/long-ibovespa.ts) | O Ibovespa diário longo: o SGS 7 do Banco Central antes da fonte de mercado, e a fonte dali em diante. |
| `validation/out_of_sample.dart` | [`validation/out-of-sample.ts`](validation/out-of-sample.ts) | O que o log de avaliação registrou sobre as guardas de cada ativo, fora da amostra. |
| `validation/python_export.dart` | [`validation/python-export.ts`](validation/python-export.ts) | Exporta séries e métricas para conferência independente em Python. |
| `validation/regression.dart` | [`validation/regression.ts`](validation/regression.ts) | Regressão múltipla e estatística de ordem para os utilitários de validação. |
| `validation/sensitivity.dart` | [`validation/sensitivity.ts`](validation/sensitivity.ts) | Avaliação de cada ativo sob cada configuração de premissas. |

Além delas, seis módulos novos, sem antecessor em Dart:
[`run.ts`](run.ts) (o despachante), [`lib/files.ts`](lib/files.ts) (leitura,
escrita e formatação no jeito que os scripts esperavam),
[`lib/sqlite-cache.ts`](lib/sqlite-cache.ts) (o cache em arquivo),
[`lib/shuffle.ts`](lib/shuffle.ts) e [`lib/stats.ts`](lib/stats.ts) (pequenos
utilitários repetidos entre ferramentas) e [`cvm/quoted-csv.ts`](cvm/quoted-csv.ts)
(o leitor de CSV aspado que dois scripts tinham cada um à sua maneira).
