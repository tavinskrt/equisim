---
numero: 52
titulo: Exercício publicado sem demonstração de resultado sai da série, e a recusa passa a nomear a causa certa
status: aceita
origem: voce
data: 2026-09-10
citacao: >
  Prossiga com o item 1 do bloco A. Mesmo esquema: ao final, reestruture a
  lista necessária para chegar no valuation sem erros conhecidos e motor de
  referência. Ao final, rode as lentes.
afeta:
  - packages/equisim_core/lib/src/entities/fundamentals.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - tool/exercicio_vazio.dart
  - tool/recusas.dart
  - docs/validacao/limitacoes.md
substitui: []
---

## Contexto

A composição das recusas — medida por `tool/recusas.dart` — mostrou oito ativos
saindo por "os dados não sustentam nenhuma das duas vias". Um deles é a
**TIMS3**, que não é caso de dado insuficiente: é uma operadora grande, líquida
e lucrativa.

O exercício que o motor usou como base tem `receita = 0`, `ebit = 0`,
`lucro = 0` e `LPA = 0` — **com patrimônio líquido de R$ 24 bilhões no mesmo
balanço**, e EBIT de R$ 4,7 bi dois exercícios antes.

A fonte publica a linha do exercício com o balanço preenchido e a demonstração
de resultado inteira zerada. **O motor lia o vazio como o número zero.**

Medido em 10/09/2026: acontece em 4 dos 376 ativos, em 7 exercícios, e nos
quatro o balanço do mesmo exercício tem valor — prova de que o exercício existe
e de que o que falta é a demonstração, não a empresa.

## Decisão

**Exercício sem demonstração de resultado não entra na série.**
`FundamentalsSnapshot.hasIncomeStatement` é falso quando receita, resultado
operacional, lucro líquido e lucro por ação estão **todos** ausentes ou zerados,
e a cascata filtra por ele logo após o recorte *point-in-time*.

**O teste são os quatro juntos.** Zerar um deles é possível — holding sem
receita, empresa no zero a zero, exercício sem LPA publicado. Zerar os quatro
com balanço preenchido, não. **Prejuízo é resultado publicado** e continua
entrando: ausência e perda não são a mesma coisa.

**A exclusão é declarada**, com a contagem, no resultado.

**Série inteiramente vazia vira recusa que nomeia a causa** — "os exercícios
divulgados vêm sem demonstração de resultado" —, e não mais "os dados não
sustentam nenhuma das duas vias", que culpava o modelo por um dado que a fonte
não entregou.

## Consequências aceitas

**Nenhum preço justo muda.** Os três ativos com o exercício-base vazio já eram
recusados, e o único com vazio no meio da série — BBSE3, em 2012 — tem o
exercício fora de todas as janelas que decidem alguma coisa.

**O ganho é de veracidade e de prospecção, não de número.** A TIMS3 sai de
"nenhuma via aplicável" para "histórico curto demais": com dois dos oito
exercícios descartados sobram seis, e seis é pouco — mas agora a mensagem
descreve o que houve. E na próxima vez que a fonte publicar um exercício vazio
para um ativo em avaliação, a base não sai nula em silêncio.

**A TIMS3 continua sem avaliação**, e por motivo legítimo. O histórico da fonte
para ela começa tarde e a demonstração de resultado para em 2023.

**Um exercício pré-operacional legítimo também sai** — receita, resultado e
lucro genuinamente nulos com balanço montado. É o comportamento certo: não há o
que descontar ali, e a Porta 0 já trata a falta de histórico.

**A comparação é de magnitude, e não de igualdade.** A auditoria pegou o `== 0`
em `double`: o zero da fonte chega às vezes como resíduo de ponto flutuante, e a
igualdade estrita leria `1e-16` como resultado publicado. Os agregados usam o
resíduo de um real que a entidade já declarava; o lucro por ação usa o de um
centavo, porque um LPA de R$ 0,50 é legítimo e o corte dos agregados o
descartaria.

**A alternativa descartada** era descartar a linha inteira na camada de dados,
no repositório. Recusada porque o balanço daquele exercício é real e a base de
capital o usa: jogar fora o patrimônio publicado para corrigir a ausência do
resultado trocaria um dado faltante por dois.
