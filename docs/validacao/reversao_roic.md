# A reversão da rentabilidade à média — item B19

> **Medido em 21/09/2026**, sobre a entrada congelada do gabarito da cascata.
>
> ```bash
> dart run tool/gabarito_cascata.dart     # congela a entrada
> dart run tool/reversao_roic.dart        # grava reversao_roic.json
> ```
>
> Montagem conferida contra o gabarito ativo a ativo: zero divergências.
>
> **Remedido** depois da [decisão 113](../decisoes/113-o-caixa-rende-a-taxa-livre-de-risco-e-nao-o-custo-de-emprestimo.md),
> que subiu o custo de capital e reduziu os avaliados de 103 para 99. A
> [decisão 112](../decisoes/112-a-rentabilidade-reverte-a-mediana-do-mercado-e-nao-ao-custo-de-capital.md)
> foi escrita com os números anteriores — 18,6% de custo e 12,9% de retorno
> implícito —, e a conclusão dela fica de pé com os de hoje: o destino medido
> continua sendo 9,5%, e o motor continua entre ele e o custo de capital.

## 0. A pergunta que o B12 deixou

O terminal neutro mantém, para sempre, o retorno que o capital instalado alcança
na projeção — e ele é de **0,70 vez** o custo de capital na mediana
([terminal_excedente.md](terminal_excedente.md)). A
[decisão 107](../decisoes/107-o-terminal-neutro-e-do-capital-novo-e-o-instalado-mantem-o-retorno-que-tem.md)
manteve o número por não haver medição de reversão à média; convergir o terminal
ao custo de capital move **+11,8%** do preço justo mediano.

São duas perguntas, e só as duas juntas decidem: **em quanto tempo** a
rentabilidade reverte, e **para onde**.

O `ROIC` medido é o do motor — `lucro_t ÷ base_{t−1}`, de `CapitalSeries.returns`,
na convenção da via da firma, sobre a mesma série limpa que a cascata usa. O
spread é contra a **mediana transversal do ano**, que é o que a competição
equaliza; a mediana de um ano com menos de 20 papéis não define referência.

## 1. A velocidade: rápida

**AR(1) no painel**, 3.246 pares de anos consecutivos, 307 ativos:

| | |
|---|---:|
| `φ` | **0,237** |
| `t` | 47,4 |
| R² | 0,409 |
| meia-vida | **0,5 ano** |

**AR(1) ativo a ativo**, nos 219 com pelo menos oito pares (mediana de 14):

| `φ` | p25 | mediana | p75 |
|---|---:|---:|---:|
| | 0,182 | **0,392** | 0,614 |

O viés de Kendall do AR(1) é da ordem de `−(1 + 3φ)/n`: desprezível no painel
(−0,0005) e de **−0,171** no estimador por ativo com dez pares. O `φ` por ativo
sem viés fica perto de 0,56, e é a cota superior da leitura; o do painel é a
inferior, porque pooling firmas heterogêneas e erro de medida no `ROIC` puxam a
persistência para zero. **Os dois estão aqui, e a faixa é a resposta.**

## 2. O que sobra, sem supor forma funcional

A leitura direta, que não depende de AR(1) nenhum: dos que estavam no quinto
superior — ou inferior — do spread, quanto restava `h` anos depois?

| horizonte | quinto superior | sobra | quinto inferior | sobra | n |
|---|---|---:|---|---:|---:|
| 1 ano | 14,3% → 10,3% | 0,72 | −10,6% → −8,1% | 0,77 | 3.246 |
| 3 anos | 14,3% → 5,3% | 0,37 | −10,3% → −4,2% | 0,40 | 2.591 |
| 5 anos | 12,5% → 1,7% | **0,14** | −9,4% → −1,8% | 0,19 | 2.017 |
| 10 anos | 11,3% → 0,1% | **0,01** | −9,8% → −2,1% | 0,21 | 968 |

**Em dez anos não sobra nada da vantagem relativa** — e é justamente o horizonte
que a projeção explicita. A desvantagem some mais devagar que a vantagem: 0,21
contra 0,01 em dez anos, e é o que se esperaria de uma amostra de sobreviventes.

## 3. O destino: a metade do custo de capital

| | |
|---|---:|
| `ROIC` mediano do universo, mediana dos anos | **9,5%** |
| custo de capital de equilíbrio mediano, dos 99 avaliados | **18,9%** |

Por ano, a mediana do universo:

| ano | mediana | ativos | | ano | mediana | ativos |
|---|---:|---:|---|---|---:|---:|
| 2011 | 10,3% | 214 | | 2019 | 8,8% | 221 |
| 2012 | 9,4% | 219 | | 2020 | 9,7% | 243 |
| 2013 | 8,3% | 220 | | 2021 | **15,7%** | 265 |
| 2014 | 7,6% | 220 | | 2022 | 11,7% | 282 |
| 2015 | 6,8% | 214 | | 2023 | 10,0% | 283 |
| 2016 | **6,0%** | 214 | | 2024 | 9,8% | 278 |
| 2017 | 7,8% | 222 | | 2025 | 9,6% | 276 |
| 2018 | 9,5% | 223 | | | | |

**Em nenhum dos quinze anos a mediana do universo chegou perto do custo de
capital.** A rentabilidade das companhias abertas brasileiras reverte — e reverte
para cerca de metade do que o capital delas custa.

## 4. O que se decidiu

[Decisão 112](../decisoes/112-a-rentabilidade-reverte-a-mediana-do-mercado-e-nao-ao-custo-de-capital.md):
**o terminal fica**, agora por medição em vez de por ausência dela.

- Convergir ao custo de capital seria afirmar uma rentabilidade que a seção
  transversal nunca teve.
- O retorno implícito do capital instalado no terminal do motor — **13,1%** —
  já está entre a mediana do mercado (9,5%) e o custo de capital (18,9%).
- E a alternativa que a medição sugeriria — convergir a 9,5% — andaria **para
  baixo**: a escolha da decisão 107 não é a otimista.

## 5. O que isto não diz

- **O destino é alvo móvel.** A mediana vai de 6,0% a 15,7% em quinze anos: ela
  é cíclica, e convergir o terminal a um número fixo congelaria um instante do
  ciclo.
- **Parte da reversão é ruído contábil.** Item não recorrente move o `ROIC` de um
  ano, e AR(1) sobre série com erro de medida é enviesado para zero. O `φ` do
  painel é cota inferior da persistência.
- **A amostra é de sobreviventes**: as listadas de hoje, com série desde 2010.
  Isso infla a mediana e subestima a persistência do lado ruim — as duas
  distorções andam contra converger, e não a favor.
- **O spread é contra a mediana, e não contra o custo de capital de cada
  ativo.** Medir contra `r_t` exigiria o custo de capital histórico de cada
  papel, que o projeto não guarda; a diferença entre os dois é um termo comum,
  que desloca o nível e não a persistência.
