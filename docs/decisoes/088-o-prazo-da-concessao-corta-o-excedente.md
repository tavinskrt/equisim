---
numero: 88
titulo: O prazo da concessão corta o excedente sobre o capital no fim do contrato, e encurta a projeção quando acaba dentro dela
status: aceita
origem: voce
data: 2026-09-14
citacao: >
  Vamos finalizar os últimos 4 itens, de A3.4 até A6.
afeta:
  - packages/equisim_core/lib/src/services/cvm/fre_concessions.dart
  - packages/equisim_core/lib/src/services/valuation/dcf.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - packages/equisim_core/lib/equisim_core.dart
  - packages/equisim_core/test/fre_concessions_test.dart
  - packages/equisim_core/test/concession_horizon_test.dart
  - lib/data/repositories/concession_term_repository.dart
  - lib/di/providers.dart
  - lib/presentation/valuation/valuation_providers.dart
  - assets/cvm/outorgas.json
  - tool/cvm_baixar.py
  - tool/cvm/csv.dart
  - tool/fre_outorgas.dart
  - tool/padrao_ligar.dart
  - test/data/b3_tesouro_package_asset_test.dart
  - docs/validacao/outorgas.md
substitui: []
---

## Contexto

O item A6 do plano, e as limitações §2.16: quinze concessionárias com valor
terminal perpétuo. A [decisão 50](050-concessao-nao-preserva-excedente.md)
recusou o excedente perpétuo nelas e deixou o horizonte como estava, porque o
prazo não era publicado, e declarou o tamanho: se o contrato acabasse em dez
anos, o preço justo mediano iria a 0,80 do publicado. O plano pedia o prazo das
outorgas do Formulário de Referência, com a indenização do investimento não
amortizado.

## Decisão

1. **O terminal da concessão com prazo é o capital mais o excedente até o fim do
   contrato.** O terminal neutro `lucro_{N+1}/r` recusa o valor do capital novo,
   mas mantém para sempre o excedente do capital existente:
   `capital_N + EVA_{N+1}/r`. O contrato que acaba `m` anos depois da projeção
   paga esse excedente só até lá e devolve o capital — pela amortização, pela
   indenização do não amortizado ou por renovação ao custo de capital:
   `VT = capital_N + EVA_{N+1}·(1 − (1+r)^−m)/r`
   (`DcfAssumptions.contractYearsAfterHorizon`). O capital sai da projeção: o do
   primeiro ano é o lucro dele sobre o retorno, e cada ano soma o reinvestimento.
   Com `EVA = 0` o prazo não muda nada; sem retorno utilizável, o terminal fica
   perpétuo e declarado.
2. **O contrato que acaba antes do fim da projeção a encurta**, e o terminal é o
   capital na data do fim. `ValuationCascade.contractYears` dá os anos até o fim,
   arredondados e nunca abaixo de um; `evaluate` refaz os insumos com esse
   horizonte antes de tudo, porque ele governa a curva, o decaimento do
   crescimento, a convergência do retorno e o ponto fixo das taxas.
3. **Na rota derivada do acionista**, o terminal é o da firma menos a dívida no
   ano N: a dívida sai do capital devolvido.
4. **Só age sobre concessão**, pela classificação de `ConcessionSectors`, e **não
   age sobre contrato já vencido** — o FRE repete contrato renovado com o prazo
   antigo.
5. **O prazo vem do quadro de intangíveis do FRE**, texto livre lido por
   `FreConcessionTerm`: a mediana dos fins das outorgas vigentes no formulário
   mais recente. Entra no pacote `assets/cvm/outorgas.json` só formulário a
   partir de 2020 e com ao menos uma outorga vigente legível.
6. **O aviso diz o que foi feito e o que se supõe**: projeção encurtada até o fim
   do contrato; excedente cortado no fim do contrato depois da projeção; e, sem
   prazo lido, que o terminal supõe o excedente para sempre.

## Consequências aceitas

**A primeira versão desta decisão estava errada, e foi corrigida antes do
commit.** Ela afirmava que o terminal neutro já era o valor do contrato finito,
com um teste que definia o capital como `lucro/r` e tornava a igualdade
verdadeira por construção. A lente `metodo` apontou o excedente do capital
existente, e a álgebra da projeção confirmou.

**O efeito tem sinal.** Na medição final da Fase 1, a correlação de postos fica
em 0,998 e um ativo se move além de 10 p.p.: EGIE3, de +3,6% para −30,5%, com o
capital rendendo acima do custo e a mediana das outorgas em 2033. ALUP11, AXIA3 e
TAEE11 **sobem** de 3 a 5 p.p., porque o capital apurado rende abaixo do custo e
a devolução pelo contábil vale mais que a perpetuidade. Ver
[fase1_padrao.md](../validacao/fase1_padrao.md).

**Sem peso por contrato, a mediana não é o prazo ponderado pela receita.** O caso
frágil é o grupo: a EQTL3 tem a projeção inteira encurtada para dois anos pelas
outorgas de distribuição de 2028 — "prorrogável até 2058" —, embora tenha
transmissão, saneamento e renováveis.

**O quadro de intangíveis parou em 2023.** O formulário mudou de formato em 2024,
e o formulário mais novo com o quadro, nas concessionárias do universo, é de
referência 2022. MOTV3, RAIL3 e SBSP3 não listam concessão no quadro; CMIG4 e
SAPR11 só têm formulário anterior a 2020. Para eles vale o aviso de prazo não
lido.

**A convenção de meio de ano deixa uma diferença de segunda ordem**: o terminal
recebe o levantamento de meio ano, e a devolução do capital, a rigor, não.

**O mesmo excedente perpétuo existe fora das concessões.** Para quem não tem
contrato, `lucro_{N+1}/r` mantém para sempre o retorno acima do custo do capital
que já existe, e isso é premissa, não conta: entra no plano como item de método.
