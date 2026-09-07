---
numero: 26
titulo: O horizonte de convergência do upside passa de 12 para 36 meses
status: aceita
origem: orientador
data: 2026-09-07
citacao: >
  Declarar explicitamente em docs/decisoes/ a superação do horizonte de 12
  meses da Decisão 014 pela Decisão 025 (H = 36 meses).
afeta:
  - packages/equisim_core/lib/src/services/portfolio/expected_return.dart
  - docs/validacao/limitacoes.md
substitui:
  - 14
---

## Contexto

A [decisão 25](025-reconstrucao-do-motor-de-avaliacao.md) homologou `M1 = 36
meses` e o código passou a usar esse horizonte. Mas ela deixou `substitui: []`,
e a **decisão 14** — registrada na tabela congelada do `PLANO_ARQUITETURA.md` —
continuava afirmando 12 meses.

Duas decisões vigentes fixando valores incompatíveis para a mesma grandeza
quebram exatamente o que o registro existe para garantir. A lente `registro` do
conselheiro apontou a divergência em 07/09/2026, e ela procede.

**A citação não foi feita antes por impedimento mecânico, não por descuido.** O
gate local só reconhecia decisões com arquivo em `docs/decisoes/`, que começa em
19. Um `substitui: - 14` disparava `L14 DECISION_DANGLING_REF` e bloqueava o
commit — verificado por execução. O registro tinha, portanto, uma faixa de
decisões que nenhuma decisão nova conseguia derrubar formalmente.

## Decisão

**O horizonte de convergência do *upside* é de 36 meses.** A decisão 14 fica
derrubada nesta grandeza.

O que muda no cálculo: a conversão do potencial total em taxa por período passa
de identidade — com `H = 12` a anualização não fazia nada, e o retorno esperado
era o *upside* cru — para `(1+u)^{1/3} − 1`. Um potencial de −55,1% deixava a
carteira com retorno esperado de −55,1% ao ano; agora sai como −23,4% ao ano.

**O gate passou a ler as decisões 0–18 da tabela congelada.** A correção é em
[`scripts/qa-local.mjs`](../../scripts/qa-local.mjs), com o motivo escrito no
código: `decisoesDoPlanoCongelado()` extrai os números das linhas de tabela do
`PLANO_ARQUITETURA.md`, e `substitui` volta a alcançar a faixa antiga.
Conferido por execução nos dois sentidos — `- 14` passa, `- 77` continua sendo
recusado.

## Consequências aceitas

- **O horizonte continua sendo premissa, e das fortes.** Nada garante que o
  preço convirja ao valor justo, nem em 36 meses nem em prazo nenhum. O que
  muda é que a premissa fica explícita em vez de embutida numa identidade.
- **Todo número de meta já apresentado com `H = 12` está desatualizado.** A
  comparação entre execuções de datas diferentes exige conferir o horizonte.
- **A decisão 14 não é apagada.** Ela permanece na tabela congelada como
  registro do que se decidiu em seu tempo; o que esta decisão faz é derrubá-la
  na grandeza que as duas disputam.
- **Esta decisão não abre reconstrução.** Não declara `postura`, e a superfície
  que ela toca segue sob preservação.
