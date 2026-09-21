# A convenção real × nominal — item B7

> **Medido em 21/09/2026**, em forma fechada, e fixado por
> [real_nominal_test.dart](../../packages/equisim_core/test/real_nominal_test.dart).
> As magnitudes do §2.2 saem dos 97 avaliados da entrada congelada do gabarito,
> remedidas depois da
> [decisão 119](../decisoes/119-a-rota-derivada-tambem-remunera-o-caixa-pela-taxa-livre-de-risco.md).

## 0. A pergunta, e por que ela não se responde lendo o código

O motor desconta fluxo **nominal** a taxa **nominal**, e usa o IPCA em dois
lugares: no teto da perpetuidade e na âncora da Saída 2. Ler o código e conferir
que cada linha está na unidade certa **não é prova** — é a mesma inspeção que já
tinha deixado passar tudo o que as rodadas anteriores acharam.

A prova é outra. **Valor presente é quantia de hoje, e não muda quando a conta é
reexpressa em moeda constante.** Deflacione toda premissa por Fisher —
`(1+x)/(1+π) − 1` — e o preço justo tem de ficar onde estava. Onde ele não fica,
há uma premissa que só vale numa unidade, e ela precisa estar declarada.

## 1. Onde a invariância vale, e vale ao último dígito

| | desvio |
|---|---|
| desconto dos fluxos explícitos, caixa no fim do ano | **0**, a 10⁻¹² |
| decaimento linear do crescimento, de `g` a `g∞` | **0** |
| estrutura a termo do desconto, de `r` a `r∞` | **0** |

**O decaimento linear sobreviver a Fisher não era óbvio.** `g_t` e `r_t` são
interpolações **lineares** entre dois pontos, e Fisher não é linear. A conta
fecha por uma identidade:

```
1 + g'_t  =  (1 + g') − (g' − g'∞)·s_t  =  (1 + g_t) ÷ (1 + π)
```

porque `g' − g'∞ = (g − g∞)/(1+π)`. Interpolar linearmente entre dois fatores
brutos é o mesmo que interpolar entre os deflacionados. **O mesmo vale para a
taxa**, e por isso a estrutura a termo da decisão 84 não introduz desvio nenhum.

A guarda do teste: trocar Fisher por subtração move o preço justo em **mais de
5%**. Sem ela, a igualdade acima não provaria nada.

## 2. Onde não vale — e são três lugares, com forma fechada

| | fator | valor a π = 4,5% |
|---|---|---:|
| caixa no meio do ano | `(1+π)^−1/2` | **0,9782** |
| terminal neutro | `r∞ ÷ (r∞ − π)` | **1,31** na mediana |
| freio de reinvestimento | razão de razões | — |

**Os três são o mesmo fato.** Operação sobre taxa **líquida** não é neutra à
unidade; operação sobre fator **bruto** é. O desconto e o decaimento trabalham
com `(1+r)` e `(1+g)`; o terminal capitaliza por `r`, e o freio divide `g` por
`ROIC`.

### 2.1 O caixa no meio do ano

A convenção levanta o fluxo por `(1+r)^0,5`, o que o coloca no poder de compra do
**fim** do ano. O que sobra é meia inflação, e o fator é exato.

É o menor dos três, e anda **contra** a prudência: a leitura nominal fica 2,2%
acima da que o mesmo modelo em moeda constante daria.

### 2.2 O terminal neutro — o caso grande

`VT = lucro_{N+1} ÷ r` capitaliza pela taxa **líquida**, e

```
r' = (r − π)/(1 + π)   ⟹   r ÷ ((1+π)·r')  =  r ÷ (r − π)
```

Nos 97 avaliados, com `r∞` mediano de 19,3%:

| `r∞ ÷ (r∞ − π)` | p10 | p25 | mediana | p75 | p90 | máximo |
|---|---:|---:|---:|---:|---:|---:|
| | 1,231 | 1,282 | **1,305** | 1,350 | 1,390 | 1,499 |

**Um terço do terminal.** Não é resíduo numérico: é a diferença entre duas
afirmações econômicas distintas sobre o mesmo ativo.

### 2.3 O freio — e é ele a raiz dos outros dois

A retenção é `b = g ÷ ROIC`, e a identidade por trás dela é `g = b·ROIC`. Ela
vale entre grandezas **nominais**: reter `b` do lucro e aplicá-lo a um `ROIC`
nominal faz o lucro **nominal** crescer `b·ROIC`.

**Em termos reais a mesma fórmula dá outro `b`, e o que ela dá está errado.**
`b` é fração do lucro — grandeza sem unidade —, e não pode depender de em que
moeda a conta foi escrita. `g_real ÷ ROIC_real` é menor que `g_nom ÷ ROIC_nom`, e
a diferença é a parcela da retenção que repõe o capital corroído pela inflação:
uma empresa que cresce zero em termos reais ainda precisa reinvestir para manter
o capital instalado em moeda constante.

**Não é o motor que é nominal por descuido. É a identidade.**

## 3. O que isto decide

[Decisão 114](../decisoes/114-o-motor-e-nominal-e-a-nao-neutralidade-de-unidade-esta-medida.md):
**a formulação nominal é a correta, e as três não neutralidades ficam
declaradas** — a do terminal com o tamanho medido no universo.

O que muda: nada no cálculo. O que passa a existir: uma prova de que o caminho
de desconto é neutro à unidade, e o nome e o tamanho de cada lugar onde ele não
é.

## 4. O que isto não diz

- **Não mede o efeito de reformular o motor em termos reais.** O motor real não
  existe, e construí-lo exigiria reescrever `g = b·ROIC` na forma correta em
  moeda constante — que não é a que a tradução ingênua produz. O que está medido
  é **o tamanho da diferença entre as duas leituras**, e não qual delas descreve
  melhor o ativo.
- **O fator `r∞ ÷ (r∞ − π)` explode com taxa baixa.** No universo brasileiro de
  hoje, `r∞` mínimo é de 13,5% e o fator máximo é 1,50. Num mercado de juro real
  baixo, a mesma conta seria instável — é ressalva do número, não do método.
- **A inflação usada é o IPCA anualizado de dez anos, 4,5%** — a mesma âncora do
  teto da perpetuidade. Outra inflação move os três fatores, e a forma fechada
  permite recalculá-los sem reexecutar nada.
