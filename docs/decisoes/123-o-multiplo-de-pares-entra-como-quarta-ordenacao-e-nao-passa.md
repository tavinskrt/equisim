---
numero: 123
titulo: O múltiplo de pares entra como quarta ordenação candidata, e não passa — a regra da decisão 103 segue devolvendo prêmio nenhum
status: aceita
origem: voce
data: 2026-09-21
citacao: >
  Seus itens de escopo para esta rodada são B20, B22, B23, B21 e C5.
afeta:
  - tool/multiplos_ordenacao.dart
  - tool/backtest_valuation.dart
  - docs/validacao/multiplos_ordenacao.md
substitui: []
---

## Contexto

A [decisão 103](103-o-premio-do-retorno-esperado-sai-da-ordenacao-comprovada-e-hoje-nao-ha.md)
fixou, **antes de medir**, que o prêmio do retorno esperado sai da **primeira
ordenação que passar** no critério da decisão 96 — e que, não passando nenhuma,
o prêmio é nenhum. Foram três candidatas: o potencial do DCF, o book-to-market e
o composto.

O item B5 acrescentou um quarto candidato sem querer: a correlação de postos
entre o potencial do DCF e o dos múltiplos de pares é de **0,470**, com o mesmo
sinal em 63 de 93. Sinal distinto, e não cópia — o que obriga a medi-lo pela
mesma regra. Virou o item B22.

## O que foi medido

Sobre as coortes **reexecutadas nesta rodada** (item C5): o motor da Fase 3, e
não mais o da decisão 102 ([multiplos_ordenacao.md](../validacao/multiplos_ordenacao.md)).

**A mediana setorial é da própria coorte**, e não do pacote de 14/09/2026 —
usá-lo numa observação de 2018 seria conhecimento futuro pela porta da frente. E
**o potencial não passa pela ponte**: ele é `valor implicado ÷ valor de mercado
− 1`, com os dois lados da companhia inteira.

**36 meses, 2.165 observações, 22 coortes:**

| ordenação | IC | `t` corrigido / crítico | positivas | passa |
|---|---:|---:|---:|---|
| book-to-market | +0,157 | 1,98 / 2,70 | 20 de 22 | não |
| composto | +0,147 | 1,17 / 2,70 | 18 de 22 | não |
| lucro sobre preço | +0,124 | 1,02 / 2,70 | 18 de 22 | não |
| potencial do DCF | +0,089 | 0,53 / 2,70 | 13 de 22 | não |
| **múltiplo de pares** | **+0,075** | **1,04** / 2,70 | 18 de 22 | **não** |

Em 12 meses, o múltiplo é o mais fraco dos cinco: +0,029, com `t` corrigido de
0,70 contra 2,24.

## Decisão

**O múltiplo de pares entra como quarta candidata, e o resultado dele não muda
nada.**

1. **Ele não passa.** `t` corrigido de 1,04 contra 2,70 em 36 meses, e 0,70
   contra 2,24 em 12.
2. **A regra da decisão 103 não muda.** Ela foi escrita para aceitar candidatos
   novos sem renegociação, e é o que acontece aqui: o prêmio do retorno esperado
   continua sendo **nenhum**.
3. **Ele fica medido a cada rodada**, junto com as outras quatro, pela mesma
   ferramenta. Acrescentar candidato depois de ver resultado é o que a decisão
   103 existe para impedir; acrescentar **antes** de medir, e publicar o
   resultado qualquer que seja, é o contrário disso.
4. **A mediana continua sendo da coorte.** Trocá-la pela do pacote versionado
   seria trocar a medição por conhecimento futuro, e a diferença entre as duas
   não é ajuste: é outro instrumento.

## O que a medição mostrou de passagem

**O múltiplo é mais consistente que o potencial, e menos forte.** `t` bruto de
4,27 contra 2,18, Newey-West de 2,65 contra 1,26, 18 coortes positivas contra
13 — e IC de 0,075 contra 0,089. Ele erra menos vezes e acerta menos.

**E o book-to-market deixou de passar.** Com as coortes do motor da decisão 102
ele tinha `t` corrigido de **2,52** contra 2,70 — perto. Com as coortes
reexecutadas, **1,98**. A ordenação que a §0 usou para acusar o motor também não
sobrevive ao critério do R3, e isso é fato do **critério**, não do motor: a
correção pela sobreposição é dura com 22 coortes trimestrais de 36 meses.

## Consequências aceitas

**Cinco ordenações medidas, nenhuma aprovada.** O retorno esperado continua
sendo o `Ke` de cada ativo, e a tela de metas continua dizendo por quê (decisão
99). **O que muda é que a lista de candidatas é maior, e a resposta é a mesma.**

**O múltiplo herda as limitações do método.** Ele é do exercício publicado, e
não normalizado: companhia cíclica no fundo do ciclo parece cara. A
[decisão 118](118-a-triangulacao-por-multiplos-e-segunda-leitura-declarada-e-nao-entra-no-preco.md)
já declarou isso, e vale igual aqui.

**A comparação é entre ordenadores, e não entre coberturas.** Nenhuma das 2.165
observações ficou sem mediana usável, de modo que as cinco foram medidas
exatamente sobre o mesmo conjunto. Se um dia o múltiplo perder observações, a
comparação precisa ser refeita no subconjunto comum, ou passa a medir cobertura.
