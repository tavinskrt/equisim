# A ordenação, medida lado a lado — item B1

Item B1 do [plano do motor de referência](../plano-motor-de-referencia.md): decidir
o que o potencial serve. O usuário autorizou em 16/09/2026 a saída recomendada na
§3 do plano — **(c), medir o DCF e um modelo transversal lado a lado, com (a)
implantado enquanto (b) é perseguido**: o preço justo continua sendo a entrega da
tela de avaliação, e o prêmio do retorno esperado passa a sair de um modelo
transversal declarado, com o potencial como um insumo entre outros.

## 1. O que se mede, e a regra — fixados antes de medir

**Escrito em 16/09/2026, antes de a medição rodar, e não alterado depois.** O
backtest trimestral sobre o motor com os itens B10 e B13 estava em execução; as
medições da rodada anterior, sobre o motor de antes, já eram conhecidas e estão
declaradas abaixo.

**O que já se sabia.** Nas coortes trimestrais de 36 meses com as deslistadas, na
base da data, sobre o motor de 15/09/2026: IC do book-to-market de 0,181 com `t`
corrigido de 2,92 contra o crítico de 2,70 e Newey-West de 7,03 — **o único dos
três que passava no critério da [decisão 96](../decisoes/096-o-t-da-habilidade-e-corrigido-pela-sobreposicao-contra-o-critico-dela.md)**,
e perto da borda —; IC do lucro sobre o preço de 0,128 com `t` corrigido de 1,00;
IC do potencial de 0,091 com `t` corrigido de 0,74 ([habilidade_trimestral.md](habilidade_trimestral.md)).
O composto nunca foi medido. O motor mudou desde então (decisão 102): 16 ativos
saíram do aplicativo e o potencial de quem ficou mudou.

**As três ordenações.**

1. **Potencial** — o do motor, `justo ÷ preço − 1`.
2. **Book-to-market** — patrimônio líquido do último exercício publicado sobre o
   valor de mercado na data.
3. **Composto** — o modelo transversal declarado: a média dos escores robustos
   dos três sinais — potencial, book-to-market e lucro sobre o preço —, cada um
   `(x − mediana) ÷ MAD` na seção, confinado a ±2, como o escore do retorno
   esperado já é. Pesos iguais, por não haver fundamento a priori para outros;
   sinal ausente sai da média.

**A amostra.** As 31 coortes trimestrais com as deslistadas, na base da data,
sobre o motor de 16/09/2026; retorno total de 36 meses; **as mesmas observações
para as três ordenações** — as que têm potencial, book-to-market e lucro sobre o
preço. A seção de cada escore é a coorte.

**O critério.** O da decisão 96, sobre o IC médio entre coortes em 36 meses: `t`
corrigido pela sobreposição acima do crítico dela, e Newey-West acima de 2. Os 12
meses são informados, e não decidem.

**A regra do que o aplicativo usa.** O prêmio sobre o `Ke` do retorno esperado
sai da **primeira ordenação que passar, nesta ordem: composto, book-to-market,
potencial**. O composto vem primeiro porque é o modelo que a saída (a) declara; o
book-to-market em seguida, porque é o fator de uma linha contra o qual a §0 do
plano mediu o motor. **Se nenhuma passar, não há prêmio**: o retorno esperado de
cada ativo é o `Ke` dele, e a tela diz por quê. A regra fica no código da
ferramenta que grava o pacote, e não na leitura de quem vê o resultado.

**Em nenhum caso outra ordenação é medida nesta rodada**, e os pesos do composto
não se ajustam ao resultado.

**O que não entra na regra, e é informado:** o IC de cada ordenação em 12 meses,
com e sem as deslistadas, e a correlação de postos entre as três.

## 2. O resultado — nenhuma ordenação passa, e o prêmio sai

Medido em 16/09/2026 por `dart run tool/regressao_condicional.dart --trimestral`,
sobre `docs/validacao/backtest_trimestral.json` reexecutado com o motor da
[decisão 102](../decisoes/102-nenhuma-avaliacao-muda-de-via-e-a-firma-avalia-pelo-fluxo-do-acionista-derivado.md)
— 10.874 observações em 31 coortes, 3.470 avaliadas. Dados em
[habilidade_trimestral.json](habilidade_trimestral.json), bloco `icComposto` ao
lado dos outros. Decisão: [103](../decisoes/103-o-premio-do-retorno-esperado-sai-da-ordenacao-comprovada-e-hoje-nao-ha.md).

**Em 36 meses, com as deslistadas** — 2.452 observações, 22 coortes, crítico de
2,70:

| ordenação | IC médio | `t` corrigido | Newey-West | coortes positivas | passa |
|---|---:|---:|---:|---:|:---:|
| composto | 0,173 | 1,57 | 3,82 | 21/22 | não |
| **book-to-market** | **0,186** | **2,52** | 5,45 | 22/22 | **não** |
| potencial | 0,078 | 0,61 | 1,45 | 13/22 | não |
| *lucro sobre o preço, informado* | *0,146* | *1,24* | *3,21* | *20/22* | — |

**Pela regra, o retorno esperado não leva prêmio**: é o `Ke` de cada ativo, e a
tela de metas diz isso.

**O book-to-market deixou de passar, e passava por pouco.** No motor de antes,
sobre 2.570 observações, tinha `t` corrigido de 2,92 contra 2,70. Neste, sobre
2.452, tem 2,52: a amostra é a das observações que o motor avalia, e a decisão
102 tirou dela as companhias em que o fluxo do acionista derivado não sustenta
capital próprio positivo — as endividadas que migravam para a via do acionista. O
IC médio até subiu, de 0,181 para 0,186; o que caiu foi a estabilidade entre
coortes. **A leitura honesta é que o book-to-market esteve na borda nas duas
medições**, e a regra fixada antes não arredonda a borda. Medido sobre todas as
avaliadas, sem exigir o lucro sobre o preço, ele fica em 2,67 contra 2,70
([recusas_custo.md](recusas_custo.md) §8).

**O composto ordena quase tanto quanto o book-to-market, e é menos estável.** O
IC é de 0,173, positivo em 21 das 22 coortes, com `t` corrigido de 1,57. Ele
carrega o potencial, e o potencial é o sinal mais fraco dos três.

**O potencial dado o book-to-market fica em 0,010**, com `t` corrigido de 0,08 —
contra 0,030 e 0,24 no motor de antes. A decisão 102 mudou o preço justo de toda
avaliação da via da firma — e o de 42 dos 109 não financeiros avaliados pelo
aplicativo, que migravam ou eram mesclados, por muito mais —, e a leitura do R3
caiu.

**Sem as deslistadas, e em 12 meses**, nada passa também:

| | composto | book-to-market | potencial | potencial dado o B/M |
|---|---|---|---|---|
| 36 meses, sem as deslistadas | 0,179 · 1,42 | 0,181 · 2,13 | 0,089 · 0,62 | 0,024 · 0,17 |
| 12 meses, com as deslistadas (crítico 2,24) | 0,086 · 1,42 | 0,094 · 1,55 | 0,046 · 0,76 | 0,010 · 0,16 |
| 12 meses, sem as deslistadas | 0,090 · 1,53 | 0,088 · 1,42 | 0,050 · 0,76 | 0,017 · 0,24 |

(IC médio · `t` corrigido.)

**A correlação de postos entre as três**, mediana das 22 coortes de 36 meses: o
composto com o potencial, 0,766; com o book-to-market, 0,779; o potencial com o
book-to-market, 0,383.

## 3. O que isto decide, e o que não decide

**Decide o prêmio do aplicativo, pela regra**: nenhum, enquanto nenhuma ordenação
passar. O pacote `assets/validacao/habilidade.json` leva as três leituras, e o
núcleo aplica a regra (`SkillReading.premiumOrdering`): quando a medição final
(C1, na Fase 4) ou uma remedição depois dela mostrar uma ordenação que passa, o
prêmio volta, dessa ordenação, sem mudar código.

**Não decide que o book-to-market não ordena.** Ele é positivo em 22 de 22
coortes; o que a amostra não sustenta, com 22 coortes que compartilham 33 meses de
retorno cada, é afirmar isso no nível que a decisão 96 exige. É a mesma distância
entre direção e prova que a decisão 95 registrou para a recusa por liquidez.

**Não decide o que o DCF é.** O preço justo continua sendo a entrega da tela de
avaliação. A saída (b) do B1 — o DCF tem de ganhar — segue aberta, e a medição
dela é o C1.
