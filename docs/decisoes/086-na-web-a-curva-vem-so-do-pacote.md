---
numero: 86
titulo: Na web, a curva do Tesouro vem só do pacote do build, e a função tesouro sai
status: aceita
origem: voce
data: 2026-09-14
afeta:
  - lib/data/config/api_config.dart
  - lib/data/datasources/remote/tesouro_datasource.dart
  - lib/data/repositories/risk_free_curve_repository.dart
  - lib/di/providers.dart
  - lib/presentation/valuation/valuation_providers.dart
  - functions/index.js
  - packages/equisim_core/lib/src/services/valuation/yield_curve.dart
  - tool/curva_empacotar.dart
  - test/data/tesouro_datasource_test.dart
  - README.md
substitui: []
---

## Contexto

A [decisão 84](084-a-curva-e-o-padrao-do-aplicativo.md) fez da curva do
Tesouro o padrão do aplicativo e, para a web — cujo navegador não lê o arquivo
do Tesouro, por CORS —, pôs uma função de nuvem, `tesouro`, ao lado da `brapi`.
O deploy ficou com o usuário, como item A2.2 do plano.

**O deploy não é possível no projeto como está.** Em 14/09/2026,
`firebase deploy --only functions` parou em: *"Your project equisim-d7128 must
be on the Blaze (pay-as-you-go) plan"*. O Firebase só publica função no plano
Blaze, que exige conta de faturamento e não tem teto de gasto, só alerta. O
projeto está no plano sem cobrança, e a mesma mensagem mostrou as APIs de
função sendo ligadas pela primeira vez: **nenhuma função deste repositório
jamais foi publicada**, nem o proxy da `brapi`.

Três caminhos foram postos ao usuário: ativar o Blaze; publicar o mesmo JSON
como arquivo estático, atualizado por uma GitHub Action diária; ou deixar a web
só com o pacote que o build já leva.

## Decisão

**Tomada pelo usuário em 14/09/2026: a web usa só o pacote.** Substitui, da
decisão 84, o item 2 — a função `tesouro` — e a consequência aceita que dizia
"até o deploy da função". Os itens 1, 3, 4 e 5 continuam valendo.

1. **Na web, o aplicativo não busca o Tesouro.** `RiskFreeCurveRepository`
   recebe a fonte do dia só no nativo; na web ela é `null` e a curva sai do
   pacote `assets/tesouro/curva.json`, com a mesma regra de data de
   `TreasuryCurve.at`. Nenhuma requisição que o navegador vai barrar.
2. **A função `tesouro` sai de `functions/index.js`**, e `TESOURO_PROXY_URL`
   sai de `ApiConfig`. Código que não pode ser publicado e configuração sem
   consumidor são decisão não entregue à espera de ser apontada. O histórico do
   git guarda os dois, se o Blaze vier.
3. **O pacote é regerado antes de cada build web**, pelos comandos de
   `tool/curva_empacotar.dart`, registrados no README.
4. **Sem curva, a avaliação diz por quê.** O repositório devolve, junto da
   curva ausente, uma ressalva com a origem (web ou Tesouro fora), a data-base
   mais recente do pacote ou a ausência dele, e — na web — que um build novo
   traz a curva de volta. A ressalva entra nos avisos da avaliação como a da
   cobertura da CVM (item A1.10). Com curva, nada muda: a própria avaliação já
   declara a data-base.

## Consequências aceitas

**A curva da web envelhece com o build.** O pacote guarda as dez datas-base
mais recentes, e `TreasuryCurve.at` aceita data-base de até sete dias: um build
web serve a curva por cerca de uma semana depois da última data-base do pacote,
e então a avaliação recua para os dois pontos do CDI, com a ressalva do item 4.
Na web a queda de nível que a curva trouxe (−28,7% para −46,0% no potencial
mediano, decisão 84) some quando o build envelhece, e volta no build seguinte.

**O nativo não muda.** Continua lendo o Tesouro no dia, com o pacote de recuo.

**Alternativas descartadas.** *Blaze*: resolve e mantém a web no dia, mas pede
faturamento sem teto a um projeto de TCC, por um único consumidor que hoje nem
está publicado — `firebase.json` não tem hosting. *Arquivo estático no GitHub*:
sem cobrança e com a web no dia, mas acrescenta um agendamento que o GitHub
pausa depois de 60 dias sem atividade no repositório, e um ramo de dados para
manter. As duas continuam possíveis: o formato de `TreasuryQuotesCodec` é o
mesmo do pacote, e qualquer uma delas voltaria como decisão nova.

**O proxy da `brapi` fica como estava** — opcional e documentado —, mas agora
com a nota de que também exige o Blaze.
