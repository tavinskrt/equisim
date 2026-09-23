---
numero: 129
titulo: O R3 não passa sobre o motor final, o teste declara o poder que tem, e a réplica fora da amostra fica pré-registrada
status: aceita
origem: voce
data: 2026-09-22
citacao: >
  Agora que, do documento plano-motor-de-referencia.md, resta apenas medir a
  habilidade do motor, peço que finalize completamente o plano com o item C1.
afeta:
  - docs/plano-motor-de-referencia.md
  - docs/validacao/poder_r3.md
  - docs/validacao/poder_r3.json
  - docs/validacao/habilidade_trimestral.md
  - tool/poder_r3.dart
  - test/tool/poder_r3_test.dart
substitui: []
---

## Contexto

O item C1 pedia que, com as Fases 1 a 3 fechadas, o potencial condicionado ao
book-to-market em 36 meses **passasse no critério da decisão 96 — ou que o
registro declarasse que não passa**. As três fases fecharam em 22/09/2026, e o
backtest foi reexecutado sobre o motor final: 10.919 observações, 31 coortes,
as versões antigas dos documentos, tarifa e spread medidos.

## O veredito

**O R3 não passa.** Sobre o motor que fecha a rodada — com o item B26 corrigido
(decisão 130), 10.837 observações, 31 coortes:

| 36 meses, 22 coortes | média | `t` corrigido / crítico | Newey-West | passa |
|---|---:|---:|---:|---|
| **potencial dado o B/M** | **0,052** | **0,30 / 2,70** | 0,84 | **não** |
| IC do potencial | 0,105 | 0,65 / 2,70 | 1,61 | não |
| IC do book-to-market | 0,158 | 2,01 / 2,70 | 4,23 | não |
| IC do lucro sobre o preço | 0,125 | 1,06 / 2,70 | 2,87 | não |
| IC do composto | 0,151 | 1,24 / 2,70 | 3,02 | não |
| IC do múltiplo de pares | 0,079 | 1,18 / 2,70 | 3,65 | não |

Líquido de custo de transação, nada muda (decisão 126). **A regra da decisão
103**, fixada antes de qualquer medição, **devolve prêmio nenhum**: o retorno
esperado do aplicativo continua sendo o `Ke`, como já era.

**O B26 melhorou o potencial, e não o bastante.** Antes da correção o
condicionado dava 0,028 com `t` 0,15; depois, 0,052 com 0,30. A carteira que
compra o quintil de maior potencial e vende o de menor passou de +0,75% para
**+6,0%** em 36 meses. O sinal ficou mais parecido com o que um valuation deveria
produzir, e continua longe do crítico.

## O poder do teste — o que a reprovação significa

Uma reprovação só informa sobre o motor se o teste pudesse ter aprovado. Medido
por simulação sobre a mesma estrutura de sobreposição com que o crítico é
simulado, calibrada — sem efeito, ela passa em 2,4% das séries, contra 2,3% de
nível nominal ([poder_r3.md](../validacao/poder_r3.md)):

- **em 36 meses, o menor coeficiente que o critério vê com 80% de chance é
  0,62** — e 0,28 mesmo com a estabilidade do book-to-market. Nenhum sinal
  conhecido tem correlação de ordem desse tamanho;
- **o book-to-market tem 37% de chance de passar** no próprio efeito que
  mostrou, e precisaria de 66 coortes — retornos em 2037;
- **o potencial não é só um efeito escondido pelo ruído**: a estimativa pontual
  é pequena (0,052 contra 0,158), e o sinal é duas vezes mais instável que o do
  book-to-market — acerta o sinal em 13 de 22 coortes, contra 20;
- **em 12 meses a amostra descarta alguma coisa**: o coeficiente condicionado
  fica abaixo de 0,20 ao nível do critério.

## Decisão

1. **O C1 fecha com o veredito de que o R3 não passa.** O registro o declara,
   que é o que o critério de pronto pedia.
2. **O poder do teste passa a acompanhar o veredito** (item C6): toda leitura do
   R3 diz o efeito mínimo detectável junto com o `t`.
3. **O motor não é «motor de referência» pela definição de 09/09/2026** — nenhum
   defeito conhecido, incerteza calibrada **e habilidade comprovada**. R1 e R2
   estão atingidos; o R3, não. E ele **não é atingível com a série de hoje por
   nenhum motor** no critério de 36 meses.
4. **A réplica fora da amostra fica pré-registrada** (item C7), para que a única
   via pela qual o R3 poderia vir a passar não seja contaminada:
   - **amostra**: as coortes trimestrais a partir de **31/12/2025** — nenhuma
     delas entrou em decisão alguma do motor;
   - **critério**: o da decisão 96, sem mudança, sobre o potencial condicionado
     ao book-to-market; as outras quatro ordenações são lidas como secundárias;
   - **leituras em datas fixadas agora**: 12 meses em **30/09/2029**, com 12
     coortes novas; 36 meses em **30/09/2031**, com 12 coortes novas; e a cada
     ano depois disso;
   - **proibido**: juntar as coortes de 2018 a 2025 às novas para passar, e
     escolher outra ordenação principal depois de ver as novas;
   - **mudança de motor** depois desta decisão é permitida, mas a leitura do C7
     reporta as duas versões — a do motor desta data e a do motor da data da
     leitura —, para que a réplica não vire reajuste.
5. **O que o R3 passa a exigir é decisão do usuário** (item C8): manter
   «habilidade comprovada», que a série não sustenta antes de 2037 nem para o
   book-to-market, ou ler o terceiro critério como **«habilidade testada, com o
   poder declarado»**, que está atingido. Esta decisão não troca a definição
   por conta própria.

## Consequências aceitas

**Mais engenharia não faz o R3 passar.** Mexer no motor até o potencial passar
nas mesmas 31 coortes seria o ajuste ao teste que a decisão 103 existe para
impedir — cinco ordenações já foram testadas nelas, e uma sexta escolhida
depois de ver as cinco não teria o nível que declara. O que pode mudar o
veredito é dado novo, e ele chega em tempo de calendário.

**O B26 não contradiz isso.** Ele foi achado pela lente `metodo` por ser
defeito — o rastro dizia uma coisa e a conta fazia outra —, sem olhar a
habilidade, e teria sido corrigido do mesmo jeito se piorasse o número. A
fronteira é essa: **corrigir defeito é obrigação; escolher mudança porque ela
melhora o teste é ajuste**.

**A réplica pré-registrada terá poder baixo.** Com 12 coortes, menos ainda que
as 22 de hoje. Ela é registrada assim mesmo: um sinal positivo e consistente
fora da amostra é evidência que nenhuma reanálise das coortes antigas
produz, e um negativo também informa.

**O resultado negativo é resultado.** Um motor sem defeito conhecido, com
incerteza que cobre o que promete, que diz com número que não ordena melhor que
o valor patrimonial sobre o preço e até onde o instrumento consegue ver, é uma
afirmação defensável. O que ele não pode afirmar é o que não mediu.
