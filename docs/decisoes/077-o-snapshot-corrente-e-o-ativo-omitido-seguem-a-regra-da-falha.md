---
numero: 77
titulo: O snapshot corrente e o ativo omitido pelo lote seguem a regra da falha
status: aceita
origem: parecer
data: 2026-09-14
afeta:
  - lib/data/datasources/remote/brapi_datasource.dart
  - lib/data/repositories/market_repositories.dart
  - lib/data/repositories/cvm_fundamentals_repository.dart
  - test/data/brapi_datasource_test.dart
  - test/data/cache_repository_test.dart
  - test/data/cvm_fundamentals_repository_test.dart
substitui: []
---

## Contexto

A [decisão 68](068-falha-de-um-demonstrativo-reprova-a-busca.md) fez a falha de
um dos quatro demonstrativos reprovar a busca de fundamentos inteira, porque a
série parcial ia para o cache e sobrevivia à falha. A lente `dados`, na rodada
de A1.8 a A3, apontou que a regra parou nos quatro — e a conferência achou dois
caminhos com o mesmo defeito, e um terceiro de desempenho no código desta
rodada.

**1. O snapshot corrente falhava em silêncio.** Depois dos demonstrativos,
`fundamentalsHistory` busca `/v2/stocks/statistics?mode=current`, que traz o
valor de mercado, a contagem e o EV/EBITDA **de hoje**. Em falha, seguia com
`currentData = null`. A lente descreveu o efeito como "contagem corrente nula".
**É pior:** sem o corrente, cada linha anual fica com os **próprios** três
campos — e o `marketCap` das linhas anuais é o calculado por ações × preço da
unit, que o comentário duas linhas abaixo documenta inflar o SAPR11 de
R$ 10,1 bi para R$ 59,9 bi e o KLBN11 de R$ 23,0 bi para R$ 117 bi. O resultado
era `Ok`, ia para o cache e valia pelo prazo inteiro dele.

Isso importa mais agora do que antes: pela
[decisão 76](076-a-cvm-chega-ao-aplicativo-por-pacote.md), a CVM entra no
aplicativo e **delega ao mercado** justamente esses campos.

**2. O ativo omitido pelo lote perdia o cache.** `PriceRepositoryImpl.dailyBatch`
recorre ao cache vencido quando o lote falha inteiro. Quando o lote **responde**
e deixa um ativo de fora — série corrompida daquele papel, papel que a fonte
deixou de devolver —, o ativo não recebia nem dado novo nem o histórico em
disco: sumia da resposta. A lente descreveu isso como custo de cota; o que o
teste reproduziu foi a perda de dado.

**3. O pacote da CVM era decodificado uma vez por chamada simultânea.**
`CvmFundamentalsRepository` guardava o resultado da leitura, e não a leitura em
curso. `valuationProvider` é uma família, e telas diferentes pedem ativos em
paralelo: quatro chamadas antes da primeira terminar decodificavam os 9 MB
quatro vezes, na thread da interface.

## Decisão

1. **Falha no snapshot corrente reprova a busca**, como a de um demonstrativo.
   Resposta 200 sem dado continua passando — é ausência declarada pela fonte,
   e não falha. O repositório já recorre ao cache vencido diante de `Err`, de
   modo que quem tem histórico em disco não perde a avaliação.
2. **O ativo omitido por um lote que respondeu recorre ao cache vencido**,
   pela mesma razão do lote que falhou.
3. **O repositório da CVM guarda a leitura em curso**, e chamadas simultâneas
   esperam a mesma.

Cada um com teste que falhava antes da correção: 4 leituras em vez de 1, `Ok`
em vez de `Err`, e PETR4 ausente da resposta com 21 pregões em disco.

## O que fica de fora

A segunda metade do achado 2 — **cache negativo**, para que um papel que a
fonte nunca devolve não seja pedido a cada leitura — não entra. Marcar como
fresco um ativo sem dado faria o verificador de validade servir ausência como
se fosse série; exige desenho próprio, e o custo é de cota, não de resultado.

## Consequências aceitas

Uma falha transitória no endpoint corrente passa a produzir `Err` onde antes
produzia série — para quem não tem cache, avaliação nenhuma em vez de avaliação
com valor de mercado de unit inflado. É a troca da decisão 68, pelo mesmo
motivo: número errado com cara de certo é o pior resultado possível.
