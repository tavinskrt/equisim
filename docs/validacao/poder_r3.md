# O poder do teste do R3 — item C6

> **Medido em 22/09/2026**, sobre as séries de coeficientes de coorte do motor
> que fecha a Fase 3 ([habilidade_trimestral.md](habilidade_trimestral.md) §9).
> Dados em [poder_r3.json](poder_r3.json).
>
> ```bash
> dart run tool/regressao_condicional.dart --trimestral
> dart run tool/poder_r3.dart
> ```

## 0. A pergunta

O R3 reprovou: nenhuma das cinco ordenações passa no critério da decisão 96.
**Isso só diz algo sobre o motor se o teste pudesse ter passado.** Um teste que
só detecta efeitos que nenhum preditor real tem reprova qualquer motor, e a
reprovação não distingue «não há habilidade» de «não dá para ver». Esta medição
separa as duas.

## 1. O modelo

A série de coeficientes de coorte é `μ + e_t`, com `e_t` a soma de `L + 1`
choques normais independentes — a estrutura que a sobreposição de coortes
trimestrais produz, e a mesma com que a decisão 96 simula o crítico. O desvio
de `e_t` é o observado em cada ordenação, **corrigido pela sobreposição**: sob
ela `E[s²] = σ²·c`, e usar o `s` cru subestimaria o ruído e inflaria o poder.
Para cada efeito verdadeiro `μ`, o poder é a fração de séries simuladas em que
o critério passa — `t` corrigido acima do crítico **e** Newey-West acima de 2.

**A simulação está calibrada**: com `μ = 0` ela passa em **2,4%** das séries,
contra o nível nominal de 2,3% que o critério declara. O teste
`test/tool/poder_r3_test.dart` cobra isso.

## 2. O resultado

> Sobre o motor com o item B26 corrigido (decisão 130) — o que fecha a rodada.

**36 meses** — 22 coortes, 11 sobreposições, crítico de 2,70:

| ordenação | média | σ por coorte | poder no efeito observado | **efeito mínimo detectável (80%)** | limite superior | coortes para 80% no efeito observado |
|---|---:|---:|---:|---:|---:|---|
| **potencial dado o B/M** | 0,052 | 0,258 | 4% | **0,62** | 0,52 | nunca, em 40 anos |
| IC do potencial | 0,105 | 0,241 | 8% | 0,58 | 0,54 | nunca, em 40 anos |
| IC do book-to-market | 0,158 | 0,118 | **37%** | 0,28 | 0,37 | 66 — retornos em **2037** |
| IC do lucro sobre o preço | 0,125 | 0,177 | 14% | 0,43 | 0,44 | nunca, em 40 anos |
| IC do composto | 0,151 | 0,183 | 18% | 0,44 | 0,48 | 154 — retornos em 2059 |

**12 meses** — 30 coortes, 3 sobreposições:

| ordenação | média | poder | **efeito mínimo detectável (80%)** | limite superior |
|---|---:|---:|---:|---:|
| **potencial dado o B/M** | 0,047 | 9% | **0,20** | 0,20 |
| IC do potencial | 0,071 | 18% | 0,20 | 0,21 |
| IC do book-to-market | 0,086 | 27% | 0,18 | 0,22 |

## 3. O que isto diz

**O teste não tinha como aprovar nenhum motor realista em 36 meses.** O menor
coeficiente que ele vê com 80% de chance é **0,62** para o critério do R3, e
**0,28** mesmo com a estabilidade do book-to-market. Correlações de ordem desse
tamanho não aparecem na literatura para nenhum sinal — as dos fatores mais
estudados ficam em décimos baixos. **O book-to-market, a anomalia mais
documentada que existe, tem só 37% de chance de passar** no próprio efeito que
mostrou, e precisaria de 66 coortes para chegar a 80% — retornos disponíveis em
2037.

**Mas o motor não reprova só por falta de poder.** Duas coisas são dele:

1. **A estimativa pontual é pequena.** O que o potencial acrescenta ao
   book-to-market é 0,052, contra 0,158 do próprio book-to-market. Não é um
   efeito grande escondido pelo ruído: é um efeito pequeno.
2. **O sinal é instável.** O σ do potencial por coorte é **o dobro** do do
   book-to-market (0,24 contra 0,12): ele acerta o sinal em 13 de 22 coortes,
   contra 20 de 22. Com esse ruído, nem 40 anos de coortes bastariam para
   confirmar o efeito que ele mostrou.

**O que a amostra descarta, e o que não.** Em 36 meses ela não descarta nada de
útil — o limite superior do potencial condicionado é 0,52. **Em 12 meses
descarta um pouco**: o coeficiente condicionado fica abaixo de **0,20** ao nível
do critério. É a leitura mais informativa que os dados sustentam.

## 4. Consequência para o R3

«Habilidade **comprovada**» não é atingível com a série brasileira de 2018 a
2025, **para nenhum motor**, no critério que o projeto fixou para 36 meses. O
que é atingível — e está atingido — é **habilidade testada, com o poder
declarado**: o motor foi medido pelo instrumento que se fixou antes de medir, a
reprovação está registrada, e está dito até onde o instrumento enxerga. A
decisão entre as duas leituras é do usuário (item C8).
