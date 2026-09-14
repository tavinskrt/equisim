---
numero: 71
titulo: A validade do cache macro é por série, e a cobertura é por janela
status: aceita
origem: parecer
data: 2026-09-11
afeta:
  - lib/data/repositories/market_repositories.dart
  - test/data/cache_repository_test.dart
substitui: []
---

## Contexto

`MacroRepositoryImpl._series` guarda validade por **série** — uma chave para o
CDI, uma para o IPCA, uma para o IBC-Br — e faz o recorte por **janela**, ao
ler as linhas do intervalo pedido.

As duas coisas não conversavam. Um gráfico que pedisse três meses de CDI
gravava esses três meses e marcava a série como fresca; a simulação de dez anos
que viesse depois via `fresh == true`, lia o cache no intervalo de dez anos,
recebia os **três meses** que lá estavam e os devolvia como se fossem a série
pedida.

**O efeito não é de cobertura, é de número errado.** O CAGR decenal do CDI, a
taxa de equilíbrio da estrutura a termo e o Sharpe sairiam apurados sobre um
trimestre, sem aviso nenhum.

A lente `dados` apontou como achado estrutural.

## Decisão

O caminho normal passa a **exigir cobertura do início**: se a primeira linha em
cache é posterior ao começo da janela pedida, mais uma folga, o cache não serve
e a busca vai à rede.

A folga é de 10 dias na série diária e de 62 na mensal, e acomoda fim de
semana, feriado e o próprio início da série no Banco Central — o IBC-Br não
existe antes de 2003, e pedir 1990 não deve invalidar o cache para sempre.

**A ponta final não é exigida.** Uma série de publicação lenta termina onde o
Banco Central parou, e exigir cobertura até `range.end` derrubaria todo cache
legítimo.

**O caminho degradado não exige nada.** Quando a fonte falha, o recuo para o
cache vencido continua aceitando o que houver: a diretriz da decisão anterior
segue valendo — dado velho em disco é melhor que avaliação nenhuma —, e ali a
alternativa não é um número pior, é número nenhum.

## Consequências aceitas

**Mais idas à rede** quando o aplicativo alterna entre janelas curtas e longas.
O custo é uma requisição ao SGS, que é aberto e sem cota; o benefício é não
apurar dez anos sobre três meses.

A alternativa que a lente propôs — buscar sempre o histórico global e fatiar
depois — resolveria também, e foi descartada por trocar um defeito por um
desperdício: a maioria das consultas quer a janela que pede.
