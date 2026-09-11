---
numero: 61
titulo: A tolerância da razão de unidade é relativa, não absoluta
status: aceita
origem: parecer
data: 2026-09-11
afeta:
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/usecases_test.dart
  - docs/validacao/unidade.md
substitui: []
---

## Contexto

`ValuationCascade.quotedUnitRatio` existe porque a fonte mistura duas
convenções no mesmo ativo: as demonstrações vêm **por ação**, a cotação e o
valor de mercado vêm **por unit**. Ela mede `ações × preço ÷ valor de mercado`,
arredonda, e recusa o resultado quando ele fica longe de um inteiro.

A folga era **absoluta**: 0,12 de distância do inteiro, em qualquer `u`.

A grandeza que ela mede não é absoluta. O desvio `bruto ÷ u − 1` é exatamente a
discordância **relativa** entre `ações × preço` e `u × valor de mercado` — ou
seja, quanto o preço andou desde o instante do valor de mercado publicado. Uma
banda absoluta de 0,12 dá **12%** de folga à ação comum, onde aceitar e recusar
devolvem o mesmo 1,0 e portanto a folga não decide nada, e **1,2%** à unit de
dez ações, onde o fator errado custa dez vezes. O aperto crescia exatamente
onde o erro é mais caro.

**A SAPR11 caía por 0,0001.** Em 04/09/2026 ela media 4,8799 — a 0,1201 do
inteiro 5 — e recebia `u = 1`. É uma das duas ações que a documentação da
própria função nomeia como razão de existir dela.

## Decisão

A tolerância passa a ser relativa, em `unitRatioTolerance = 0,05`.

Cinco por cento é o que separa os dois grupos medidos sobre os 359 ativos com
razão mensurável: as nove units reais ficam todas em **2,40% ou menos** e o
falso positivo mais próximo, a EQPA5, em **10,44%** — fator de quatro de margem
para cada lado.

A troca **não é mais permissiva em toda parte**: de `u = 3` para cima afrouxa,
em `u = 2` aperta (de 0,12 para 0,10 absolutos) e em `u = 1` não decide nada.
Nenhum ativo passa a receber fator que não recebia, exceto a SAPR11.

## Consequências aceitas

**A SAPR11 sai de −58,4% para +108,0% de potencial.** O divisor deixa de ser
1.511.205.500 e passa a 302.241.100, e o preço justo vai de R$ 14,54 para
R$ 72,71 contra um mercado de R$ 34,95.

A conferência que sustenta isso não está na peça, e sim entre duas: **a unit e
a classe que a compõe descrevem o mesmo negócio.** Antes da correção a SAPR11
acusava −58,4% e a SAPR4, +115,6% — 174 pontos percentuais de contradição sobre
a mesma empresa. Depois, +108,0% contra +115,6%, e os 7,6 p.p. que sobram são o
ágio entre ON e PN dentro da cesta. Nas nove raízes com unit e outra classe
avaliável, a maior distância é essa.

O teto de `maxSharesPerUnit = 10` continua sendo o que barra a AZUL3, que mede
18,4466 a 2,48% de um inteiro — perto de 18 por coincidência, e não por ser uma
unit de dezoito ações. Proximidade de inteiro é evidência fraca quando `u` é
grande, e o teto é o que a compensa.
