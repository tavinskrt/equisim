# A1.8 — os doze meses, e o A1.7 refeito

Executado em 14/09/2026, sobre a base completa: **40.064 documentos** da CVM —
10.846 DFP e 29.218 ITR, de 2010 a 2026 —, de 1.224 companhias.

```bash
python tool/cvm_baixar.py --de 2010 --ate 2026 --docs DFP,ITR,FCA
dart run tool/cvm_ingerir.dart data/cvm
dart run tool/cvm_ligar.dart 2024-09-04   # grava cvm_ligacao_2024-09-04.*
```

---

## 1. O que a conferência do ITR revelou antes de construir

Três defeitos das rodadas anteriores, nenhum visível nos totais publicados
([decisão 72](../decisoes/072-a-ingestao-le-o-periodo-e-o-tipo-do-documento.md)).

### 1.1 A DRE do ITR traz trimestre e acumulado

No 2º e no 3º trimestre cada conta vem duas vezes, distinguidas só por
`DT_INI_EXERC`. WEG, 2T23:

| período | receita |
|---|---:|
| 01/01/2023 a 30/06/2023 — acumulado | R$ 15,87 bi |
| 01/04/2023 a 30/06/2023 — trimestre | R$ 8,17 bi |

A ingestão filtrava só por `ÚLTIMO`, e o leitor ficava com a que aparecesse
primeiro. **19.237 dos 29.218 ITRs** tinham a duplicação. A DFC do ITR já vem
acumulada, e o balanço vem na data do trimestre — o defeito era só da DRE.

A correção fica com a linha de **menor `DT_INI_EXERC`**, e a conferência que a
valida é externa ao leitor: o comparativo que o ITR de um ano traz tem de bater
com o acumulado que o ITR do ano anterior publicou para o mesmo trimestre.

| conta | pares | batem a 0,1% |
|---|---:|---:|
| receita | 21.123 | **89,3%** |
| lucro líquido | 24.145 | **92,6%** |
| EBIT | 22.650 | **88,7%** |
| caixa operacional | 23.219 | **83,0%** |

O resíduo é, como hipótese não verificada, reapresentação do ano anterior
dentro do comparativo.

### 1.2 "Anual" era "termina em dezembro"

| companhia | encerramento do exercício |
|---|---|
| AGRO3 | junho |
| SMTO3, JALL3, RAIZ4 | março |
| CAML3 | fevereiro |

Para elas, o ITR de dezembro é acumulado parcial, e a primeira ligação o
tratava como ano cheio. A série anual passa a ser **a DFP, pelo tipo**.

### 1.3 O LPA da CVM é zero

A conta `3.99` vem **exatamente zero em 14.684 de 15.206** exercícios. Zero não
é nulo, a mescla o preferia, e o árbitro `lucro ÷ LPA` da contagem de ações se
desligava. O LPA passa a vir só do mercado.

---

## 2. O A1.7 refeito

Mesma medição da rodada anterior, sem os três contaminantes. Em 04/09/2026:

| | antes (A1.7 original) | refeito |
|---|---:|---:|
| avaliados, mercado → CVM anual | 127 → 127 | 127 → 128 |
| mediana do `\|Δ potencial\|` | 0,0% | **0,0%** |
| `\|Δ\|` > 10 p.p. | 7 | 8 |
| **SMTO3** | **−45,2 p.p.** | **−0,9 p.p.** |

**O SMTO3 era artefato**, e o registro da rodada anterior não o apontou. Os
bancos continuam sendo os que mais se movem — BMGB4, BPAC11, ITUB4, ITUB3,
BRSR6 —, e aquela conclusão se sustenta.

Em 04/09/2024 a leitura é a mesma: mediana de 0,0%, correlação de postos de
**0,968** entre a montagem só de mercado e a anual da CVM. **Remedida depois da
decisão 78: 0,977**, e USIM3 e USIM5 saem da lista de movimentos — eram o ano
de 2023 apagado por uma DFP reapresentada em 2025 (§3.5).

---

## 3. A série ancorada

### 3.1 Como ela é montada

Se o documento mais recente publicado é o ITR de 30/06, a série inteira vira
doze meses terminados em 30/06 de cada ano:

```
fluxo_jun/y  = DFP_{y−1} + acumulado_jun/y − acumulado_jun/{y−1}
estoque      = balanço de 30/06/y
publicidade  = DT_RECEB do ITR
```

Todos os pontos a exatamente um ano de distância — é o espaçamento que as
guardas do motor presumem. Funciona também em exercício de abril a março, e a
identidade de que um "trimestral" de doze meses devolve o próprio exercício
está nos testes.

### 3.2 O buraco da fonte, e o que ele fez

**Em 14/09/2026 a CVM não publica `itr_cia_aberta_2025.zip`.** O diretório
lista 2017 a 2024 e 2026, e o endereço devolve 404. O baixador pulou em
silêncio.

A primeira versão da série ancorada montou junho/24 seguido de junho/26, e as
guardas leram os dois anos como um. Em 04/09/2026:

| | |
|---|---:|
| mediana do `\|Δ potencial\|` | **25,3%** |
| `\|Δ\|` > 10 p.p. | 86 |
| QUAL3 | −22,0% → **+908,0%** |
| MOVI3 | −52,7% → +424,4% |

A série agora **recua inteira para a âncora de DFP** quando há buraco
([decisão 73](../decisoes/073-os-doze-meses-ancoram-a-serie-e-nao-entram-por-padrao.md)).
Com o ITR de 2025 ausente, isso acontece hoje em todo o universo.

### 3.3 O efeito, onde a fonte é contígua

Medido em **04/09/2024**, âncora no 2T24:

| | |
|---|---:|
| séries ancoradas em trimestre | **349** de 371 |
| recuaram para DFP | 22 |
| avaliados, anual → ancorada | 113 → 108 |
| mediana do `\|Δ potencial\|` | **9,8%** |
| `\|Δ\|` > 10 p.p. | 51 |
| **correlação de postos anual × ancorada** | **0,816** |

Os que mais se moveram: CSNA3 +136% → −47%, CAML3 +194% → +16%, RANI3 +132% →
−21%, LREN3 −58% → +66%.

> **Esta tabela foi medida com dois defeitos da montagem**, corrigidos pela
> [decisão 78](../decisoes/078-a-mescla-nao-empresta-fluxo-de-outra-janela.md).
> Os números corrigidos estão na §3.5, e a conclusão desta seção sai mais
> forte com eles.

### 3.4 Defeito ou sensibilidade?

Conferido no caso mais extremo, número a número:

| CSNA3 | anual | doze meses em junho |
|---|---:|---:|
| receita 2023 / jun-24 | R$ 45,44 bi | R$ 43,72 bi |
| lucro 2022 / jun-23 | **+R$ 2,17 bi** | **−R$ 0,10 bi** |
| lucro 2023 / jun-24 | +R$ 0,40 bi | +R$ 0,24 bi |

A soma está certa: `45,44 + 20,59 − 22,31 = 43,72`. E o que ela mostra é real —
a CSN entrou em prejuízo no primeiro semestre de 2023, e a série de junho vê a
virada seis meses antes da de dezembro. As guardas do motor reagem a isso.

**Não é defeito da construção; é o motor sensível à janela.** Deslocar o
exercício seis meses, com o mesmo preço, muda a ordenação de forma relevante.
Se isso é informação nova ou ruído é exatamente a pergunta da coorte
trimestral (C1c), e por isso a série ancorada **não entra por padrão**.

### 3.5 Remedido depois da decisão 78

Dois defeitos, achados em revisão depois das medições acima:

- **A mescla emprestava fluxo de outra janela.** O ponto de junho herdava do
  dezembro anterior a despesa de juros, o NOPAT publicado e o LPA.
- **DFP recebida depois da data ocupava o ano** e apagava o exercício de
  mercado dele. Doze tickers do universo em 04/09/2024.

Em 04/09/2024, na mesma execução:

| | antes | corrigido |
|---|---:|---:|
| séries do universo ancoradas em trimestre | — | 341 |
| avaliados, anual → ancorada | 113 → 108 | 113 → 108 |
| mediana do `\|Δ potencial\|` | 9,8% | **14,8%** |
| `\|Δ\|` > 10 p.p. | 51 | **60** |
| **correlação de postos anual × ancorada** | **0,816** | **0,683** |

Os que mais se movem agora: POSI3 +989% → +499%, PCAR3 +324% → +12%, BEEF3
+393% → +151%, CSNA3 +136% → −80%, RAPT4 +142% → −67%.

**A mistura amortecia a diferença.** Pegando emprestado do dezembro, o ponto de
junho ficava parcialmente ancorado em dezembro; sem isso, a sensibilidade à
janela é maior do que a medida.

**A primeira correção passou do ponto**, e o que ela revelou virou item do
plano. Recusar também o VPA e a contagem do exercício fez 106 de 113 avaliados
serem recusados como insolventes: a base de patrimônio da cascata é **sempre**
`VPA × contagem do exercício`, e o patrimônio que a CVM traz não é lido (A1.11).

**Uma ressalva sobre comparar execuções.** Entre duas execuções com meia hora
de intervalo, 26 ativos mudaram de valor **na montagem só de mercado**, todos de
M em diante — o cache da validação venceu no meio de uma delas, e a fonte
devolveu série revisada. As comparações acima são todas dentro de uma mesma
execução, onde isso não entra.

---

## 4. O que fica em aberto

- **O ITR de 2025 na fonte.** Até a CVM republicá-lo, a série ancorada é
  idêntica à anual. O baixador passou a precisar avisar ano ausente em vez de
  pular em silêncio.
- **C1c decide o padrão.** A série ancorada só deve virar padrão se a coorte
  trimestral mostrar que ela ordena o retorno melhor que a anual.
- **As séries que recuaram em 2024** não foram investigadas uma a uma.
- **A base de patrimônio do ponto de junho é a de dezembro** (decisão 78). Ler
  o patrimônio da CVM na data do ponto é o A1.11.
- **O ano de DFP reapresentada fica com o mercado**, porque a ingestão só guarda
  a última versão. É o B8.
