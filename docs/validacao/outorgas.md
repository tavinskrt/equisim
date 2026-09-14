# O prazo das outorgas — item A6

Medido em 14/09/2026. Ferramentas: `tool/cvm_baixar.py --docs FRE`,
`tool/fre_outorgas.dart` e `tool/padrao_ligar.dart`.
[Decisão 88](../decisoes/088-o-prazo-da-concessao-corta-o-excedente.md).
Retoma o [D8](concessao.md) e as [limitações §2.16](limitacoes.md).

## 1. A pergunta estava mal posta

O D8 mediu o que aconteceria se o contrato **acabasse** em dez anos: o preço
justo mediano dos expostos cairia para 0,80 do publicado. A conta truncava a
perpetuidade e **não devolvia nada** no fim — e o próprio registro já dizia que
truncar sem indenizar trocaria um viés por outro.

A conta certa inclui o que o contrato devolve: o capital investido, pela
amortização ao longo do prazo, pela indenização do investimento não amortizado na
reversão ou por uma renovação que refaz a tarifa ao custo de capital.

## 2. O que o prazo corta, e o que não corta

O terminal neutro que a [decisão 50](../decisoes/050-concessao-nao-preserva-excedente.md)
impõe a toda concessão, `lucro_{N+1}/r`, afirma que o **capital novo** não cria
valor. Não afirma que o capital **existente** deixa de render acima do custo: o
lucro do ano N+1 carrega o retorno dele, e dividido por `r` o excedente vale para
sempre. Em termos de lucro econômico:

```
VT_perpétuo = capital_N + EVA_{N+1} / r         EVA_{N+1} = lucro_{N+1} − r · capital_N
```

**É esse excedente que o contrato corta.** Um contrato que acaba `m` anos depois
da projeção paga o excedente até lá e devolve o capital:

```
VT_contrato = capital_N + EVA_{N+1} · (1 − (1+r)^−m) / r
```

Com `m → ∞` volta ao perpétuo; com o contrato acabando no ano N, é o capital. E
**com o capital rendendo exatamente o custo dele, `EVA = 0`, o prazo não muda
nada** — é a única identidade verdadeira aqui, conferida em
`concession_horizon_test.dart`. Com retorno acima do custo, o contrato corta
valor; abaixo, a indenização pelo contábil devolve **mais** do que o negócio
renderia.

**O capital sai da própria projeção.** O do primeiro ano é o lucro dele sobre o
retorno do capital, e cada ano soma o reinvestimento `b_t · lucro_t`; no fim, é o
capital que rende o lucro de N+1. Sem retorno utilizável não há capital a apurar,
e o terminal fica perpétuo, declarado.

**Se o contrato acaba dentro da projeção**, ela termina nele, e o terminal é o
capital naquela data.

> **Correção feita na mesma rodada.** A primeira versão deste item afirmou que o
> terminal neutro **já era** o valor do contrato finito, para qualquer prazo além
> da projeção — e o teste que a sustentava definia o capital como `lucro/r`, o
> que torna a identidade verdadeira por construção. A lente `metodo` apontou que
> `lucro_{N+1}/r` perpetua o excedente do capital existente; conferido na
> álgebra da projeção, procede.

A convenção de meio de ano deixa uma diferença de segunda ordem: o terminal
recebe o levantamento `√(1+r)`, e a devolução do capital em T, a rigor, não.

## 3. A fonte, e por que ela é fraca

O quadro de intangíveis do Formulário de Referência (item 9.1.b) lista cada
concessão com a coluna `Duracao` **em texto livre**: "até julho/2045", "De
11/08/2017 até 11/08/2047", "30 anos, a partir de 03/2019", "2028, prorrogável
até 2058", "Prazo indeterminado". `FreConcessionTerm` lê as formas que aparecem,
e recusa o que não dá data absoluta.

| | |
|---|---:|
| tickers com concessão no FRE, pela ponte da CVM | 76 |
| tickers no pacote | **35** |
| deles, concessão pela classificação da B3 | 37 dos 76 |

**Três limites, e todos declarados:**

1. **Sem peso por contrato.** A TAEE11 tem 39 outorgas, a CPFE3 117. O prazo do
   ativo é a **mediana** dos fins vigentes: um contrato pequeno e extremo não a
   arrasta, mas ela não é o prazo ponderado pela receita.
2. **O quadro para em 2023.** O formulário mudou de formato em 2024 e os dados
   abertos não trazem mais os intangíveis. Nas concessionárias do universo, o
   formulário mais novo com o quadro é de referência 2022.
3. **Formulário velho repete contrato renovado com o prazo antigo** — a
   distribuição da Cemig aparece "até fevereiro de 2016" no formulário de 2019.
   Por isso só entra formulário a partir de 2020, e só outorga vigente na data
   dele. CMIG4, SAPR11, REDE3 e AFLT3 ficam de fora.

E há concessionária sem concessão no quadro: MOTV3 não tem linha, RAIL3 e SBSP3
só listam marcas, ECOR3 remete a outro item.

## 4. Os contratos que acabam dentro da projeção

| ativo | mediana dos fins vigentes | outorgas vigentes | anos |
|---|---|---:|---:|
| ENMT3, ENMT4 | 11/12/2027 | 1 de 1 | 1 |
| EQTL3, EQPA3, EQPA5 | 31/12/2028 | 4 de 4 | 2 |
| GEPA3, GEPA4 | 21/09/2029 | 10 de 10 | 3 |
| EGIE3 | 26/08/2033 | 12 de 12 | 7 |
| TAEE11, TAEE3, TAEE4 | 15/03/2035 | 39 de 39 | 8 |

Os outros do pacote acabam depois de 2036 — ALUP11 em 2042, AXIA3 em 2042, CPFE3
em 2040, ENGI11 em 2045 —, e para eles o contrato corta o excedente sobre o
capital nesses anos, e não na projeção.

## 5. O efeito, na mesma execução

Sobre os 128 avaliados, na medição final da Fase 1
([fase1_padrao.md](fase1_padrao.md)):

| | sem prazo | com prazo |
|---|---:|---:|
| potencial mediano | −45,5% | −45,5% |
| `\|Δ\|` > 10 p.p. | | 1 |
| correlação de postos | | **0,998** |

| ativo | fim do contrato | sem prazo | com prazo |
|---|---|---:|---:|
| EGIE3 | 26/08/2033 | +3,6% | **−30,5%** |
| ALUP11 | 25/01/2042 | −32,8% | −28,3% |
| AXIA3 | 31/05/2042 | −81,2% | −77,5% |
| TAEE11 | 15/03/2035 | −42,4% | −39,7% |
| ENGI11 | 07/07/2045 | +51,7% | +50,5% |
| CPFE3 | 30/04/2040 | −45,2% | −45,4% |
| EQTL3 | 31/12/2028 | −26,5% | −26,7% |

**O excedente tem sinal.** Na EGIE3 o capital rende acima do custo, a projeção
termina em 2033 e o excedente dos anos seguintes sai: 34 p.p. Na ALUP11, na AXIA3
e na TAEE11 o capital apurado rende **abaixo** do custo, e devolvê-lo pelo
contábil no fim do contrato vale mais do que rendê-lo para sempre: o preço sobe
de 3 a 5 p.p. O capital apurado é o implícito na projeção — lucro sobre retorno
—, e não a base regulatória; quanto eles se afastam, nas concessionárias que
registram o contrato como ativo financeiro, não foi conferido.

**A EQTL3 é o caso frágil, e mexe pouco.** É um grupo com distribuição em vários
estados, transmissão, saneamento e renováveis, e a mediana de quatro outorgas no
formulário de 2022 — duas de distribuição em 2028, "prorrogável até 2058" —
encurta a projeção do grupo inteiro para dois anos. O efeito é de 0,2 p.p.
