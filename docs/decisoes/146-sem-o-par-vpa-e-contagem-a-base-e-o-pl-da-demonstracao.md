---
numero: 146
titulo: Sem o par VPA e contagem do exercício, a base de patrimônio é o PL da demonstração
status: aceita
origem: voce
data: 2026-10-02
citacao: >
  Maravilha. Pode fazer as 4 medições e fazer o download.
afeta:
  - packages/equisim_core/lib/src/entities/fundamentals.dart
  - packages/equisim_core/test/base_de_patrimonio_test.dart
substitui: []
---

## Contexto

Medindo as estatais (item B46), a Copasa saiu recusada por «patrimônio líquido
não positivo em exercícios consecutivos», com R$ 8,6 bilhões de patrimônio na
DFP de 2025. Conferido o universo, cinco companhias estavam assim — Copasa,
Fleury, Armac, ARND3 e AZTE3 —, todas com patrimônio positivo na CVM. Aberto e
fechado na mesma rodada como **B47**.

A causa: a base de patrimônio da cascata é `VPA × contagem do exercício`. A
[decisão 81](081-a-base-de-patrimonio-e-o-pl-da-cvm.md) passou a derivar o VPA
do PL da CVM — `PL ÷ contagem` —, para que o produto devolvesse o PL da
demonstração exatamente. Mas a contagem continua sendo a da fonte de mercado
(decisão 70), e a fonte devolve, para algumas companhias e alguns exercícios, a
contagem **zerada** e o VPA vazio. Sem contagem não havia por onde dividir, o
produto não se formava, e a ausência virava insolvência na elegibilidade — e,
nas companhias que passavam, um buraco na série de capital: a EGIE3 de 2010 a
2014, a ALOS3 de 2014 a 2018, o BBAS3 em 2023, a AZZA3 em 2020.

## Decisão

**Quando o par VPA e contagem do exercício falta, a base de patrimônio é o PL
da demonstração** (`FundamentalsSnapshot.equityBookValue`).

1. **Com o par, nada muda**: vale o produto, que na série mesclada é o PL da
   CVM exatamente.
2. **Sem o par, vale o PL**, que é grandeza total, sem escala por ação — e é a
   base que a decisão 81 pede.
3. **VPA negativo continua sendo insolvência**: o recuo só vale quando o par
   falta, e não quando ele diz que o patrimônio é negativo. PL negativo também
   continua sem base.

## Efeito medido

Na entrada congelada de 14/09/2026, montagem do aplicativo: a Copasa e a Fleury
passam a ser avaliadas; Armac, ARND3 e AZTE3 continuam recusadas, agora pelo
histórico curto e, a ARND3, também pela liquidez, que já as barravam; a AXIA7
passa a ser recusada pela estrutura de capital; e o preço justo de outras
companhias com buraco na série muda — ALOS3 de R$ 17,61 para R$ 11,70, EGIE3 de
R$ 22,94 para R$ 17,86, AZZA3 de R$ 20,16 para R$ 17,23, BBAS3 de R$ 36,32 para
R$ 39,33. O universo, a faixa calibrada e a habilidade foram remedidos na mesma
rodada (plano, itens B47, C2c e C1).

## Consequências aceitas

- **O PL da fonte de mercado também entra, onde não há CVM.** A fonte o deixa
  nulo no BBAS3 antes de 2020 e o preenche no campo do controlador depois; onde
  ele vem nulo, a base continua ausente, como antes.
- **A contagem zerada da fonte continua zerada** nos outros usos dela; esta
  decisão só fecha a base de patrimônio.
