---
numero: 84
titulo: A curva do Tesouro é o padrão do aplicativo, lida no dia e com recuo declarado
status: aceita
origem: voce
data: 2026-09-14
afeta:
  - lib/data/config/api_config.dart
  - lib/data/network/api_client.dart
  - lib/data/datasources/remote/tesouro_datasource.dart
  - lib/data/repositories/risk_free_curve_repository.dart
  - lib/di/providers.dart
  - lib/presentation/valuation/valuation_providers.dart
  - packages/equisim_core/lib/src/services/valuation/yield_curve.dart
  - packages/equisim_core/test/yield_curve_test.dart
  - functions/index.js
  - assets/tesouro/curva.json
  - pubspec.yaml
  - tool/curva_empacotar.dart
  - tool/curva_ligar.dart
  - test/data/tesouro_datasource_test.dart
  - test/data/b3_tesouro_package_asset_test.dart
substitui: []
---

## Contexto

A [decisão 74](074-a-taxa-livre-de-risco-segue-a-curva-observada.md) pôs a curva
dos prefixados do Tesouro no núcleo e deixou o padrão para o usuário, porque ela
muda o nível de toda avaliação. A curva existia só nas ferramentas de validação
— era o item A2.1.

**O obstáculo era de transporte.** O arquivo do Tesouro Transparente tem 14,5
MB e libera CORS só para o domínio do próprio Tesouro: o aplicativo web não pode
lê-lo. O JSON do site do Tesouro Direto devolve 403 fora do navegador, e as taxas
referenciais de swap DI × pré no SGS do Banco Central foram descontinuadas em
2019.

**Duas medições destravaram o nativo.** O arquivo vem em ordem **decrescente**
de data-base — zero inversões em 176.042 linhas — e as 58 linhas do dia mais
recente cabem nos primeiros quilobytes. Ler só o começo e parar resolve.

## Decisão

**Tomada pelo usuário em 14/09/2026: a curva é o padrão, e a web usa função de
nuvem.**

1. **O aplicativo avalia pela curva do dia.** No nativo, `TesouroDatasource`
   resolve o endereço do arquivo pelo catálogo CKAN e lê o CSV **em fluxo**,
   parando na primeira linha de outra data. Na web, com
   `--dart-define=TESOURO_PROXY_URL=...`, pergunta à função `tesouro`.
2. **A função `tesouro`** mora em `functions/index.js`, ao lado da `brapi`, com
   a mesma lista de origens. Lê o mesmo começo de arquivo no servidor e devolve o
   formato de `TreasuryQuotesCodec`. Conferida contra o arquivo real: 11 títulos
   prefixados da data-base de 10/09/2026, em 433 ms. **O deploy é do usuário.**
3. **Recuo, em ordem**: sem a curva do dia, o pacote `assets/tesouro/curva.json`
   com as dez datas-base mais recentes do build; sem data-base de até sete dias
   em nenhum dos dois — a regra de `TreasuryCurve.at` —, a cascata recua para os
   dois pontos do CDI, e o aviso da avaliação diz qual caminho usou.
4. A busca do dia vale **pelo dia**: falha não fica guardada, e o aplicativo
   aberto de um dia para o outro busca de novo.
5. Leitor do CSV e formato do pacote descem para o núcleo (`TreasuryCsv`,
   `TreasuryQuotesCodec`): ferramenta, aplicativo e — pelo formato — função
   concordam.

## Efeito medido

Em 14/09/2026, na mesma execução, com o divisor oficial da decisão 83 já
aplicado (`tool/padrao_ligar.dart`):

| | dois pontos | curva |
|---|---:|---:|
| avaliados | 128 | 128 |
| perdidos / ganhos | | AMER3, EVEN3 / CSAN3, KLBN4 |
| potencial mediano | −28,7% | **−46,0%** |
| mediana do `\|Δ\|` | | 12,9% |
| correlação de postos | | **0,929** |

O mesmo que a decisão 74 mediu: **o nível cai e a ordenação quase não muda.**

## Consequências aceitas

Até o deploy da função, o aplicativo web usa a curva do pacote, que vale por uma
semana depois do build e então cede aos dois pontos — declarado.

A leitura direta depende de o Tesouro manter a ordem decrescente do arquivo. Se
mudar, a leitura encontra várias datas logo nas primeiras linhas, fica com a
primeira, e a curva pode sair de uma data antiga — que `TreasuryCurve.at` recusa
por ter mais de sete dias.
