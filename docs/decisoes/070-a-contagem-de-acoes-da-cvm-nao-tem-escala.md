---
numero: 70
titulo: A contagem de ações da CVM não tem escala, e só a fração dela entra
status: aceita
origem: parecer
data: 2026-09-11
afeta:
  - packages/equisim_core/lib/src/entities/fundamentals.dart
  - tool/cvm_ligar.dart
  - docs/validacao/limitacoes.md
substitui: []
---

## Contexto

O `composicao_capital` da CVM publica `QT_ACAO_TOTAL_CAP_INTEGR` e
`QT_ACAO_TOTAL_TESOURO`, e foi o que revelou que **62% do universo tem ação em
tesouraria** — item A1.5, e defeito que o motor não tratava porque a fonte
anterior não publicava o campo.

Ao ligar a ingestão ao motor, a contagem absoluta entrou como
`sharesOutstandingAsOf` e como base de `bookValuePerShare`. O resultado foi
imediato e absurdo: **a MILS3 saiu com +14.037,7% de potencial**, que é
precisamente o falso desconto que a regra do maior da
[decisão 66](066-a-regra-do-maior-e-confirmada-por-contrafactual.md) existe
para barrar.

A causa, medida sobre **2.081 pares comparáveis** contra a contagem da fonte de
mercado:

| escala do campo da CVM | exercícios |
|---|---:|
| unidades | **60,9%** |
| **milhares** | **34,5%** |
| outra | 4,7% |

A ABEV3 aparece com 15.757.657 contra os 15.761.638.000 papéis reais; a MILS3,
com 234.178 contra 234.178.210. **Nenhum campo do arquivo declara qual é**, e a
escala varia por declarante — não por ano, não por setor.

## Decisão

A contagem **absoluta** da CVM não entra no motor. Entra a **fração**
`tesouraria ÷ integralizadas`, que é invariante de escala porque as duas saem
do mesmo registro e erram juntas.

`FundamentalsSnapshot.treasuryFraction` carrega essa razão, e
`sharesNetOfTreasury` a prefere sobre a contagem absoluta. A base sobre a qual
ela é aplicada continua sendo a da fonte de mercado — que a §1.7 mediu como
reproduzindo o patrimônio publicado em **4.461 de 4.462** exercícios.

## Consequências aceitas

**Perde-se a contagem primária.** Seria melhor ter a contagem da fonte
original; ficamos com a do agregador, cuja qualidade já estava medida e é boa.
Recuperá-la exigiria inferir a escala por comparação — o que é possível, e não
foi feito porque inferir escala é adivinhar, e adivinhar contagem de ações é
como o MILS3 chegou a +14.000%.

**A tesouraria fica sem tratamento onde a fração não se apura**: exercício sem
`composicao_capital`, ou com tesouraria maior que a base integralizada, que é
registro corrompido.

**O defeito só apareceu porque a ligação foi medida contra o estado anterior.**
Ele passou pelo `dart analyze`, pelos 474 testes e pelo gate — nenhum deles
tinha como saber que 234.178 não é a contagem da MILS3. Quem pegou foi a
comparação antes-depois, e é ela que deve acompanhar toda troca de fonte.
