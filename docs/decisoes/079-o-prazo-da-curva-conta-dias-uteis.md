---
numero: 79
titulo: O prazo da curva conta dias úteis da liquidação, pelo calendário conhecido na data-base
status: aceita
origem: parecer
data: 2026-09-14
afeta:
  - packages/equisim_core/lib/src/time/brazilian_calendar.dart
  - packages/equisim_core/lib/src/services/valuation/yield_curve.dart
  - packages/equisim_core/lib/src/services/b3/corporate_events.dart
  - packages/equisim_core/lib/src/services/cvm/cvm_document_codec.dart
  - packages/equisim_core/lib/equisim_core.dart
  - packages/equisim_core/test/brazilian_calendar_test.dart
  - packages/equisim_core/test/yield_curve_test.dart
  - docs/validacao/curva_de_juros.md
substitui: []
---

## Contexto

A auditoria do gate, sobre o staging da rodada de A1.8 a A3, reprovou com
quatro achados.

**O que pesava: o prazo da curva em dias corridos** (regra R9). A
[decisão 74](074-a-taxa-livre-de-risco-segue-a-curva-observada.md) montou os
vértices com `dias corridos ÷ 365,25`, e declarou isso como aproximação de
"fração de ponto base no fator". A taxa do Tesouro é efetiva anual na base de
**252 dias úteis** — `PU = 1000 ÷ (1 + taxa)^(du ÷ 252)` —, e a declaração não
tinha sido medida.

**Os outros três eram a regra R6**: `double` como chave de mapa na
deduplicação de vértices, como elemento de `Set` na lista de fatores de evento,
e comparado por igualdade no codec do pacote da CVM. Nenhum produzia número
errado hoje; a regra existe para que não passem a produzir.

## A conferência

O arquivo do Tesouro traz taxa e PU, e o `du` implícito sai de
`252 · ln(1000 ÷ PU) ÷ ln(1 + taxa)`. Sobre as **19.171 cotações de LTN desde
2010**:

| convenção | `du` exato |
|---|---:|
| dias úteis da data-base, calendário de hoje | 7,6% |
| da liquidação (D+1), calendário de hoje | 83,9% |
| **da liquidação, calendário conhecido na data-base, sem liquidar em 24/12 e 31/12** | **99,13%** |

As duas regras que a conferência ensinou:

1. **O calendário é o conhecido na data.** O 20 de novembro virou feriado
   nacional pela Lei 14.759, de 21/12/2023. De 2018 a 2023 o Tesouro contava um
   dia útil a mais por ano de vencimento depois de 2024 — a assinatura de quem
   ainda não conhecia o feriado.
2. **O prazo conta da liquidação**, e a B3 não liquida em 24/12 nem em 31/12.

O que sobra, 0,87%, é fronteira de vigência e dia atípico de pregão.

**O efeito, isolado sobre o mesmo arquivo:** em onze datas-base de 2018 a 2026,
o maior deslocamento de forward anual nos anos 1 a 10 foi de **4,7 bp**, e o da
perpetuidade, de **0,4 bp**. A declaração da decisão 74 subestimava o erro no
prazo — mediana de 0,4%, acima de 1% em um vértice a cada dez —, mas o efeito
na taxa que a projeção usa é pequeno.

## Decisão

1. `BrazilianCalendar`, no núcleo: feriados nacionais — os fixos, e Carnaval,
   Paixão e Corpus Christi pela Páscoa —, o 20 de novembro condicionado à data
   de conhecimento, contagem em `[início, fim)` e a liquidação de título
   público.
2. O vértice da curva passa a ser `dias úteis da liquidação ao vencimento ÷
   252`, pelo calendário conhecido na data-base. Os anos da projeção ficam na
   mesma unidade.
3. As três ocorrências da R6 saem: chave inteira em dias úteis, lista em vez de
   conjunto, e tolerância de um bilionésimo de real para gravar valor inteiro no
   pacote — ordens de grandeza abaixo do centavo.

## Remedição

Em 04/09/2026, dentro da mesma execução:

| | dois pontos | curva |
|---|---:|---:|
| avaliados | 128 | 127 |
| potencial mediano | −33,1% | −53,2% |
| mediana do Δ | | −12,2 p.p. |
| correlação de postos | | **0,9174** |

**Não comparar com a tabela da decisão 74 em nível.** A montagem de dois
pontos não usa a curva e mesmo assim foi de −37,6% para −33,1% e de 127 para
128 avaliados entre a manhã e a tarde: é a deriva do dado de mercado entre
sessões — cache vencido, Ibovespa sem cache —, somada à decisão 77. O que a
comparação dentro da execução mostra é o mesmo de antes: **a curva derruba o
nível em cerca de 12 pontos e quase não reordena**.

## Consequências aceitas

O calendário só tem feriado nacional. Feriado atípico de pregão — dia de jogo
do Brasil em Copa, por exemplo — não entra, e é parte do 0,87% que não bate.

Uma lei nova de feriado nacional exige editar o calendário, com a data de
conhecimento dela.
