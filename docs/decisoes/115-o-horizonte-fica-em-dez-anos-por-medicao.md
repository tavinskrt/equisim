---
numero: 115
titulo: O horizonte fica em dez anos, e agora por medição — o nível não depende dele, e o peso do terminal sim
status: aceita
origem: voce
data: 2026-09-21
citacao: >
  Seus itens de escopo para esta rodada são B6, B7, B3, B4 e B5.
afeta:
  - tool/horizonte.dart
  - tool/validation/congelado.dart
  - docs/validacao/horizonte.md
substitui: []
---

## Contexto

O horizonte de projeção explícita é fixo em **dez anos** para todo ativo,
independentemente de ciclo, setor ou maturidade. O número é herança do plano
original e nunca foi medido: o item B6 pedia a varredura de 5 a 20 anos «sobre o
universo e sobre a habilidade», e uma decisão que escolhesse.

## O que foi medido

Sobre a entrada congelada do gabarito, com a montagem de dez anos conferida
ativo a ativo contra ele ([horizonte.md](../validacao/horizonte.md)).

**A mediana do preço justo anda entre −1,0% e +0,8% de cinco a vinte anos.**
Quadruplicar a projeção explícita não move o ativo mediano.

**O peso do terminal vai de 59,2% a 8,4% no mesmo intervalo.**

| anos | avaliados | mediana vs 10 | p10 | p90 | peso do terminal | postos vs 10 |
|---:|---:|---:|---:|---:|---:|---:|
| 5 | 102 | +0,8% | −3,3% | +21,3% | 59,2% | 0,9937 |
| 10 | 97 | — | — | — | 30,5% | 1,0000 |
| 20 | 94 | −1,0% | −23,3% | +3,0% | 8,4% | 0,9930 |

**Cinco contra vinte: postos de 0,9828.**

## Decisão

**Dez anos ficam, por medição.**

1. **A escolha não é de nível.** Nenhum horizonte da faixa move a mediana mais
   que 1,0%, e a ordenação é praticamente a mesma em todos.
2. **A escolha é de onde o valor mora.** A cinco anos o terminal responde por
   **59%** do preço justo, e o modelo passa a ser majoritariamente a sua parte
   mais frágil — a que a [decisão 107](107-o-terminal-neutro-e-do-capital-novo-e-o-instalado-mantem-o-retorno-que-tem.md)
   e a [decisão 112](112-a-rentabilidade-reverte-a-mediana-do-mercado-e-nao-ao-custo-de-capital.md)
   examinaram. A vinte ele é 8%, mas a projeção explícita passa a extrapolar
   fundamento duas décadas à frente, as caudas se abrem para baixo (p10 de
   −23,3%) e **três ativos deixam de ser avaliáveis**, porque uma projeção mais
   longa dá mais anos para o capital próprio desaparecer dentro dela (decisões
   45 e 110).
3. **Dez fica entre os dois males**, com 30,5% de terminal e 97 avaliados.
4. **O horizonte continua comum a todo ativo.** Horizonte por setor ou por ciclo
   é outra pergunta, e prazo de concessão já é tratado por outro caminho
   (decisão 88).

**O motor não muda.** O que muda é o fundamento: dez anos deixa de ser convenção
herdada e passa a ser escolha com a varredura ao lado.

## O que a varredura mostrou de graça

**A invariância ao horizonte é evidência independente de que o terminal neutro
está bem especificado.** `VT = lucro_{N+1} ÷ r` afirma `RONIC_∞ = r`: o capital
novo não cria valor, e estender a projeção explícita transfere valor do terminal
para os fluxos **sem mudar o total**. É exatamente o que se observa, e não era o
que a varredura procurava.

## Consequências aceitas

**A perna da habilidade não foi medida, e depende do C5.** O que está no lugar é
o limite superior do efeito: com postos de 0,9828 entre os extremos e `IC` de
0,078, a desigualdade `|IC(y) − IC(x)| ≤ (1−ρ)|IC(x)| + √(1−ρ²)` dá **+0,20** —
**e não é apertada**. O pior caso levaria o IC a 0,26, acima do book-to-market,
mas exigiria que 1,5% da variância dos postos fosse preditor perfeito do
retorno. **A aposta de que a habilidade esteja escondida no horizonte é fraca, e
não está descartada**; o teste é barato quando as coortes voltarem.

**MOTV3, ENGI11 e GOAU4 voltam a cinco anos.** Os que as decisões 113 e 119
tiraram por estrutura de capital reaparecem com projeção curta — não porque o ativo melhore,
mas porque a conta tem menos tempo para quebrar. **Escolher o horizonte pela
cobertura seria escolher a projeção que esconde o problema**, e é motivo a mais
para não encurtar.

**As caudas se movem, e a mediana não.** Quem lê o preço justo de um ativo
específico nas caudas está lendo um número que o horizonte move em até 20%. A
declaração disso é o peso do terminal, que já sai nos diagnósticos e no rastro
desde a decisão 107.
