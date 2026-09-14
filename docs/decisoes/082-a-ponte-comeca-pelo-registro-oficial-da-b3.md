---
numero: 82
titulo: A ponte ticker↔CNPJ começa pelo registro oficial da B3
status: aceita
origem: parecer
data: 2026-09-14
afeta:
  - packages/equisim_core/lib/src/services/cvm/cvm_bridge.dart
  - packages/equisim_core/test/cvm_bridge_test.dart
  - tool/cvm_ponte.dart
  - tool/b3_companhias_baixar.py
  - docs/validacao/ponte_cvm.json
substitui: []
---

## Contexto

A ponte do item A1.1 liga ticker a CNPJ por quatro regras inferidas — código de
negociação da FCA, raiz de quatro letras, nome idêntico e tabela declarada — e
acertava 371 de 375. **Duas das 371 estavam erradas**, e o erro só apareceu
quando a [decisão 81](081-a-base-de-patrimonio-e-o-pl-da-cvm.md) passou a ler o
PL da CVM:

- **MBRF3** estava ligada à **BRF**. A Marfrig incorporou a BRF em 2025 e virou
  MBRF; a fonte de preços manteve o nome "BRF S.A." no ticker novo, e a regra de
  nome casou com a empresa absorvida. A série de mercado da MBRF3 é da Marfrig —
  contagem de 347 a 711 milhões de ações —, e a CVM que entrava era da BRF.
  Desde o A1.7, a montagem com a CVM da MBRF3 misturava o resultado de uma com o
  patrimônio da outra.
- **AUAU3** estava ligada à **Petz** pelo nome "Pet Center", quando o emissor é
  a União Pet, que a incorporou.

As duas são fusões de 2025, e as duas regras que as erraram são **inferidas**.
Nenhuma medição interna as denunciava.

## A fonte que resolve

O registro de empresas listadas da B3 (item A3.1) traz, por emissor de quatro
letras, o **código CVM**; os metadados das DFPs e ITRs ligam código CVM a CNPJ.
É ponte **declarada**, e é a única que acompanha fusão, porque o emissor
registrado na B3 é o que negocia hoje.

Conferida contra a do A1.1 em 14/09/2026: **369 de 371 iguais**, e as duas
diferentes são exatamente MBRF3 e AUAU3.

## Decisão

A regra 0 de `CvmBridge.resolver` é o registro oficial, depois do veto de
`semPonte` e antes das quatro inferidas. `tool/cvm_ponte.dart` o monta de
`data/b3/companhias` e dos metadados de DFP e ITR, e declara no relatório quais
tickers ele corrigiu.

A ingestão e o pacote da CVM foram refeitos sobre a ponte corrigida.

## Consequências aceitas

O registro só cobre emissor listado hoje: a ponte de companhia deslistada
continua inferida, e é assunto do item A3.2.

A MBRF3 passa a ter a história da Marfrig na CVM, que é coerente com a série de
preço dela. A da BRF, até 2025, deixa de entrar em ativo nenhum do universo.
