---
numero: 90
titulo: A contagem de ações por data vem do Formulário de Referência, em três camadas, e o evento declarado se localiza no preço
status: aceita
origem: voce
data: 2026-09-14
citacao: >
  Vamos finalizar os últimos 4 itens, de A3.4 até A6.
afeta:
  - packages/equisim_core/lib/src/services/cvm/share_count_history.dart
  - packages/equisim_core/lib/src/services/b3/corporate_events.dart
  - packages/equisim_core/lib/equisim_core.dart
  - packages/equisim_core/test/share_count_history_test.dart
  - tool/cvm_baixar.py
  - tool/cvm/csv.dart
  - tool/b3/proventos.dart
  - tool/b3_complemento_baixar.py
  - tool/b3_deslistadas_contagem.dart
  - docs/validacao/b3_contagem_por_data.md
  - docs/validacao/b3_contagem_por_data.json
substitui: []
---

## Contexto

O item A3.4 do plano: para as 164 companhias deslistadas da ponte do A3.2, a
série de preço ajustada por evento e a contagem de ações por data, com a escala
conferida. É o que falta para as coortes incluírem as deslistadas (C1b) e para a
validação exercitar a ponte por papel, que colapsa para `u = 1` sob a reescala
do backtest (limitações §3.5, item C3).

O critério pedia a escala conferida "contra o valor de mercado de uma data
conhecida". **Companhia deslistada não tem valor de mercado publicado**: a fonte
de preços não a cobre, e o registro da B3 é só de emissor listado.

## Decisão

1. **A contagem vem do Formulário de Referência**, que declara o capital
   integralizado com a data de aprovação e os eventos de ações com a contagem
   antes e depois, de 2010 a 2026. `ShareCountHistory` monta a série em três
   camadas: cada aprovação de capital pela contagem da **primeira** declaração
   dela; cada evento declarado na data ex, com a contagem de depois; e o
   formulário que a série não explica na data de recebimento. A primeira versão,
   que lia a declaração mais recente, levava a contagem de depois de um
   grupamento para antes dele — a CPFL Transmissão saía com P/VPA de 0,01.
2. **O evento declarado se localiza no preço.** A data de aprovação não é a data
   ex: `CorporateEvents.locate` procura, até um ano depois, o pregão em que o
   fechamento se divide pelo fator, com a folga da inferência; bonificação
   pequena sai pela troca do número de distribuição, e fator longe de 1 aceita a
   troca de distribuição com a razão a 25% do fator — o grupamento de papel em
   crise acontece no dia em que ele despenca. Onde o FRE não declara, vale a
   inferência pelo preço da decisão 75. **Evento com pregão e sem data ex fica
   marcado por papel**, para a coorte que o atravessa sair.
3. **A escala é conferida de três jeitos**, no lugar do valor de mercado que não
   existe: nas listadas, a contagem do FRE contra a oficial da B3 — é o que valida
   o método —; nas deslistadas, contra a composição do capital do DFP e do ITR da
   mesma data, contando como igual a diferença de exatamente mil vezes da escala
   do declarante (decisão 70); e o P/VPA no fim de cada exercício, que um erro de
   mil vezes tira de qualquer faixa plausível.
4. **Os proventos das deslistadas vêm pelo nome de pregão**, que a consulta da B3
   aceita para companhia que saiu da bolsa, conferidos pelo preço com direito
   contra o COTAHIST do papel.
5. **O resultado é dado de validação**, em `data/b3/deslistadas_contagem.json`,
   e não entra no aplicativo: companhia deslistada não se avalia hoje.

## Consequências aceitas

**Os números** (ver [b3_contagem_por_data.md](../validacao/b3_contagem_por_data.md)):

| conferência | resultado |
|---|---:|
| listadas, FRE contra a B3, a 1% | 281 de 291 |
| deslistadas com contagem por data | 160 de 164 |
| FRE contra a composição do capital, a 2% | 1.619 de 1.848 |
| P/VPA entre 0,02 e 50 | 860 de 867 |
| eventos com pregão na aprovação e não localizados | 22 |
| proventos com preço com direito batendo com o COTAHIST | 1.753 de 1.779 |

**12% das datas divergem entre os dois formulários da CVM**, e a série não diz
qual está certo: companhias em recuperação, fusões e defasagem em torno de
aumento de capital. A conferência fica gravada por data, para a coorte poder
exigir concordância.

**O quadro de eventos do FRE parou em 2023.** Evento de 2024 em diante entra pela
correção do formulário, na data de recebimento, e não na data ex.

**Ligar a contagem às coortes é o C1**, da Fase 2 — este item entrega o dado, e
não a medição.
