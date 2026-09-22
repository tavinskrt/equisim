# A reapresentação no *point-in-time* — item B8

> **Consertado em 22/09/2026** ([decisão 128](../decisoes/128-a-coorte-le-a-versao-que-era-publica-na-data.md)).
> As §0 a §3 são a medição de 21/09, feita antes de haver as versões antigas;
> a §4 é o conserto e o efeito dele.

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

## 4. O conserto, e o que ele moveu

> **Medido em 22/09/2026**, com a base bruta restaurada pelo C5.
>
> ```bash
> python tool/cvm_versoes_baixar.py      # repetir até nada faltar
> dart run tool/cvm_ingerir.dart data/cvm
> dart run tool/backtest_valuation.dart --montagem aplicativo --com-deslistadas --trimestral
> python tool/reapresentacao_efeito.py SEM.json docs/validacao/backtest_trimestral.json
> ```

**A versão original existia, e é pública.** Os CSVs anuais da CVM trazem nos
demonstrativos só a última versão — conferido: na DRE consolidada de 2019, 0 de
386 documentos aparecem com mais de uma —, mas o índice lista todas, com o
`ID_DOC` de cada uma, e o RAD entrega o pacote de qualquer versão por esse
número. Dentro do pacote vêm as mesmas contas, na mesma escala: a conversão foi
conferida conta a conta contra os CSVs em quatro documentos da WEG, dois no
formato até 2022 (um `.dfp` interno com `InfoFinaDFin.xml`) e dois no de 2023 em
diante (um XML único com os valores em formato brasileiro) — **zero
divergência** nos oito demonstrativos que o motor lê.

**Só a versão vigente em alguma coorte é baixada**: a de recebimento mais
recente até a data, quando não é a última. São **626** no universo das coortes
— 316 DFP e 310 ITR. O RAD reseta conexão longa, e o download precisou de três
passes; **616 foram convertidas**, 9 recusaram o download nas três tentativas e
1 veio sem demonstrativo. As dez restantes caem na última versão, que é o
comportamento de antes.

**A ingestão grava as antigas em arquivo à parte** (`data/cvm_versoes.json`),
cada uma com a data de recebimento **dela**, e a base vigente ficou idêntica em
conteúdo à anterior. O backtest lê as duas, e `CvmSeries.vigentes` escolhe em
cada coorte a versão recebida mais recentemente até a data — a original até a
reapresentação chegar, a reapresentada depois.

### O efeito

Duas execuções do backtest sobre o mesmo motor, sem e com as versões antigas
([reapresentacao_efeito.json](reapresentacao_efeito.json)):

| | |
|---|---:|
| observações | 10.919 nas duas |
| avaliadas nas duas | 3.045 |
| **preço justo que muda** | **84 (2,8%)** |
| passam a ser avaliadas | 6 |
| deixam de ser avaliadas | 16 |
| exercício mais recente que muda | 61 |
| book-to-market que muda | 87 |
| movimento do justo entre as que mudam | mediana 21%, p90 83% |

**O efeito é raro e grande.** Em 97% das observações nada muda — a
reapresentação típica chega antes da coorte seguinte, ou corrige o que o motor
não lê. Onde muda, muda muito: a ENAT3 em 31/03/2022 vai de R$ 3,81 a R$ 20,16 de
preço justo, a MRVE3 ao longo de 2022 perde de 83% a 97%, o BPAC11 em 31/12/2021
cai de R$ 38,57 para R$ 5,67. **São exatamente os casos que a metade (b) nomeava**:
número corrigido depois entrando numa avaliação que não o tinha.

**E a leitura do R3 não muda.** O potencial condicionado ao book-to-market, em 36
meses, dá 0,028 com `t` corrigido de 0,15 — era 0,027 com 0,15 —, e nenhuma
das cinco ordenações passa. A faixa calibrada continua replicando: 87,8% em 12
meses e 88,4% em 36 contra 90% nominal.

**O que isto fecha.** As duas metades: (a) o documento que sumia porque a única
versão disponível chegou depois volta pela versão original; (b) o número
reapresentado deixa de entrar antes de ter sido publicado. O que sobra são as dez
versões que o RAD não entregou — 1,6% das 626 —, declaradas.
