---
numero: 138
titulo: A série pré-registrada do C7 sai do commit dela, reproduzida ao último dígito, e a leitura traz as duas séries
status: aceita
origem: voce
data: 2026-09-25
citacao: >
  Após realizar a leitura do documento plano-motor-de-referencia.md
  atualizado, aprovo a execução do item B28 e a finalização do C7.
afeta:
  - tool/c7/protocolo.dart
  - tool/c7_preregistrado.dart
  - tool/c7_leitura.dart
  - tool/c7_selar.dart
  - test/tool/c7_test.dart
  - docs/validacao/c7/
substitui: []
---

## Contexto

A [decisão 133](133-a-replica-fora-da-amostra-comeca-selada.md) selou as três
primeiras coortes da réplica e deixou escritas duas coisas que ainda não
existiam:

- **a série pré-registrada das coortes ainda não seladas sai de um `git
  worktree` do commit que o índice registra** — mas nada montava o worktree, e o
  motor pré-registrado nem estava num commit;
- **a leitura traz as duas versões que a [decisão 129](129-o-r3-nao-passa-e-o-teste-declara-o-poder-que-tem.md)
  pede**, a do motor pré-registrado e a do motor da data — mas a leitura lia só
  a primeira.

Esta rodada mudou o motor (decisões 135 a 137 e 139). **A partir de agora a
selagem do trimestre sela a série «motor da data»**, e sem a máquina do
worktree a série pré-registrada das coortes novas não teria de onde sair. O C7
só está em curso de verdade quando a rotina do trimestre roda inteira sem
decisão manual.

## Decisão

1. **O commit do motor pré-registrado é achado pela impressão.** A impressão
   de 24/09/2026, `689fad50…`, entrou no commit `e856ec6`: `commitDaImpressao`
   percorre os commits que tocam o núcleo e devolve o primeiro cuja árvore tem
   essa impressão, calculada pelo `ls-tree` do próprio commit.
2. **`tool/c7_preregistrado.dart` produz a série pré-registrada pelo pipeline
   daquele commit**, e não só pelo núcleo: o motor inclui as ferramentas que
   montam as coortes. Ele monta o worktree fora do repositório, liga a base
   bruta que o git não versiona por junção (`data/b3`, `data/cvm`,
   `data/tesouro`, `data/gabarito`), copia os arquivos que o backtest escreve,
   roda o backtest `--c7` no worktree e sela o resultado com a impressão
   pré-registrada. **A credencial da fonte de mercado vai pelo ambiente do
   processo**, e não por cópia do `.env`: segredo não se espalha em pasta
   temporária.
3. **As coortes que o commit refaz e já estão seladas são conferidas contra o
   selo.** É a prova de que o selo se reproduz, e ela sai a cada trimestre.
4. **O motor desta rodada sela as três coortes na série «motor da data»**, com
   a impressão dele no índice, ao lado da pré-registrada e sem tocá-la.
5. **A leitura traz as duas séries.** `leitura` continua sendo a do motor
   pré-registrado, e é ela que decide o C7. `motoresDaData` traz a mesma conta
   sobre a série de cada motor posterior, **como referência**: mostra o que as
   correções depois do selo fizeram, e não substitui o veredito. A situação,
   antes da data, lista as coortes de cada série.
6. **A rotina do trimestre**, no cabeçalho das ferramentas: o backtest `--c7`,
   `tool/c7_selar.dart` — que sela a série do motor atual, pré-registrada se o
   motor não mudou —, e `tool/c7_preregistrado.dart`, que sela a pré-registrada
   pelo commit dela e confere a reprodução. **Os selos são commitados logo
   depois**: o commit é a prova de quando foram feitos.

## O que foi medido

**O selo se reproduz ao último dígito.** O commit `e856ec6`, num worktree, sobre
a base de hoje, refez as 1.018 previsões das três coortes seladas: **nenhuma
diverge** do selo. A máquina que a leitura de 2029 vai usar é, portanto, a que
produziu o selo.

**O motor da data, de impressão `9b5030dd…`, difere do pré-registrado em 47
das 1.018 previsões, de 23 papéis**, todas explicadas pelas correções da rodada:
o beta dos papéis cuja série a decisão 136 completou — os bancos que bonificam
(ABCB4, BBDC3, BBDC4, ITSA3, ITSA4, ITUB3), POMO3 e POMO4, SLCE3, SHUL4, LREN3 e
outros — e a contagem da DIRR3 pela decisão 137, com o potencial de −62% a −87%
em 31/12/2025. **O capital posterior da decisão 135 não entra em nenhuma**: as
três coortes avaliam balanços de 2024 e 2025, e depois deles o formulário não
declara emissão.

## Consequências aceitas

**A série pré-registrada herda os defeitos que esta rodada corrigiu.** É o que
pré-registrar quer dizer: a réplica mede o motor que existia antes de ver as
coortes novas. As correções aparecem na série do motor da data, lado a lado.

**O worktree depende de a resolução de pacotes daquele commit continuar
possível.** O `pubspec.lock` é versionado e versão publicada não muda no
repositório de pacotes; se um dia isso falhar, a ferramenta para com erro, e
não sela nada.

**A base bruta é a de cada trimestre, e não a de 24/09/2026.** A previsão de
uma coorte nova é feita com o que era público nela — a leitura das versões por
data (decisão 128) cuida da reapresentação —, e o motor pré-registrado a lê como
leria qualquer base.

**O motor da data desta rodada ainda não está num commit.** O índice registra a
impressão com a árvore de trabalho, como na decisão 133, e o próximo commit que
tocar o núcleo a contém.
