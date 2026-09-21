---
numero: 112
titulo: A rentabilidade reverte, e reverte à mediana do mercado — que vive abaixo do custo de capital; o terminal fica
status: aceita
origem: voce
data: 2026-09-21
citacao: >
  Seus itens de escopo para esta rodada são B17, B18, B19, B8 e B2.
afeta:
  - tool/reversao_roic.dart
  - docs/validacao/reversao_roic.md
  - docs/validacao/terminal_excedente.md
substitui: []
---

## Contexto

A [decisão 107](107-o-terminal-neutro-e-do-capital-novo-e-o-instalado-mantem-o-retorno-que-tem.md)
manteve o terminal como está — o capital instalado seguindo com o retorno que a
projeção alcança — e disse por quê: trocá-lo por `capital_N` é afirmar reversão
da rentabilidade à média, **e o motor não mediu isso**. O custo da escolha está
medido: +14,1% no preço justo mediano se o terminal convergisse ao custo de
capital. Medir a reversão virou o item B19, e é o que decide se aquela porta se
reabre.

## O que foi medido

Sobre a entrada congelada do gabarito, em 21/09/2026, com 307 ativos e 3.246
pares ano a ano ([reversao_roic.md](../validacao/reversao_roic.md)). O `ROIC` é o
do motor — `lucro_t ÷ base_{t−1}`, de `CapitalSeries.returns` —, e o spread é
contra a **mediana transversal do ano**.

**A reversão é real e é rápida.** AR(1) no painel: `φ = 0,237`, `t` de 47,4,
meia-vida de **meio ano**. Ativo a ativo, com pelo menos oito pares, `φ` mediano
de 0,392 — e o viés de Kendall a esse tamanho é de −0,17, de modo que o número
sem viés fica perto de 0,56. Sem supor forma funcional nenhuma, o quinto
superior:

| horizonte | spread do quinto superior | sobra |
|---|---:|---:|
| 1 ano | 14,3% → 10,3% | 0,72 |
| 3 anos | 14,3% → 5,3% | 0,37 |
| 5 anos | 12,5% → 1,7% | **0,14** |
| 10 anos | 11,3% → 0,1% | **0,01** |

**Em dez anos — o horizonte que a projeção explicita — não sobra nada da
vantagem relativa.**

**Mas reverter para onde?** A mediana do `ROIC` do universo é de **9,5%**,
estável entre 6,0% e 15,7% em quinze anos. O custo de capital de equilíbrio
mediano dos avaliados é de **18,6%**.

**A rentabilidade brasileira reverte à metade do custo de capital.**

## Decisão

**O terminal fica como está**, e agora por medição em vez de por ausência dela.

1. **Converger o terminal ao custo de capital é afirmar o que a seção
   transversal nunca mostrou.** A reversão existe e é rápida, mas o destino dela
   é 9,5%, e não 18,6%. Levar o retorno do capital instalado a `r` não seria
   reversão à média — seria inventar uma rentabilidade que este mercado não teve
   em nenhum dos quinze anos medidos.
2. **O que o motor faz já está entre os dois, e mais perto do destino medido.**
   O retorno implícito do capital instalado é de 12,9% na mediana
   ([terminal_excedente.md](../validacao/terminal_excedente.md)), entre a
   mediana do mercado (9,5%) e o custo de capital (18,6%).
3. **E a alternativa andaria para baixo, não para cima.** Convergir ao destino
   medido — 9,5% — reduziria o terminal em cerca de um quarto, e o preço justo
   com ele. A escolha da decisão 107 **não é a otimista**: ela está entre as
   duas, e a direção que a medição indica é a oposta da que o B12 cogitava.

**O motor não muda.** O que muda é o fundamento: a decisão 107 deixa de repousar
em "não medimos" e passa a repousar em "medimos, e o destino não é o custo de
capital".

## Consequências aceitas

**A reversão medida é de spread relativo, e o destino é um alvo móvel.** A
mediana do universo vai de 6,0% em 2016 a 15,7% em 2021: ela é cíclica, e
convergir o terminal a um número fixo congelaria um instante do ciclo. É mais um
motivo para não converger, e é ressalva do que foi medido.

**Parte da reversão é ruído contábil.** `ROIC` de um ano carrega item não
recorrente, e AR(1) sobre série com erro de medida é enviesado para zero: o `φ`
de 0,237 do painel é cota **inferior** da persistência. O estimador por ativo,
mais alto, aponta a mesma direção com outra magnitude — e o documento traz os
dois em vez de escolher.

**A amostra é de sobreviventes.** O universo é o das listadas de hoje, com série
desde 2010: quem quebrou saiu. Isso infla a mediana do `ROIC` e subestima a
persistência do lado ruim — e as duas distorções andam **contra** a decisão de
converger, não a favor.

**Fica um fato para o artigo.** O déficit perpétuo que o terminal do motor
carrega — 0,71 vez o custo de capital — não é peculiaridade do modelo: é o que a
seção transversal brasileira mostra. A rentabilidade mediana das companhias
abertas vive abaixo do custo de capital delas, e um DCF honesto sobre essa
amostra tem de dizê-lo.
