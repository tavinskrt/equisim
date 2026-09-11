---
numero: 48
titulo: O caixa do exercício chega ao longo do ano, e o desconto passa a refletir isso
status: aceita
origem: voce
data: 2026-09-10
citacao: >
  Prossiga pelo bloco A, iniciando por D4. Mesmo esquema: ao final, reestruture
  a lista necessária para chegar ao valuation sem erros conhecidos e motor de
  referência ao final e rode as lentes.
afeta:
  - packages/equisim_core/lib/src/services/valuation/dcf.dart
  - packages/equisim_core/lib/src/services/valuation/levered_rates.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - packages/equisim_core/test/levered_rates_test.dart
  - packages/equisim_core/test/valuation_test.dart
  - docs/validacao/fluxo_explicito.md
substitui: []
---

## Contexto

O motor descontava o fluxo inteiro de cada exercício como se ele chegasse no
último dia do ano. Nenhuma empresa recebe assim: o caixa entra ao longo dos
doze meses, e o centro de massa dele é o meio do ano.

O erro é **sistemático, unidirecional e grande**: cobra meio ano de espera a
mais sobre a avaliação inteira, período explícito e perpetuidade. Com desconto
de 13%, vale 6,3%.

## Decisão

**A convenção de produção passa a ser a de meio de ano.** Cada fluxo é
levantado por `√(1 + r_t)`, à taxa do próprio ano; o valor terminal recebe o
mesmo levantamento à taxa de equilíbrio que o capitaliza.

**A convenção anterior continua existindo, nomeada** — `CashTiming.fimDeAno` —
porque é sob ela que `FCFF/WACC ≡ FCFE/Ke` é identidade algébrica exata, e é lá
que os testes da [decisão 41](041-custo-de-capital-realavancado-ano-a-ano.md)
provam a álgebra do ponto fixo.

**O ponto fixo acompanha a convenção.**
`LeveredCostOfCapital` reconstrói o valor ano a ano por acumulação regressiva
para conhecer `D/E`, e essa reconstrução estava na convenção de fim de ano.
Como a dívida **não** é levantada, `D/E` sairia inflado e o `Ke` com ele. A
invariante — o valor que alimenta a alavancagem é o mesmo que sai no preço —
passa a ser travada por teste nas duas convenções.

## Consequências aceitas

**O preço justo sobe 8,2% na mediana**, com p10 de 6,6% e p90 de 15,0%. A
dispersão é a das taxas de desconto: meio ano vale mais quando o dinheiro é
mais caro.

**Todo preço justo publicado muda.** De novo.

**O `terminalShare` não se move.** O levantamento é o mesmo fator nos dois
pedaços do valor quando a taxa é plana, e a composição do preço fica onde
estava — o que está travado por teste.

**É aproximação declarada, e a exata seria outra.** O ano 1 conta a partir do
último exercício publicado, e na data da avaliação parte dele já correu. Tratar
o período parcial exigiria data de fechamento por empresa — que a fonte dá — e
um fluxo proporcional dentro do ano — que ela não dá. A convenção de meio de
ano é a aproximação padrão para exatamente esse caso, e erra menos que supor
que tudo chega no dia 31 de dezembro.

**Não é ajuste ao mercado.** A direção é conhecida antes de medir e o tamanho
sai da taxa de desconto, não do vão a fechar: ele fecha cerca de um oitavo do
resíduo, e o resto continua onde estava.

**A alternativa descartada** era manter o fim de ano por ser conservador.
Recusada: conservadorismo por convenção errada não é margem de segurança, é
viés não declarado — e o projeto já tem margem de segurança como parâmetro
explícito.
