---
numero: 91
titulo: Todas as recusas ficam, e o custo da recusa por liquidez é remedido com as deslistadas antes de qualquer soltura
status: aceita
origem: voce
data: 2026-09-14
citacao: >
  Por ora, essa tarefa irá contemplar os itens D1, C2 e C0.
afeta:
  - tool/backtest_valuation.dart
  - tool/cvm/outorgas_por_data.dart
  - tool/recusas_custo.py
  - docs/validacao/backtest_aplicativo.json
  - docs/validacao/recusas_custo.md
  - docs/validacao/recusas_custo.json
substitui: []
---

## Contexto

O item C0 do plano. A §0 achou, sobre o motor de 11/09, que nas observações
recusadas o book-to-market dava o maior spread de quintil de todos os recortes:
+23,8 p.p. em 12 meses e +77,3 p.p. em 36. O critério pedia o spread por motivo
de recusa e por liquidez, e **uma decisão por motivo: manter a recusa ou
soltá-la**.

A medição foi feita sobre a montagem do aplicativo **na data de cada coorte**, e
não sobre a de 11/09: curva do Tesouro do dia, CVM recebida até ali, setor da B3,
prazo das outorgas do Formulário de Referência recebido até ali e beta de retorno
total. São 2.633 observações de 2018 a 2025, 845 avaliadas e 1.788 recusadas.

## Decisão

1. **Nenhuma recusa é solta.** Por motivo:

   | motivo | n | por que fica |
   |---|---:|---|
   | só liquidez | 986 | ver o item 2 |
   | só histórico curto | 282 | o B/M ordena pouco em 12 meses (IC 0,13, t 1,3); abaixo de oito exercícios as guardas perdem o poder (decisão 25), e soltar pediria mudar o núcleo sem contrafactual medido |
   | mais de um motivo | 322 | quase todos ilíquidos, com mediana de R$ 49 mil por dia |
   | nenhuma via aplicável | 88 | o B/M ordena forte (IC 0,43, t 5,0), e o motor não tem modelo para eles: é sinal do fator ingênuo, e não recusa evitável — cabe no B1, e não aqui |
   | patrimônio não positivo, ponte frágil, sem exercício, sem contagem | 110 | amostra curta demais para medir, e sem base ou sem dado para avaliar |

2. **A recusa por liquidez tem sinal medido, e fica mesmo assim.** Soltando só o
   corte de liquidez — sem a série de cotações, a Porta 0 omite o teste —, o
   potencial dos 848 que passam a ser avaliados ordena o retorno total além do
   B/M: IC condicionado de 0,12 em 12 meses (t 2,75 entre sete coortes) e de 0,17
   em 36, onde nos avaliados não passa de 0,04 (t 0,67). O efeito sobrevive a
   começar o retorno um mês depois da coorte (t 2,85), então não é reversão do
   fechamento. Fica porque três coisas não estão resolvidas:
   - **o viés de sobrevivência é máximo justamente aqui**: papel pequeno e
     ilíquido que quebrou saiu do universo, e o que sobrou rendeu 73% em média
     em 36 meses contra 31% dos avaliados;
   - **o nível confirma o risco que a Porta 0 declara**: o potencial mediano
     deles é de −24%, contra −50% dos avaliados — beta de papel pouco negociado
     sai baixo e infla o preço justo;
   - **R$ 37 mil por dia, na mediana, não é investível** na escala de uma
     carteira.
3. **O custo da recusa por liquidez é remedido com as deslistadas** (C0b), com a
   contagem, os eventos e os proventos do A3.4, antes de qualquer decisão de
   soltá-la.

## Consequências aceitas

**O motor segue recusando mais do que avalia**: 68% das observações das coortes.
A cobertura não é critério (decisão 45), e o que esta decisão registra é que a
composição das recusas foi medida e que nenhuma delas, hoje, esconde sinal que o
motor saberia usar com segurança.

**A medição é dos sobreviventes.** O universo é o listado hoje; o B/M dos
recusados, e o do motor solto, estão inflados na medida do viés, que não é
conhecida até o C1b.

**O `t` de 36 meses é otimista**: as janelas de coortes vizinhas se sobrepõem, e
o erro-padrão entre cinco coortes não corrige isso (C1a).

Ver [recusas_custo.md](../validacao/recusas_custo.md).
