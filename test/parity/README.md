# Paridade com o motor Dart original

A reconstrução em TypeScript (decisão 152) trocou a linguagem do motor, e não
o método: cada fórmula, limiar, guarda e texto de aviso do núcleo Dart foi
portado 1:1 para `src/core`. Esta pasta é a prova disso, e continua valendo
depois que o Dart saiu do repositório.

## Como o gabarito foi gravado

1. `dart/harness.dart` roda o núcleo Dart **compilado para JavaScript pelo
   dart2js** — a mesma semântica numérica do aplicativo Flutter na web —, com
   `--no-minify` para que os nomes de tipo do rastro de auditoria saiam
   legíveis.
2. A entrada é a dos pacotes versionados de `assets/` (CVM, B3, Tesouro,
   mercado, validação) mais um **mercado sintético determinístico**: Ibovespa,
   cotações com volume, CDI, IPCA e IBC-Br sorteados por `Random(seed)` e
   ancorados no patrimônio publicado de cada companhia. Sintético porque as
   cotações reais vêm da brapi pela rede, e o gabarito tem de se reproduzir
   sem rede.
3. Para cada um dos 371 ativos do pacote da CVM, treze montagens da cascata
   (dois pontos, curva, aplicativo, série ancorada, sem curva, prior
   resolvido, Monte Carlo, via da firma, via do acionista, imposições de
   diagnóstico, margem e horizonte curtos, notas de contexto e o deslocamento
   do nível da taxa livre de risco). Depois, sobre as mesmas avaliações:
   valuation manual com premissas perturbadas, atribuição da divergência e
   DCF reverso nos sete campos, registro do valuation confirmado (ida e volta
   pelo JSON), 80 simulações históricas, metas, alinhamento com a meta pelas
   duas leituras do retorno esperado, concentração setorial, troca entre
   Principal e Reserva, seção transversal e o calendário de dias úteis.
4. `dart/run.cjs` entrega os pacotes ao programa compilado, recebe o que ele
   emite e grava `golden/header.json`, `golden/cascade.json.gz` e
   `golden/services.json.gz`. O rastro de auditoria de cada avaliação —
   3.894 rastros, 58 MB de JSON — entra pela impressão SHA-256 do texto que o
   `jsonEncode` do Dart produziu.

## O que a suíte confere

`cascade-parity.test.ts` refaz a bateria inteira com `oracle.ts`, que é a
tradução linha a linha de `harness.dart` para o núcleo TypeScript, e exige
**igualdade exata**: número com número por `Object.is` (o que distingue
`-0` de `0`), texto com texto, e a impressão de cada rastro.

Na gravação, em 23/10/2026, a comparação deu **zero divergências**: as 4.823
montagens da cascata, os 3.894 rastros byte a byte e todos os serviços.

## Para regravar

O gabarito é a fotografia do motor Dart, e **não se regrava** a partir do
TypeScript: regravar com o próprio port faria a suíte comparar o port com ele
mesmo. Uma mudança de método deliberada, registrada em decisão nova, muda o
gabarito com ela — e a decisão diz quais números mudaram e por quê.

Para refazer a gravação a partir do Dart, restaure `packages/equisim_core` do
commit `3388c0d` e rode, com o SDK do Dart no `PATH`:

```bash
cd test/parity/dart
dart pub get --offline
dart compile js --no-minify -O2 -o build/harness.js bin/harness.dart  # harness.dart em bin/
TZ=UTC node --max-old-space-size=8192 run.cjs build/harness.js ../../.. saida 0
```
