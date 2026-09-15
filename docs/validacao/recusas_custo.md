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
  do viés, que só o C1b mede — **medido em 15/09/2026, na §6**: o viés pesa no
  nível do retorno, e não na ordenação.
- **O `t` de 36 meses é otimista**: cinco coortes com janelas sobrepostas — a §6
  o refaz com Newey-West.
- **O contrafactual só existe para a liquidez.** Soltar o histórico curto pediria
  mudar a Porta 0 no núcleo, e as guardas perdem o poder abaixo de oito
  exercícios (decisão 25) — medir isso é método novo, e não C0.

## 6. Com as deslistadas — item C0b

> **Medido sobre a montagem com o preço na base de ações de hoje, e com o `t` da
> decisão 93.** A §7 remede na base da data e com o `t` da decisão 96.

Medido em 15/09/2026 por `python tool/recusas_custo.py --entrada
docs/validacao/backtest_aplicativo_deslistadas.json --grupo todas` (e
`--grupo listadas`, `--grupo deslistadas`), sobre a montagem do aplicativo por
data com as deslistadas da ponte, na mesma execução. Dados em
[recusas_custo_deslistadas.json](recusas_custo_deslistadas.json) e
[recusas_custo_so_deslistadas.json](recusas_custo_so_deslistadas.json). Decisão:
[95](../decisoes/095-a-recusa-por-liquidez-fica-pelo-nivel-e-nao-pela-ordenacao.md).

**O `t` de 36 meses passa a sair também com Newey-West**, e vale o menor dos dois
(decisão 93). Em 12 meses as coortes não se sobrepõem, e os dois coincidem.

**A pergunta da §3.3**: o sinal dos soltos do corte de liquidez é viés de
sobrevivência?

| soltos do corte de liquidez | n | IC dado o B/M, 12m | `t` | IC dado o B/M, 36m | `t` comum / Newey-West |
|---|---:|---:|---:|---:|---:|
| listadas | 848 | 0,120 | 2,75 | 0,169 | 2,56 / 2,85 |
| **com as deslistadas** | **1.003** | **0,116** | **2,73** | **0,189** | **3,08 / 3,22** |
| só as deslistadas | 155 | 0,107 | 1,10 | 0,158 | 2,39 / 4,06 |

Começando o retorno um mês depois, com as deslistadas: 0,105 (`t` 2,63) em 12
meses e 0,182 (`t` 2,91) em 36. Nas avaliadas, com as deslistadas, o potencial
dado o B/M continua sem sinal: 0,036 (`t` 0,65) e 0,057 (`t` 1,25).

**Não é o viés que produz a ordenação.** O viés existe, e pesa no nível do
retorno: os soltos com as deslistadas renderam 67,8% em média em 36 meses, contra
73,4% só nas listadas, e os deslistados soltos, 45,6%.

**O nível do preço justo continua fora**: o potencial mediano dos soltos é de
−24,5%, contra −52,1% das avaliadas, com as deslistadas nos dois grupos.

**O B/M por motivo, com as deslistadas**, repete a §2: nas 1.203 recusadas só por
liquidez, IC de 0,196 em 12 meses (`t` 7,36); nas 101 que nenhuma via avalia, de
0,354 (`t` 3,62); nas 344 de histórico curto, de 0,127 (`t` 1,82).

**O que se decidiu** (decisão 95): a recusa por liquidez fica, pelo nível — beta
de papel pouco negociado sai baixo e infla o preço justo —, e não pela ordenação,
que sobreviveu às deslistadas. A razão da investibilidade sai, porque não era da
Porta 0. O caminho para soltar é corrigir o beta pela negociação não sincrônica e
remedir o nível, e entrou no plano.

## 7. Na base da data, trimestral

Medido em 15/09/2026 por `python tool/recusas_custo.py --grupo todas --saida
docs/validacao/recusas_custo_trimestral_todas.json` (e `--grupo listadas`,
`--grupo deslistadas`), sobre `docs/validacao/backtest_trimestral.json` — as 31
coortes trimestrais com as deslistadas da ponte ampliada (C1d), na base de ações
da data (C3). Os `t` saem de três jeitos, e o que decide é o corrigido pela
sobreposição contra o crítico dela, com o Newey-West acima de 2
([decisão 96](../decisoes/096-o-t-da-habilidade-e-corrigido-pela-sobreposicao-contra-o-critico-dela.md)).

**Por que remedir.** As §§1 a 6 foram medidas com o preço da coorte na base de
ações de hoje, que inflava o valor de mercado de quem desdobrou depois e o
book-to-market de quem agrupou ([ponte_por_papel.md](ponte_por_papel.md) §1).

**A pergunta das §§3 e 6, de novo** — o potencial dos soltos do corte de liquidez
ordena além do B/M?

| com as deslistadas | n | 12 meses: IC · `t` comum · NW · corrigido / crítico | 36 meses: IC · `t` comum · NW · corrigido / crítico |
|---|---:|---|---|
| avaliadas | 3.672 | 0,019 · 0,74 · 0,52 · 0,36 / 2,24 | 0,026 · 0,97 · 0,65 · 0,24 / 2,70 |
| **soltos do corte de liquidez** | **3.488** | **0,084** · 3,44 · 2,32 · **1,67 / 2,24** | **0,148** · 4,79 · 2,42 · **1,16 / 2,70** |
| começando um mês depois | | 0,084 · 3,66 · 2,50 · 1,77 / 2,24 | 0,148 · 4,68 · 2,35 · 1,14 / 2,70 |
| só as listadas | 2.884 | 0,086 · 3,41 · 2,38 · 1,66 / 2,24 | 0,122 · 3,63 · 1,98 · 0,88 / 2,70 |
| só as deslistadas | 604 | 0,091 · 2,18 · 1,56 · 1,05 / 2,24 | 0,142 · 3,28 · 3,90 · 0,80 / 2,70 |

**O sinal está lá, e não prova.** O coeficiente é quatro a seis vezes o das
avaliadas, positivo nos dois horizontes e nas duas amostras, e sobrevive ao mês
pulado. Com o `t` comum — o da §6 —, passaria de 2 com folga. Com o que as coortes
sobrepostas permitem dizer, não passa em nenhum horizonte. **A leitura da
[decisão 95](../decisoes/095-a-recusa-por-liquidez-fica-pelo-nivel-e-nao-pela-ordenacao.md)
de que "a ordenação sobreviveu" fica como direção, e não como prova.**

**O nível continua fora**: o potencial mediano dos soltos é de −25,4%, contra
−51,5% das avaliadas. **A recusa por liquidez fica, pela razão que a decisão 95
deu.**

**O B/M, por grupo, com as deslistadas:**

| grupo | n | IC 12m · corrigido / crítico | IC 36m · corrigido / crítico |
|---|---:|---|---|
| avaliadas | 3.672 | 0,094 · 1,61 / 2,24 | **0,179 · 3,09 / 2,70** |
| todas as recusadas | 7.191 | **0,132 · 3,20 / 2,24** | **0,254 · 3,75 / 2,70** |
| só liquidez | 4.190 | **0,121 · 2,51 / 2,24** | 0,204 · 1,77 / 2,70 |
| só histórico curto | 1.334 | 0,039 · 0,51 / 2,24 | 0,212 · 1,84 / 2,70 |
| nenhuma via aplicável | 332 | 0,110 · 0,86 / 2,35 | 0,225 · 0,90 / 2,72 |

**O recorte da §0 do plano sobrevive à correção**: o B/M ordena mais nas
recusadas do que nas avaliadas, e passa no critério nas duas amostras em 36 meses.
Nas deslistadas sozinhas, o B/M dos recusados só por liquidez não ordena — IC de
−0,008 em 12 meses e de 0,030 em 36.
