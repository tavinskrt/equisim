---
numero: 50
titulo: Contrato de prazo determinado recusa o excedente perpétuo, e a perpetuidade fica declarada
status: aceita
origem: voce
data: 2026-09-10
citacao: >
  Prossiga com o bloco A, por D8. Mesmo esquema: ao final, reestruture a lista
  necessária para chegar no valuation sem erros conhecidos e motor de
  referência. Ao final, rode as lentes.
afeta:
  - packages/equisim_core/lib/src/services/valuation/concession_sectors.dart
  - packages/equisim_core/lib/src/services/valuation/growth_guards.dart
  - packages/equisim_core/lib/src/entities/valuation.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - tool/concessao.dart
  - docs/validacao/concessao.md
substitui: []
---

## Contexto

O D8 pergunta o que acontece quando a perpetuidade é aplicada a um negócio cujo
direito de operar tem data para acabar. Quinze dos 120 avaliados são assim:
transmissão, distribuição, saneamento, rodovia, ferrovia.

**O prazo não é publicado**, e o estimador que parecia servir não serve:
`(imobilizado + intangível) ÷ D&A` dá 6,3 anos para a TAEE11, cujas outorgas
vão a 2042, e 14,3 anos para a WEGE3, que não tem concessão alguma. Ele mede
giro da base de ativos. Ver [concessao.md](../validacao/concessao.md).

**E o tamanho do erro é menor do que parece.** Truncar a perpetuidade em dez
anos deixaria o preço justo mediano dos expostos em 0,80 do publicado; em
vinte, 0,90. A taxa de equilíbrio deles está entre 9% e 13%, e a essa taxa a
cauda além do vigésimo ano vale pouco.

## Decisão

**A perpetuidade fica como está, e a suposição passa a ser declarada.** Sem o
prazo não há horizonte a impor, e arbitrar um seria trocar uma premissa
explícita por um número inventado. O resultado ganha a ressalva
`prazoDeterminado` e um aviso que diz o que se supõe, por que não se corrige, e
quanto isso pode valer.

**O excedente de retorno perpétuo é recusado.** Contrato de prazo determinado
entra como bloqueio nomeado — `MoatBlock.prazoDeterminado` — na mesma lista que
histórico curto e crescimento inorgânico já ocupam.

A razão é que essa é a única afirmação que o contrato contradiz **diretamente**:
uma concessão é relicitada, e a tarifa é fixada por regulador para remunerar o
capital ao custo dele, não acima. O terminal neutro da
[decisão 25](025-reconstrucao-do-motor-de-avaliacao.md), `ROIC_∞ = WACC`, é
exatamente o modelo certo para esse negócio.

**A classificação é declarada, não inferida**, como a de
[`CyclicalSectors`](../../packages/equisim_core/lib/src/services/valuation/cyclical_sectors.dart):
as chaves `saneamento` e `infraestrutura`, e os termos de subsetor
`energia eletrica`, `agua e saneamento`, `exploracao de rodovias`,
`transporte ferroviario`, `aeroportu` e `concessao`, comparados sobre o rótulo
normalizado.

## Consequências aceitas

**Dois preços justos mudam: CPFE3 −5,8% e TAEE11 −2,5%.** Os outros três que
tinham a bandeira ligada já preservavam `λ` nulo — a diferença entre
`moatApplied` e `λ` que a
[decisão 36](036-decaimento-medido-do-excedente-na-perpetuidade.md) criou para
expor exatamente isto.

**A CPFE3 preservava 26% do excedente para sempre** numa distribuidora
regulada. É o caso que justifica a decisão sozinho.

**Petróleo fica de fora**, embora exploração também seja concessão: ali não há
tarifa nem relicitação de serviço público, e a reserva se esgota. É outro
problema, e tratá-lo junto misturaria dois regimes.

**Geradora em regime de cotas e transmissora com receita anual permitida são
tratadas igual**, e não são a mesma coisa. Separá-las exige subsetor mais fino
que o publicado.

**A reversão indenizada não é modelada.** Ao fim da concessão o investimento não
amortizado costuma ser indenizado, o que é valor terminal positivo. Modelar o
prazo sem modelar a indenização trocaria um viés por outro — e é mais uma razão
para não truncar às cegas.

**A alternativa descartada** era adotar um prazo padrão por setor — trinta anos
para transmissão, trinta e cinco para saneamento. Recusada porque seria
parâmetro sem medição, exatamente o que a
[decisão 35](035-dcf-reverso-e-regressao-condicional.md) veda: o motor passaria
a ter um número que ninguém observou governando metade do valor de quinze
ativos.
