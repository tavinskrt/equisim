---
numero: 49
titulo: A ponte desconta os não controladores, e a equivalência patrimonial deixa de ser tributada duas vezes
status: aceita
origem: voce
data: 2026-09-10
citacao: >
  Prossiga com o bloco A, por D7. Mesmo esquema: ao final, reestruture a lista
  necessária para chegar no valuation sem erros conhecidos e motor de
  referência. Ao final, rode as lentes.
afeta:
  - packages/equisim_core/lib/src/entities/fundamentals.dart
  - packages/equisim_core/lib/src/services/valuation/dcf.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - lib/data/dtos/brapi_dtos.dart
  - lib/data/datasources/local/cache_database.dart
  - lib/data/datasources/remote/brapi_datasource.dart
  - lib/data/repositories/market_repositories.dart
  - docs/validacao/ponte.md
substitui: []
---

## Contexto

O D7 pergunta se a ponte `E = EV − dívida líquida` está completa. O manual
manda ajustar quatro termos: não controladores, coligada, arrendamento e
debênture.

**A conferência contra a fonte reprovou três dos quatro.** O cache guarda 30
dos 211 campos que a fonte devolve por exercício, de modo que a pergunta só se
respondia indo à API — e a resposta foi que a conta-mãe `loansAndFinancing`
**já contém** arrendamento e debênture. Somá-los estouraria o passivo não
circulante em PETR4, VALE3 e RENT3. Ver
[ponte.md](../validacao/ponte.md).

O de coligada reprovou por outra razão: na DRE brasileira a equivalência
patrimonial entra **acima** do EBIT. Na ITSA4 ela é R$ 17,5 bi de um EBIT de
R$ 18,1 bi — 97%. Somar o valor das participações contaria o mesmo duas vezes,
o fluxo e o estoque.

## Decisão

**A participação dos não controladores sai do valor do capital próprio**, nas
duas rotas — a ponte `EV − D` e a rota derivada da
[decisão 43](043-capital-proprio-pela-rota-derivada.md) —, depois do desconto e
antes da divisão por papel.

**A alavancagem não muda.** Minoritário é capital próprio: tirá-lo de
`equityShare` o trataria como dívida, e a pós-condição da ponte e o ponto fixo
da [decisão 41](041-custo-de-capital-realavancado-ano-a-ano.md) leriam uma
estrutura de capital que não existe.

**A equivalência patrimonial deixa de ser tributada duas vezes:**

```
NOPAT = (EBIT − equivalência) × (1 − τ) + equivalência
```

Ela chega líquida do imposto pago pela investida, e a
[decisão 37](037-aliquota-estrutural-no-fluxo-da-firma.md) aplicava a alíquota
da controladora sobre o EBIT inteiro.

**Nada é somado ao valor da firma por conta de coligada, e nada é somado à
dívida por conta de arrendamento ou debênture.** As três correções de manual
ficam explicitamente recusadas, com a medição que as recusa.

**Dois campos novos entram no cache** — `minorityInterest` e
`equityIncomeResult` —, e a migração para a versão 4 **invalida a chave de
fundamentos**: as colunas são nuláveis, mas a validade de 30 dias faria a
leitura responder com elas vazias até vencer.

## Consequências aceitas

**Os dois confinamentos da equivalência são assimétricos, de propósito.**
Equivalência negativa não devolve imposto — prejuízo de investida reduz o EBIT
sem ter gerado crédito tributário na controladora — e a parcela isenta não
passa do próprio EBIT, porque acima disso o NOPAT ficaria maior que o resultado
que o gerou. As duas assimetrias vão na direção conservadora.

**Participação negativa de não controladores é tratada como zero.** Controlada
com patrimônio negativo produz o caso, e subtraí-lo *aumentaria* o valor do
controlador. Enquanto o motor não modelar a obrigação de aportar, zero é a
leitura defensável.

**A participação é subtraída pelo valor contábil.** O correto seria o valor de
mercado da parcela dos minoritários, que não existe para controlada fechada. O
contábil é o disponível, e subestima quando a controlada vale mais que o livro.

**Propriedade para investimento fica fora.** `longTermInvestments` é
`shareholdings + investmentProperties`, e a segunda gera receita que pode ou
não estar no EBIT conforme o setor. Sem como distinguir, não se mexe.

**A recusa das três correções de manual é a parte mais importante desta
decisão.** Aplicar o arrendamento da PETR4 teria somado 61% do valor de mercado
dela à dívida líquida, e nada no motor acusaria — a conta continuaria fechando,
com o número errado.

**O rastro de auditoria passou a declarar a convenção de caixa.** A lente
`metodo` apontou que a fórmula publicada omitia o levantamento de meio de ano
da [decisão 48](048-caixa-no-meio-do-ano.md) e descrevia um desconto 6% maior
que o aplicado. A auditoria existe exatamente para impedir esse tipo de
divergência, e agora ela está travada por teste nas duas convenções.

**A alternativa descartada** era confiar na taxonomia documentada da fonte em
vez de testá-la contra a aritmética do balanço. Recusada porque a fonte não
documenta a hierarquia das contas, e o teste — a soma das filhas não pode
passar do passivo que as contém — custa três consultas.
