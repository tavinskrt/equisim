---
numero: 101
titulo: O registro declara as substituições parciais que os campos não marcaram
status: aceita
origem: voce
data: 2026-09-15
citacao: >
  Reforce a validação da implementação realizada com a execução das lentes e
  correção dos problemas apontados por elas.
afeta:
  - docs/decisoes/README.md
substitui:
  - 27
  - 23
---

## Contexto

A lente `registro` apontou, em 15/09/2026, que decisões posteriores mudaram
parâmetros de decisões anteriores **sem marcar `substitui`**, e que a cadeia só
existe na prosa. Conferido no código, o achado procede em dois pontos:

- **O limiar Φ do moat.** A [decisão 27](027-recalibragem-apos-a-primeira-validacao.md)
  homologou "manter Phi <= 0,35"; a [decisão 28](028-travas-de-ciclo-saturacao-e-saude.md),
  do mesmo dia e do mesmo orientador, elevou-o a 0,60 "para acomodar concessões e
  estrutura de bancos". O código aplica 0,60
  (`GrowthGuards.moatMaxExternalCapital`), e a 28 tem `substitui: []`.
- **O provento.** A [decisão 23](023-remocao-de-proventos.md) tirou provento do
  projeto; a [decisão 89](089-proventos-voltam-como-dado-conferido.md) o reabriu
  como **dado conferido de validação** — retorno total nas coortes e no beta —, e
  também tem `substitui: []`. A simulação da carteira, a cascata e o retorno
  esperado continuam de preço, como a 23 quis.

**Decisão aceita não se edita** ([README de decisões](README.md)): a correção não
pode ser acrescentar o campo nos arquivos de 28 e 89. O mecanismo que o registro
oferece é este: uma decisão nova que declare o que ficou para trás.

## Decisão

**Fica declarado, para efeito de registro:**

1. O limiar Φ que governa o moat é **0,60**, da decisão 28. O "manter Phi <= 0,35"
   da decisão 27 **não vale mais**, e é o único ponto dela derrubado — o resto da
   27 (multiplicador de rentabilidade, histórico mínimo de oito anos, preço justo
   pelo DCF, retorno esperado desacoplado da taxa crua) continua valendo.
2. O provento é **dado conferido de validação**, da decisão 89, e não crédito de
   simulação. É o único ponto da decisão 23 derrubado: a simulação da carteira, a
   cascata de avaliação e o retorno esperado seguem de preço, como ela decidiu, e
   estendê-lo a qualquer um deles exige decisão nova.

O campo `substitui` desta decisão cita as duas derrubadas parciais — 27 e 23 —,
que é onde a cadeia passa a ser navegável a partir do registro, e não da prosa.

## Consequências aceitas

**Uma decisão de escrituração não muda número nenhum.** Nada no código muda: o
código já faz o que esta decisão declara. O que muda é que quem lê a 27 ou a 23
chega aqui pelo campo, e não por memória de quem participou.

**O `substitui` passa a valer para derrubada parcial.** O README trata o campo
como "números que esta decisão derruba"; a prática até aqui o deixava vazio quando
a derrubada era de um ponto só. O critério que fica: **quem muda um parâmetro que
outra decisão fixou cita essa decisão no campo**, mesmo que só naquele ponto, e
diz no corpo o que sobra em pé.

**As duas decisões citadas continuam como estão**, com o corpo e o `status:
aceita` que têm. Marcá-las de outro jeito exigiria editá-las, que é o que o
registro proíbe — e o que esta decisão existe para evitar.

**O inventário não foi exaustivo.** A lente `registro` só alcança as decisões até
a 30, e este registro fecha os dois pontos que ela apontou e que o código
confirmou. Outras derrubadas parciais podem existir entre a 31 e a 100; quando
aparecerem, o caminho é o mesmo.
