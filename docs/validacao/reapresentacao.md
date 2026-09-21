# A reapresentação no *point-in-time* — item B8

> **Medido em 21/09/2026**, sobre `assets/cvm/documentos.json`, que é
> versionado. Esta medição **não precisa da base bruta nem da entrada
> congelada** — ela se reproduz num clone limpo.
>
> ```bash
> dart run tool/reapresentacao.dart   # grava reapresentacao.json
> ```

## 0. O defeito, e as duas metades dele

A ingestão adota a **última versão** de cada documento da CVM, e 24,8% dos
anuais têm mais de uma. A data que viaja com o documento é a de recebimento
**daquela** versão. Numa avaliação datada, o corte *point-in-time* compara essa
data com a data da coorte, e daí saem dois problemas diferentes:

- **(a) o documento some.** Quando a última versão chegou depois da coorte, o
  exercício inteiro sai, e a coorte recua para a fonte de mercado — embora a
  versão **original** estivesse pública na época. É a evidência que abriu o
  item: a DFP de 2023 da USIM3 tem recebimento em 16/01/2025, e em 04/09/2024
  aquele ano ficava sem CVM.
- **(b) o número é o reapresentado.** Quando a última versão chegou **antes** da
  coorte, ela entra — com os números corrigidos, que ninguém tinha naquela data.
  É conhecimento futuro entrando na coorte pela porta da frente.

**A metade (a) é medível com o pacote. A (b) não é**: ela exige as versões
originais, que só existem na base bruta — e `data/cvm` não sobrevive ao clone
(item C5).

## 1. Quanto atraso há

O prazo regulamentar é a régua: a DFP vence três meses depois do fecho do
exercício; o ITR, 45 dias depois do fecho do trimestre. Recebimento além disso é
entrega atrasada **ou** reapresentação, e o pacote não distingue as duas.

| | documentos | p50 | p90 | máximo | além do prazo |
|---|---:|---:|---:|---:|---:|
| DFP | 5.142 | 79 dias | 115 | **3.000** | 784 (15,2%) |
| ITR | 13.923 | 42 dias | 56 | 2.129 | 2.385 (17,1%) |

**Um sexto dos documentos chega depois do prazo.** Os extremos não são pequenos:

| ticker | fecho | recebido | atraso |
|---|---|---|---:|
| ITUB4 / ITUB3 | 31/12/2011 | 18/03/2020 | 3.000 dias |
| ITUB4 / ITUB3 | 31/12/2012 | 18/03/2020 | 2.634 |
| RNEW3 / RNEW4 | 30/06/2014 | 28/04/2020 | 2.129 |
| PFRM3 | 31/03/2014 | 29/06/2018 | 1.551 |
| BPAC3 | 31/12/2020 | 23/12/2024 | 1.453 |

## 2. Mas a metade medível é pequena

Para cada data de coorte, quantos exercícios **deviam estar públicos** — prazo
regulamentar vencido antes dela — e quantos somem porque a única versão que o
pacote tem chegou depois:

| coorte | deviam estar | perdidos | fração | tickers |
|---|---:|---:|---:|---:|
| 31/03/2018 | 7.955 | 46 | 0,6% | 15 |
| 30/06/2020 | 11.066 | **120** | **1,1%** | 72 |
| 30/09/2020 | 11.412 | 113 | 1,0% | 54 |
| 30/06/2023 | 15.388 | 85 | 0,6% | 47 |
| 30/06/2024 | 16.858 | 98 | 0,6% | 52 |
| 30/09/2025 | 17.979 | 10 | 0,1% | 10 |

Nas 31 coortes trimestrais, a perda vai de **0,0% a 1,1%**, com a maioria abaixo
de 0,6%. A pior é a de 30/06/2020 — o trimestre em que a CVM prorrogou prazos
pela pandemia —, e ali 72 tickers perdem ao menos um exercício.

**O defeito (a) é real e pequeno.** Menos de um centésimo dos exercícios de cada
coorte, num efeito que empurra a observação para a fonte de mercado em vez de a
apagar.

## 3. O que fica aberto, e é a metade que importa

**A metade (b) não foi medida, e ela é maior por construção.** Se 24,8% dos
anuais têm mais de uma versão, até um quarto dos documentos que a coorte usa
pode carregar número corrigido depois. Quanto disso muda o preço justo — e a
ordenação — depende de quanto a reapresentação move os campos que o motor lê, e
isso exige as versões originais.

**Consertar exige a base bruta.** A ingestão precisa guardar cada versão com a
data dela, o pacote precisa carregá-las, e o corte *point-in-time* precisa
escolher a versão recebida até a data. Os três passos dependem de `data/cvm`,
que é o item C5.

**O que este documento decide:** nada do motor muda agora, e o item B8 fica
aberto com o tamanho de uma das metades medido. A limitação que ele descreve
deixa de ser "24,8% dos anuais têm mais de uma versão" — que é a contagem das
reapresentações, não a do dano — e passa a ser **"menos de 1,1% dos exercícios
de cada coorte somem, e a parte que entra com número corrigido não foi
medida"**.
