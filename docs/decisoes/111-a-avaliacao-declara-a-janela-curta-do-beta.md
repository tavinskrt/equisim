---
numero: 111
titulo: A avaliação declara quando o beta saiu de uma janela mais curta que a pedida
status: aceita
origem: voce
data: 2026-09-21
citacao: >
  Seus itens de escopo para esta rodada são B17, B18, B19, B8 e B2.
afeta:
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - tool/backtest_valuation.dart
  - docs/validacao/limitacoes.md
substitui: []
---

## Contexto

A fonte de cotações devolve uma **janela fixa de dez anos**, e o cache da
validação guarda o que ela devolve: a série de qualquer listada começa em
setembro de 2016. A janela do beta é de cinco anos e o mínimo do estimador é de
30 pares — então a coorte de 31/03/2018 estima beta com **383 pregões em vez de
1.240**, e passava sem ressalva.

O efeito é ruído no `Ke` das coortes de 2018 a 2021, que entra no preço justo
delas e, por ele, na medição da habilidade e na da faixa calibrada. **As
deslistadas não têm o problema**: a série delas vem do COTAHIST, que o projeto
tem desde 2010 — as duas metades da amostra não são estimadas na mesma janela.

O item B17 oferecia duas saídas: cobrir a janela pelo COTAHIST também nas
listadas, **ou** declarar a janela curta.

## Decisão

**A avaliação declara a janela curta**, e a cobertura pelo COTAHIST fica para
quando a base bruta voltar (item C5).

1. `PrepareValuationInputs` mede a **extensão da série** que estimou o beta —
   da primeira à última cotação alinhada — e a entrega em
   `ValuationInputs.betaWindowYears`. Extensão, e não contagem de pares:
   feriado e pregão faltando no meio tiram dias, e o que se quer separar é
   série que **não existe** no período.
2. A cascata declara quando a extensão fica abaixo de
   `ValuationCascade.minimumBetaWindowShare` — **80%** da janela pedida. Uma
   série que cobre quatro dos cinco anos é a mesma janela; uma que cobre um ano
   e meio não é.
3. A constante da janela mora na **cascata**, e o preparo a referencia: duas
   cópias divergiriam, e o aviso passaria a medir contra um número que o preparo
   não usa.
4. A coorte grava a janela efetiva (`janelaDoBeta` em
   `backtest_valuation.dart`), para que a medição da habilidade possa separar as
   coortes de janela curta das outras.

## O que foi medido

Sobre a entrada congelada do gabarito, em 21/09/2026: **um dos 103 avaliados**
tem janela curta — a CYRE4, com 0,7 ano de cotação —, e agora diz. O aplicativo
de hoje quase não sofre o defeito, porque pede cinco anos de uma janela de dez;
quem sofre é a coorte datada, e ali a contagem depende do backtest.

## Consequências aceitas

**A contagem nas coortes fica para o C5.** O código que a grava está no lugar; o
número — quantas observações de 2018 a 2021 têm janela curta, e o quanto o `Ke`
delas se move — sai quando o backtest reexecutar. Até lá, a medição da habilidade
e a da faixa continuam carregando o ruído **sem separá-lo**, e a limitação 3.14
continua valendo com esta ressalva a mais: agora ela é visível em cada avaliação,
e não só no registro.

**Declarar não conserta.** O `Ke` de um beta de 383 pregões continua ruidoso; o
que muda é que quem lê o preço justo sabe disso. A correção — a série do COTAHIST
nas listadas, papel a papel, que a montagem da base da data já lê — depende da
base bruta.

**O corte de 80% é declarado, e não medido.** Não há distribuição que o
justifique: ele separa "falta pregão" de "falta série", e a folga de um ano em
cinco é generosa dos dois lados.
