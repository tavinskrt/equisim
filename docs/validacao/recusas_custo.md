# O que as recusas custam — item C0

Medido em 14/09/2026 por `tool/recusas_custo.py`, sobre
`docs/validacao/backtest_aplicativo.json` — a montagem do aplicativo na data de
cada coorte, descrita em [cobertura_banda.md](cobertura_banda.md) §1. Dados em
[recusas_custo.json](recusas_custo.json). Decisão:
[91](../decisoes/091-as-recusas-ficam-e-a-liquidez-e-remedida-com-as-deslistadas.md).

**A régua.** O IC é a correlação de postos entre o sinal e o retorno total de
cada coorte, na média das coortes; o `t` é o da média entre coortes. Em 12 meses
são sete coortes que não se sobrepõem; em 36, cinco que se sobrepõem, e o `t`
delas é otimista (C1a). `Q5−Q1` é o retorno total do quintil de maior B/M menos
o do menor, na média das coortes.

## 1. A pergunta da §0, na montagem de agora

A §0 do plano achou, no motor de 11/09, que nas 1.218 observações recusadas o
book-to-market dava spread de +23,8 p.p. em 12 meses e +77,3 p.p. em 36. Na
montagem de agora são 1.788 recusadas em 2.633, e o recorte se repete mais forte:

| | n | liquidez mediana | IC do B/M 12m | `t` | `Q5−Q1` 12m | IC do B/M 36m | `Q5−Q1` 36m |
|---|---:|---:|---:|---:|---:|---:|---:|
| avaliadas | 845 | R$ 35,8 mi | 0,133 | 3,34 | +14,9 p.p. | 0,243 | +74,1 p.p. |
| recusadas | 1.788 | R$ 0,14 mi | 0,273 | 7,18 | +34,5 p.p. | 0,466 | +136,6 p.p. |

## 2. Por motivo

| motivo | n | liquidez mediana | acima do corte de R$ 2 mi | IC do B/M 12m | `t` | IC do B/M 36m |
|---|---:|---:|---:|---:|---:|---:|
| só liquidez | 986 | R$ 37 mil | 0 | 0,242 | 6,41 | 0,386 |
| só histórico curto | 282 | R$ 21,7 mi | 278 | 0,130 | 1,29 | 0,397 |
| mais de um motivo | 322 | R$ 49 mil | 4 | 0,015 | 0,07 | — |
| nenhuma via aplicável | 88 | R$ 22,0 mi | 81 | 0,427 | 4,96 | 0,566 |
| só patrimônio não positivo | 51 | R$ 38,2 mi | 42 | — | — | — |
| ponte frágil sem via do acionista | 38 | R$ 39,3 mi | 38 | — | — | — |
| nenhum exercício divulgado | 12 | — | — | — | — | — |
| sem contagem de papéis | 9 | — | — | — | — | — |

"—" é amostra curta demais para medir por coorte. **O sinal do B/M nas recusadas é
quase todo de dois grupos**: as ilíquidas, que são mais da metade, e as que
nenhuma via avalia — prejuízo recorrente e base negativa, onde o fator ingênuo
ordena forte e o motor não tem modelo.

**Por tercil de liquidez dentro das recusadas**, o B/M ordena nos três — IC de
0,19, 0,26 e 0,24 em 12 meses —, e o de cima começa em R$ 1 milhão por dia, ainda
abaixo do corte. Não é só o papel que não negocia.

## 3. Soltar a recusa por liquidez

Sem a série de cotações, a Porta 0 omite o teste de liquidez; nada mais na
cascata lê a série. `tool/backtest_valuation.dart` grava o potencial que sairia
para cada recusada, e 848 das 986 recusadas só por liquidez passam a ser
avaliadas.

| | n | IC do motor 12m | `t` | IC do B/M 12m | **motor dado o B/M, 12m** | `t` | motor dado o B/M, 36m | `t` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| avaliadas | 845 | 0,106 | 1,59 | 0,133 | 0,042 | 0,67 | 0,050 | 0,94 |
| soltas | 848 | 0,221 | 4,88 | 0,233 | **0,120** | **2,75** | 0,169 | 2,56 |

**Nas ilíquidas o motor ordena além do B/M**, e nas avaliadas não. É o achado
que pedia investigação, e três leituras dele foram testadas:

1. **Reversão do fechamento?** Sinal escalado pelo preço divide pelo mesmo
   fechamento em que o retorno começa, e em papel pouco negociado esse fechamento
   é ruído. Começando o retorno **um mês depois** da coorte, o motor dado o B/M
   fica em 0,110 (`t` 2,85) em 12 meses e 0,167 em 36. **Não é isso.**
2. **O risco que a Porta 0 declara?** Beta de papel pouco negociado sai baixo,
   reduz o custo de capital e infla o preço justo. O potencial mediano das soltas
   é de **−24,4%**, contra −49,6% das avaliadas: o nível confirma o risco. A
   ordenação dentro do grupo, porém, sobrevive a ele.
3. **Viés de sobrevivência?** O universo é o listado hoje. As soltas renderam
   **73,4% em média em 36 meses**, contra 31,0% das avaliadas; mediana de 32,4%
   contra 12,6%. Papel pequeno e ilíquido que quebrou saiu do universo, e o que
   sobrou é justamente o que o sinal de valor apontava. **Não se exclui sem as
   deslistadas.**

## 4. O que se decidiu

**Nenhuma recusa é solta** (decisão 91). A de liquidez fica porque o viés de
sobrevivência é máximo nela, o nível confirma o risco do beta, e R$ 37 mil por
dia não é investível na escala de uma carteira; o custo dela é remedido com as
deslistadas do A3.4 antes de qualquer soltura — é o C0b. As demais ficam por
falta de modelo, de amostra ou de dado, com o motivo de cada uma na decisão.

**O que fica em aberto para o B1**: onde o motor recusa, o fator ingênuo ordena
mais do que ordena onde o motor avalia. Se a ordenação da carteira sair de um
modelo transversal, e não do potencial, as recusadas deixam de ser invisíveis
para ela.

## 5. O que isto não diz

- **A amostra é dos sobreviventes**, e o IC das recusadas está inflado na medida
  do viés, que só o C1b mede.
- **O `t` de 36 meses é otimista**: cinco coortes com janelas sobrepostas.
- **O contrafactual só existe para a liquidez.** Soltar o histórico curto pediria
  mudar a Porta 0 no núcleo, e as guardas perdem o poder abaixo de oito
  exercícios (decisão 25) — medir isso é método novo, e não C0.
