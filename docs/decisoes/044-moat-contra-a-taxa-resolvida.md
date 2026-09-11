---
numero: 44
titulo: O veredito de vantagem competitiva passa a ser fechado contra a taxa de equilíbrio resolvida
status: aceita
origem: voce
data: 2026-09-10
citacao: >
  Prossiga para D1c e D1d se possível.
afeta:
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
substitui: []
---

## Contexto

A [decisão 42](042-caminho-de-taxas-em-producao.md) registrou como aproximação
declarada que o veredito de vantagem competitiva era medido contra a taxa
**interpolada**, não contra a resolvida pelo ponto fixo: ele é decidido antes
de o solucionador rodar.

O excedente que o veredito mede é `ROIC_ciclo − r_∞`, e `r_∞` é justamente o
que o ponto fixo devolve. Fechar o veredito contra a taxa que a própria conta
depois descarta é decidir a perpetuidade por um número que não vale.

## Decisão

**O veredito é fechado duas vezes.** O primeiro passe usa a interpolação — que
é o chute de que o ponto fixo parte. Com a taxa de equilíbrio resolvida, o
veredito é **refeito contra ela**; se o retorno terminal resultante mudar, as
premissas são reconstruídas e o ponto fixo roda de novo.

**A narrativa e a auditoria do *moat* saem depois do ponto fixo**, com o
veredito final. Publicá-las antes afirmaria um veredito que a taxa final pode
não sustentar — e o texto citaria uma taxa de equilíbrio que a conta não usou.

## Consequências aceitas

**O efeito é de segunda ordem, e era previsto.** O `λ` mediano é 0,0015, então
a maioria dos ativos não muda de veredito. O que a decisão compra é coerência:
o número citado no aviso é o mesmo que o diagnóstico carrega, e está travado
por teste.

**Custa um segundo ponto fixo** nos ativos em que o veredito muda. Cada um é
até cem iterações de um DCF barato.

**A convergência do segundo passe não é garantida.** Quando ele não converge,
vale o resultado do primeiro — o que é o comportamento conservador e fica
declarado no resultado.

**Não há terceiro passe.** O veredito refeito poderia, em tese, mudar de novo
contra a taxa do segundo ponto fixo. Iterar até o veredito estabilizar seria o
rigor completo; medido, `λ` é pequeno o bastante para a segunda ordem não
chamar uma terceira, e parar aqui é escolha declarada.
