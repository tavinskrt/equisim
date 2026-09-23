# O múltiplo de pares como ordenação — item B22

> **Medido em 21/09/2026**, sobre as coortes reexecutadas nesta rodada — **o
> motor da Fase 3**, e não mais o da decisão 102 (item C5).
>
> **Remedido em 22/09/2026 sobre o motor que fecha a Fase 3** (itens B8 e B24):
> o múltiplo de pares vai a IC **0,083**, `t` corrigido **1,24** contra 2,70 e
> Newey-West 3,49, com 20 de 22 coortes positivas — e **continua não passando**.
> Com o item B26 corrigido: IC **0,079**, `t` corrigido **1,18**, Newey-West
> 3,65, 18 de 22 coortes positivas — não passa.
> As tabelas abaixo são as de 21/09; o `multiplos_ordenacao.json` é o de 22/09.
>
> ```bash
> dart run tool/backtest_valuation.dart --montagem aplicativo \
>     --com-deslistadas --trimestral
> dart run tool/multiplos_ordenacao.dart
> ```

## 0. Por que ele virou candidato

O item B5 mediu que o potencial do DCF e o dos múltiplos de pares têm
correlação de postos de **0,470**, com o mesmo sinal em 63 de 93. **Sinal
distinto, e não cópia** — o que o torna candidato a ordenação pela regra que a
[decisão 103](../decisoes/103-o-premio-do-retorno-esperado-sai-da-ordenacao-comprovada-e-hoje-nao-ha.md)
fixou **antes de medir**: o prêmio do retorno esperado sai da **primeira
ordenação que passar** no critério da decisão 96.

## 1. A mediana é da coorte, e isso não é detalhe

O pacote versionado de múltiplos é de **14/09/2026**. Usá-lo numa observação de
2018 seria conhecimento futuro entrando pela porta da frente — exatamente o
defeito que o item B8 nomeia em outro lugar.

**Aqui a mediana setorial sai da própria seção transversal da coorte.** O
backtest grava, por observação, os ingredientes — `P/L` e `P/VP` já vinham como
`earningsYield` e `bookToMarket` invertidos, e a firma sobre EBITDA entrou nesta
rodada —, e a ferramenta monta a mediana por setor **dentro de cada coorte**,
com recuo para o mercado daquela data quando o setor não reúne cinco pares.

**E o potencial não passa pela ponte.** Ele é `valor implicado ÷ valor de
mercado − 1`: os dois lados são da companhia inteira, e a contagem de papéis não
entra. A ponte não tem como contaminar a medição porque não é consultada.

**Nenhuma observação ficou sem mediana usável**: as 2.165 de 36 meses e as 2.943
de 12 meses são exatamente as mesmas que as outras ordenações usam. A comparação
é entre ordenadores, e não entre coberturas.

## 2. As quatro, lado a lado

**36 meses — 2.165 observações, 22 coortes trimestrais:**

| ordenação | IC médio | `t` | Newey-West | `t` corrigido / crítico | positivas | passa |
|---|---:|---:|---:|---:|---:|---|
| book-to-market | **+0,157** | 8,16 | 4,26 | **1,98** / 2,70 | 20 de 22 | não |
| composto | +0,147 | 4,80 | 2,81 | 1,17 / 2,70 | 18 de 22 | não |
| lucro sobre preço | +0,124 | 4,20 | 2,78 | 1,02 / 2,70 | 18 de 22 | não |
| potencial do DCF | +0,089 | 2,18 | 1,26 | 0,53 / 2,70 | 13 de 22 | não |
| **múltiplo de pares** | **+0,075** | 4,27 | 2,65 | **1,04** / 2,70 | 18 de 22 | **não** |

**12 meses — 2.943 observações, 30 coortes:**

| ordenação | IC médio | `t` corrigido / crítico | positivas | passa |
|---|---:|---:|---:|---|
| book-to-market | +0,086 | 1,46 / 2,24 | 25 de 30 | não |
| composto | +0,084 | 1,42 / 2,24 | 21 de 30 | não |
| potencial do DCF | +0,072 | 1,20 / 2,24 | 20 de 30 | não |
| lucro sobre preço | +0,041 | 0,79 / 2,24 | 19 de 30 | não |
| **múltiplo de pares** | **+0,029** | 0,70 / 2,24 | 21 de 30 | **não** |

## 3. O que isto responde

**O múltiplo de pares não passa, e a regra da decisão 103 segue valendo sem
mudança:** nenhuma ordenação passou, e o prêmio do retorno esperado continua
sendo nenhum.

**Mas ele é mais estável do que o potencial, e menos forte.** Em 36 meses o
`t` bruto dele é 4,27 contra 2,18 do potencial, e o Newey-West é 2,65 contra
1,26 — ele acerta com mais consistência entre coortes, 18 positivas contra 13.
**O que ele não tem é magnitude**: 0,075 contra 0,089 do potencial e 0,157 do
book-to-market. **A correção pela sobreposição o achata como achata todos**, e
1,04 fica longe de 2,70.

**E os dois sinais que a §0 do plano opõe continuam na mesma ordem.** O
book-to-market ordena mais que qualquer coisa que o motor produza — potencial ou
múltiplo —, e a distância não diminuiu com o motor da Fase 3.

## 4. O que mudou com a reexecução das coortes

**As coortes são novas.** Até esta rodada, habilidade, faixa, recusas e ponte
descreviam o motor da decisão 102; o item C5 as reexecutou sobre o motor que a
Fase 3 deixou. O potencial do DCF vai de **0,078 a 0,089** em 36 meses, e o
resíduo ortogonalizado ao P/B (item B2) de **+0,016 a +0,025**.

**E o book-to-market deixou de passar.** Na leitura anterior ele tinha `t`
corrigido de **2,52** contra o crítico de 2,70 — perto de passar. Agora tem
**1,98**. **Nenhuma das cinco ordenações passa**, e a regra da decisão 103, que
foi fixada antes de qualquer uma ser medida, continua devolvendo o mesmo: prêmio
nenhum.

## 5. O que isto não diz

- **Não é o C1.** O veredito da habilidade é o coeficiente do potencial
  **condicionado ao P/B** numa regressão conjunta, e ele está em
  [habilidade_trimestral.md](habilidade_trimestral.md). Esta medição é de
  ordenações lado a lado, que é a regra do B1.
- **A mediana da coorte não é a do pacote.** As duas respondem perguntas
  diferentes: a do pacote é a que o aplicativo mostra hoje; a da coorte é a que
  existia naquela data. Comparar os dois números seria comparar instrumentos.
- **O múltiplo é do exercício publicado**, e não normalizado. Numa companhia
  cíclica no fundo do ciclo, o `P/L` fica alto e a leitura parece cara — é a
  mesma limitação que a [decisão 118](../decisoes/118-a-triangulacao-por-multiplos-e-segunda-leitura-declarada-e-nao-entra-no-preco.md)
  já declarou.
