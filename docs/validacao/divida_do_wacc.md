# A dívida do WACC — item B9

> **Medido em 20/09/2026**, sobre a entrada congelada do gabarito da cascata
> (`tool/gabarito_cascata.dart`), que fixa cache, Ibovespa e universo. Comparar
> execuções diferentes misturaria o efeito do código com a deriva do dado.

## 1. O que estava errado

A lente `metodo` apontou em 14/09/2026 que o motor usava duas réguas de dívida.
Conferido no código:

| onde | dívida | desde |
|---|---|---|
| pesos do WACC estático | **bruta** | sempre |
| realavancagem ano a ano | líquida | decisão 41 |
| desalavancagem do beta | líquida | decisão 54 |
| apuração do capital próprio | líquida | decisão 102 |

**Não é questão de estilo.** O fluxo da firma é operacional: ele não traz o
rendimento do caixa. O valor que ele desconta é o dos ativos **operacionais**, e
o capital que os financia é `E + D_líquida`. Dar à dívida o peso da bruta e
depois devolver o caixa ao acionista conta o mesmo caixa duas vezes — uma
barateando a taxa, porque a dívida entra com peso maior que o real; outra
somando-se ao capital próprio na apuração.

A régua já tinha sido decidida por medição na desalavancagem: desalavancar contra
a bruta e realavancar contra a líquida fazia a ida e a volta não se cancelarem, e
o beta que voltava era menor que o medido em 100 dos 127 avaliados (decisão 54).
O peso do WACC ficou de fora daquela decisão.

## 2. O que mudou

A dívida dos pesos passou a ser a líquida
([decisão 104](../decisoes/104-a-divida-do-wacc-e-a-liquida-como-no-resto-do-modelo.md)).
O `K_d` observado continua sendo `despesa financeira ÷ dívida bruta` — razão
sobre o que de fato paga juro —, e o prêmio de crédito continua saindo de
`dívida líquida ÷ EBITDA`.

Duas consequências de forma:

- **A ausência de estrutura é medida na bruta.** Sem dívida contratada não há
  custo de dívida a ponderar, e o desconto degenera para o `Ke`. Caixa maior que
  a dívida **não** é estrutura ausente: é estrutura conhecida, com peso negativo.
- **Com caixa líquido o WACC fica acima do `Ke`**, e a avaliação passa a dizer
  isso na tela. O ativo operacional sozinho é mais arriscado que a companhia
  inteira — a mesma leitura que o `β_U` faz ao desalavancar contra a líquida.

## 3. O efeito

| montagem | avaliados | preço justo muda em | mediana |
|---|---:|---:|---:|
| aplicativo (sem taxas resolvidas) | 114 → **115** | 73 de 114 | **+3,02%** |
| prior (com taxas resolvidas) | 104 → **102** | **2 de 102** | +1,08% |

**Na montagem do aplicativo o efeito é grande, e sobe com o caixa**: EMBJ3
+41,9%, VLID3 +17,3%, FESA4 +13,1%, MYPK3 +11,4%, RIAA3 +11,2%, MDIA3 +10,2%. A
MOVI3 volta a ser avaliada, em R$ 0,07 por papel.

**Na montagem com o prior o efeito é quase nulo** — porque ali a dívida dos pesos
já era a líquida, pela decisão 41. O que sobrou foi o chute inicial do ponto
fixo, mais caro: a PNVL3 e a VAMO3 passam a ter a estrutura recusada logo na
primeira iteração.

**A varredura do nível da curva continua sem achar ativo subindo com a taxa** na
montagem do aplicativo: 0 de 115, como antes.

## 4. O sintoma que a medição expôs, e que não é deste item

**Um desconto maior subindo o preço justo é resposta errada**, e é o que a
montagem do aplicativo deu: o WACC subiu em 73 ativos e o preço justo subiu
junto.

A causa está declarada desde a decisão 102: **sem taxas resolvidas, a via da
firma reinveste contra o WACC e desconta ao `Ke`.** A retenção é `g ÷ ROIC`, e o
retorno terminal neutro é o próprio WACC — subir o WACC sobe o retorno terminal,
baixa a retenção, engorda o fluxo, e o desconto não se move, porque ele é o `Ke`
do CAPM.

**As duas taxas só são a mesma conta no caminho resolvido**, e é exatamente por
isso que ali o efeito deste item praticamente não existe. A correção é o B11,
feito na mesma rodada
([prior_no_aplicativo.md](prior_no_aplicativo.md)): com o prior ligado, a
montagem do aplicativo passa a ser a montagem resolvida.

## 5. O que fica de fora

- **A alíquota do escudo** continua sendo a estatutária limitada pela cobertura
  de juros, e a cobertura vem da despesa financeira contaminada. Não é deste
  item.
- **O `K_d` observado** continua sendo só conferência, como a decisão 31 fixou.
- **O caixa não é avaliado à parte.** A convenção é netá-lo contra a dívida, e
  não modelar o rendimento dele: caixa que rende menos que o custo de capital
  destrói valor, e essa perda não aparece em lugar nenhum. É premissa declarada,
  e não medida.
