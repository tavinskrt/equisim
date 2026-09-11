---
numero: 41
titulo: O custo de capital passa a ser resolvido ano a ano contra a alavancagem, e as duas rotas do capital próprio voltam a coincidir
status: aceita
origem: voce
data: 2026-09-10
citacao: >
  Vamos de b pela fidelidade. Comece por D1 e vá até onde conseguir. Não ligo
  sobre sobrepor decisões ou reescrever código legado.
afeta:
  - packages/equisim_core/lib/src/services/valuation/dcf.dart
  - packages/equisim_core/lib/src/services/valuation/levered_rates.dart
  - packages/equisim_core/test/equity_from_firm_test.dart
  - packages/equisim_core/test/levered_rates_test.dart
  - docs/validacao/identidade_das_vias.md
substitui: []
---

## Contexto

A [decisão 39](039-as-duas-vias-sao-modelos-independentes.md) estabeleceu que
as duas vias são modelos independentes e que conciliá-las exige derivar uma da
outra. A ponte foi construída — `FCFE = FCFF − juros(1−τ) + ΔDívida` — e **não
fechou**: divergência de 4,2% entre as rotas quando há crescimento.

A causa foi isolada em [`identidade_das_vias.md`](../validacao/identidade_das_vias.md):
a dívida é projetada sobre a base de capital e cresce a `g`; o valor da firma
cresce a outra taxa. Medido, `D/V` sai de **0,2868 no ano zero para 0,3789 no
ano dez**, e o `WACC` montado com os pesos do ano zero deixa de descrever os
anos seguintes. No ano N:

```
Ke·E + Kd(1−τ)·D = 1.617,62
WACC·V           = 1.710,32     ← diferença de 92,70, exatamente o vão
```

**O motor já supunha alavancagem constante e não a produzia.** Usar um `WACC`
único ao longo da projeção **é** supor `D/V` constante, e a projeção da dívida
contradizia essa suposição. A contradição estava invisível porque nada
verificava as duas rotas uma contra a outra.

## Decisão

**Adotada a rota da fidelidade**: aceitar que a alavancagem muda e reprecificar
o custo do capital próprio a cada ano, em vez de forçar a dívida a seguir o
valor.

`LeveredCostOfCapital.solve` resolve por **ponto fixo** o que é circular por
natureza:

```
β_L,t  = β_U · (1 + (1 − τ)·D_{t−1}/E_{t−1})
Ke_t   = Rf_t + β_L,t · prêmio
WACC_t = Ke_t·(E/V)_{t−1} + Kd·(1 − τ)·(D/V)_{t−1}
```

Cada iteração reavalia a firma com o caminho da anterior, reconstrói o valor
ano a ano por acumulação regressiva e recalcula a alavancagem de cada ano. Para
até 100 iterações, com parada em 1e-10 de variação do valor no ano zero.

**A taxa deixa de ser interpolação de dois pontos e vira caminho.**
`DcfAssumptions.discountRatePath` e o `equityDiscountRatePath` de
`equityFromFirm` recebem uma taxa por ano projetado, e recusam caminho de
tamanho diferente do horizonte.

**O amortecimento de meio a meio é parte do método, não detalhe.** Sem ele o
ponto fixo oscila em ativo muito alavancado: uma queda de `E` eleva `Ke`, que
derruba `E` de novo.

### O critério de aceite

| | divergência entre as rotas |
|---|---:|
| interpolação de dois pontos, com crescimento | **4,2%** |
| caminho resolvido por ponto fixo | **< 1e-6** |

**A identidade fecha.**

## Consequências aceitas

**Isto amarra a decisão 40 a esta, e agora por uma recusa explícita.** Sem
`β_U` não há como realavancar, e `solve` devolve falha nomeada em vez de um
número. A [decisão 39](039-as-duas-vias-sao-modelos-independentes.md) afirmava
que o beta desalavancado era pré-requisito sem conseguir dizer por quê; esta é
a razão.

**Nada disso está ligado à produção.** `LeveredCostOfCapital` e
`DcfCalculator.equityFromFirm` são código exercitado por teste e não alcançado
por caminho de avaliação nenhum. Faltam três coisas, e cada uma é trabalho:
a cascata chamar o solucionador em vez de `CostOfCapital` com peso de mercado;
`PrepareValuationInputs` propagar o `β_U` que `ShrunkBeta` já produz; e a
decisão sobre o que fazer com a via do acionista sobre LPA, que permanece.

**A circularidade do WACC no ano zero continua em produção.** O ponto fixo a
resolve **dentro** da projeção; no ano zero o peso do equity segue vindo do
valor de mercado, e o modelo diz que o equity vale bem menos. Ligar o
solucionador é o que resolve os dois de uma vez.

**Instituição financeira fica fora por direito.** Não há valor da firma nem
dívida líquida com sentido econômico ali, e a via do acionista permanece como
modelo independente — declarado como tal.

**O ponto fixo pode não convergir**, e o resultado diz quando não converge em
vez de entregar o último palpite como se fosse solução.

**Duas guardas nasceram de achado da auditoria**, e a segunda é rede de
segurança para caso que lucro-base positivo não alcança: capital próprio que
desaparece dentro da projeção vira recusa nomeada, e valor da firma não
positivo também.

**A alternativa descartada** era amarrar a dívida ao valor — `D_t = D_0·(V_t/V_0)`
—, que daria alavancagem constante por construção e fecharia a identidade sem
ponto fixo por ano. Recusada por escolha declarada de fidelidade: ela imporia
ao ativo uma política de endividamento que o dado não mostra, enquanto a rota
adotada preserva a projeção de dívida que a base de capital implica.
