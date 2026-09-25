---
numero: 133
titulo: A réplica fora da amostra começa selada — três coortes, o motor pré-registrado identificado pela impressão, e a leitura travada até a data
status: aceita
origem: voce
data: 2026-09-24
citacao: >
  Após realizar a leitura do documento plano-motor-de-referencia.md
  atualizado, aprovo a execução do C7. Vamos decidir o que fazer com o C8
  depois.
afeta:
  - tool/c7/protocolo.dart
  - tool/c7_selar.dart
  - tool/c7_leitura.dart
  - tool/backtest_valuation.dart
  - tool/regressao_condicional.dart
  - test/tool/c7_test.dart
  - docs/validacao/c7/
  - .gitignore
substitui: []
---

## Contexto

A [decisão 129](129-o-r3-nao-passa-e-o-teste-declara-o-poder-que-tem.md)
pré-registrou a réplica fora da amostra (item C7): as coortes trimestrais a
partir de 31/12/2025, o critério da decisão 96 sobre o potencial condicionado ao
book-to-market, leituras em 30/09/2029 (12 meses) e 30/09/2031 (36 meses), e
duas proibições — juntar as coortes antigas às novas e trocar a ordenação
principal depois de ver as novas. Ela disse **o quê** e **quando**. Não disse
**como** garantir que a previsão lida em 2029 seja a que existia antes do
desfecho.

Sem esse como, o pré-registro vale pouco. Até 2029 o motor muda, a base é
refeita, e um backtest rodado na data da leitura **refaz** as previsões de
2025 com o motor e os dados de 2029. A leitura mediria outra coisa, e ninguém
conseguiria dizer o quê.

## Decisão

1. **A previsão é selada, e o selo nunca é reescrito.** Para cada coorte, um
   arquivo em `docs/validacao/c7/` guarda as previsões de todos os ativos:
   preço, justo, potencial, modelo, recusa e os sinais das cinco ordenações.
   **Nenhum campo de desfecho entra nele.** O hash do git de cada arquivo fica
   no índice. Selar de novo uma coorte já selada refaz as previsões, compara com
   o selo e relata a divergência, mas não mexe no selo. Um selo alterado depois
   de selado interrompe tudo. **A prova de quando foi selado é o commit do
   arquivo.**
2. **O motor é identificado pela impressão, e não pela data.** A impressão é o
   hash do git de cada fonte de `packages/equisim_core/lib`, num manifesto
   ordenado, e o hash do manifesto. É o hash que o git dá aos blobs, então a
   impressão de um selo pode ser reencontrada em qualquer commit.
3. **O motor pré-registrado é o da primeira selagem**, e ela é esta. A decisão
   129 falava do motor «desta data», 22/09/2026, e o desta selagem é o de
   24/09. **Os dois diferem só no rastro de auditoria e nas cópias dos
   insumos** (decisões 131 e 132). No gabarito, 376 ativos em nove montagens
   sobre a entrada congelada, **nenhum campo muda** além do rastro e dos avisos
   das montagens de diagnóstico: nem preço justo, nem modelo, nem recusa, nem
   diagnóstico. O motor de 22/09 está no commit `e1a843d`, e a afirmação pode
   ser conferida.
4. **Motor novo sela numa segunda série**, «motor da data». Ela não substitui a
   pré-registrada. Para a leitura de 2029, a série pré-registrada das coortes
   ainda não seladas sai de um `git worktree` do commit que o índice registra.
   Essa é a leitura com as duas versões que a decisão 129 pede.
5. **A leitura é travada até a data.** Antes de 30/09/2029 (12 meses) e de
   30/09/2031 (36 meses), `tool/c7_leitura.dart` só diz quantas coortes estão
   seladas e quantas já têm o horizonte completo, **sem estatística nenhuma**.
   Na data, aplica a mesma função que mede o R3 (`horizonteDaHabilidade`) às
   previsões **seladas**, com os retornos de um backtest `--c7` refeito com a
   base de então. Observação anterior a 31/12/2025 faz a leitura recusar, e
   não filtrar em silêncio.
6. **O backtest ganha o modo `--c7`**: só as coortes a partir de 31/12/2025,
   gravadas fora do versionamento (`data/c7/`), e `--fim-dos-dados` para dizer
   até onde a base vai. A selagem lê dali.
7. **Selar a cada trimestre fechado**, logo depois da coorte, é o que dá valor
   ao selo. O procedimento está no cabeçalho de `tool/c7_selar.dart`.

## O que foi selado

Em 24/09/2026, com o COTAHIST e a CVM até 04/09/2026, pelo backtest
`--c7` refeito na mesma execução que regerou o backtest principal:

| coorte | observações | avaliadas | deslistadas |
|---|---:|---:|---:|
| 31/12/2025 | 344 | 93 | 14 |
| 31/03/2026 | 338 | 96 | 10 |
| 30/06/2026 | 336 | 95 | 6 |

**Nenhuma observação traz retorno.** Com a base terminando em 04/09/2026,
nenhuma coorte tem 12 meses, e a trava do selo recusaria qualquer campo de
desfecho.

O motor pré-registrado tem a impressão `689fad50738defa82c1665853b79bc06651df1d4`, sobre o commit
`e1a843d` com a árvore do núcleo alterada. A primeira leitura, de 12 meses,
abre em 30/09/2029.

## Consequências aceitas

**As três primeiras coortes são seladas 9, 6 e 3 meses depois da data.** O
desfecho de 12 meses de nenhuma delas existe ainda. Parte do caminho já
aconteceu, mas nenhuma decisão do motor olhou para elas: a decisão 129 fixou a
amostra justamente por isso. A partir da próxima coorte, 30/09/2026, o selo
pode vir logo depois do fechamento do trimestre.

**O motor pré-registrado não é o de um commit limpo.** Ele é a árvore de
trabalho sobre `e1a843d`, e o índice diz isso (`arvoreLimpa: false`). O commit
que contém a impressão é o seguinte a `e1a843d` que tocar o núcleo, e a
impressão o identifica sem ambiguidade.

**O poder continua baixo**, como a decisão 129 já tinha dito: 12 coortes em
2029. A selagem não aumenta o poder. O que ela garante é que o resultado,
positivo ou negativo, seja da réplica e não de um reajuste.
