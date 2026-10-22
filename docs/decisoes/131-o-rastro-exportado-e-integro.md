---
numero: 131
titulo: O rastro que o painel de logs exporta é íntegro — serializável sempre, completo, e emitido por toda saída da avaliação
status: aceita
origem: voce
data: 2026-09-24
citacao: >
  Aproveitando essa janela, garanta também que o painel de logs esteja
  recebendo as informações do motor de valuation de forma íntegra para
  podermos efetuar nossas depurações no json exportado.
afeta:
  - packages/equisim_core/lib/src/audit/calculation_trace.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - packages/equisim_core/test/audit_integrity_test.dart
  - lib/audit/audit_bus.dart
  - lib/data/isolate/valuation_runner.dart
  - lib/presentation/audit/logs_page.dart
  - lib/presentation/valuation/valuation_providers.dart
  - test/presentation/logs_page_test.dart
  - test/data/valuation_runner_test.dart
  - tool/gabarito_cascata.dart
substitui: []
---

## Contexto

O painel de logs recebe o evento que a cascata emite ao fechar a transação de
cada avaliação, e exporta o histórico em JSON para depuração. O usuário pediu
que esse caminho seja íntegro. **Antes de mexer, conferi o caminho inteiro**, do
ponto de cálculo ao arquivo, e ele perdia informação em nove lugares.

**Serialização.**

1. **`jsonEncode` lança diante de `NaN`, de infinito e de objeto que não seja
   mapa, lista, texto, número ou booleano**, e o evento era serializado dentro
   do encerramento da transação. Um valor degenerado numa variável do rastro
   derrubava a exportação e, dentro da transação, a própria avaliação.
2. **O arredondador do rastro transformava `NaN` e infinito em `0`.** O sinal
   de que uma conta degenerou aparecia como zero, que é o valor mais enganoso
   possível numa depuração.

**Completude.**

3. **O evento registrava 5 dos 19 campos do diagnóstico**, e nem a volatilidade
   que a tela usa para montar a faixa calibrada, nem a triangulação por
   múltiplos. Pelo JSON não dava para reproduzir a faixa nem a segunda leitura
   que a tela mostra.
4. **A entrada registrava preço, CAPM e seis exercícios**, sem dizer que tinha
   resumido, e sem a curva, a contagem oficial, a composição da unit, o prior do
   beta, os múltiplos de pares e as imposições de diagnóstico — tudo o que muda
   o preço justo.
5. **As ressalvas de contexto** — CVM ausente ou defasada, curva que faltou,
   prior indisponível — eram acrescentadas pela tela **depois** da avaliação: a
   tela as mostrava, e o arquivo exportado não as tinha.

**Emissão.**

6. **Uma exceção no meio da cascata deixava a transação aberta**, e o painel
   não recebia nada.
7. **A falha de preparo** — sem exercícios, sem cotação — acontece antes da
   cascata e não deixava evento: o painel não tinha como dizer por que um ativo
   não foi avaliado. No gabarito, são 14 dos 376 ativos.
8. **A avaliação que migra de isolate** — Monte Carlo com 20 mil sorteios ou
   mais, fora do web — rodava com o coletor desligado, que é estático e local à
   isolate, e saía sem evento.

**Histórico e exportação.**

9. **O anel do histórico era um só, de 200**, e descartava o mais antigo em
   silêncio: numa carteira de quinze ativos, o ruído de rede empurrava para fora
   as avaliações. A exportação também não registrava a busca digitada, e um
   arquivo filtrado parecia o histórico inteiro. E a classificação entre
   cálculo e rede era pela presença de passos, de modo que a avaliação recusada
   antes do primeiro passo aparecia como ida à rede.

## Decisão

1. **`AuditJson.safe`** converte no JSON o que ele não representa — `NaN` e
   infinito em texto de mesmo nome, data em ISO-8601, enum em nome, o resto em
   `toString` — e passa o resto intacto. **O JSON de um rastro sem valor
   degenerado não muda um byte**, e um teste cobra isso. A leitura aceita os
   textos de volta como número.
2. **O arredondador passa o não finito como é**, e ele sai no JSON como texto.
3. **O evento de sucesso leva o diagnóstico inteiro, a volatilidade da faixa e a
   triangulação**, e a entrada leva o resto dos insumos, as imposições ativas e
   quantos exercícios o resumo omitiu.
4. **As ressalvas de contexto entram pela cascata** (`contextNotes`), e ficam no
   resultado e no rastro: a tela e o arquivo leem as mesmas.
5. **Uma exceção fecha a transação** com o tipo, a mensagem e o começo da pilha,
   e continua subindo. **A falha de preparo sai no endpoint da avaliação**, com a
   etapa e a fonte que faltou. **O rastro atravessa a isolate**: ela liga um
   coletor próprio e devolve o evento, que esta reemite.
6. **Dois anéis, e descarte contado**: 200 cálculos e 300 eventos de rede, cada
   um descartando o seu mais antigo, com a contagem transmitida à janela do
   painel, mostrada no cabeçalho e gravada no arquivo — que passa a dizer o
   filtro, a busca, o total no histórico e, havendo descarte, que não tem a
   sessão inteira. **A classificação é pela origem** (`/core/`).

## O que foi medido

No gabarito, sobre a entrada congelada: **nenhum preço justo mudou** em nenhuma
das 3.384 avaliações; o rastro mudou nas 3.258 que chegam à cascata, porque a
entrada e a saída do evento cresceram.

## Consequências aceitas

**O evento ficou maior.** A entrada ganhou a curva e os pares, a saída ganhou o
diagnóstico e a triangulação — algumas centenas de bytes por avaliação, contra
um rastro de passos que já passa de dezenas de milhares.

**Os anéis continuam tendo teto.** Uma sessão longa ainda descarta — agora
contando, dizendo e separando o que descartou.

**A exceção dentro da isolate** é o único caso em que o evento não atravessa: o
erro sobe pelo `compute` e continua visível para quem chamou.
