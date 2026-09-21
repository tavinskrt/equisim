---
numero: 119
titulo: A rota derivada também remunera o caixa pela taxa livre de risco — o defeito da decisão 113 tinha um segundo lugar, e era o caminho de produção
status: aceita
origem: lente
data: 2026-09-21
citacao: >
  Na via da firma [...] a função `DcfCalculator.equityFromFirm` recebe o custo
  da dívida `kd` (que carrega o spread de risco de crédito da companhia) e o
  aplica de forma cega à dívida líquida, sem separar as contas de caixa e
  aplicações financeiras da dívida bruta. [...] esse modelo faz com que os
  excessos de liquidez rendam uma taxa agressiva de empréstimo (Rf + spread).
afeta:
  - packages/equisim_core/lib/src/services/valuation/dcf.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - docs/validacao/gabarito_cascata.json
substitui: []
---

## Contexto

A [decisão 113](113-o-caixa-rende-a-taxa-livre-de-risco-e-nao-o-custo-de-emprestimo.md),
de horas antes, separou o caixa da dívida bruta **no WACC**: a perna negativa da
dívida líquida deixou de ser remunerada ao custo de empréstimo.

**O mesmo defeito estava num segundo lugar, e nele era pior.** A ponte do
acionista da rota derivada — `DcfCalculator.equityFromFirm`, que é o **caminho
de produção da via da firma desde a [decisão 102](102-nenhuma-avaliacao-muda-de-via-e-a-firma-avalia-pelo-fluxo-do-acionista-derivado.md)**
— calcula o serviço da dívida como

```
serviço_t = D_líquida,t · (K_d(1 − τ) − g_t)
```

Com caixa líquido, `D_líquida` é negativa e o termo vira **receita financeira ao
custo de empréstimo**. Com dívida e caixa juntos, o caixa é creditado com prêmio
de crédito que ele não rende. O fluxo do acionista saía inflado em **toda
companhia com caixa no balanço**, que é praticamente todas.

A lente `metodo` apontou o segundo lugar na rodada seguinte à do primeiro.

## Decisão

**O serviço da dívida se abre em duas pernas, com a mesma álgebra da decisão
113.**

```
serviço_t = D_bruta,t · K_d(1 − τ)  −  C_t · R_f(1 − τ)  −  D_líquida,t · g_t
```

1. **A dívida projetada não muda.** As duas metades crescem com o mesmo fator, e
   a diferença delas é a série líquida de antes: o que a separação muda é a
   **taxa** de cada metade, e não a ponte.
2. **Com caixa zero, colapsa na forma anterior** — `D_líquida·(K_d(1−τ) − g)` —,
   que é a que quem monta a projeção à mão obtém. Sem `cashYield`, idem.
3. **A taxa do caixa é uma só para todo o caminho**, como o `K_d` logo ao lado:
   a rota derivada não recebe caminho de custo da dívida, e dar caminho ao
   rendimento sem dar ao juro misturaria convenções.
4. **É identidade, e não escolha.** `FCFE = FCFF − (D·K_d − C·R_f)(1−τ) +
   ΔD_líquida`. A forma anterior supunha `R_f = K_d`, que é falso por
   construção — o `K_d` do motor é `R_f + spread` desde a decisão 31.

## O que foi medido

Sobre a entrada congelada do gabarito, contra a montagem da decisão 113:

| | |
|---|---:|
| preço justo muda | **73 de 97** |
| **todos caem** | 73 de 73 |
| mediana | **−4,63%** |
| p10 / p90 | −42,8% / −0,95% |
| extremo | −85,6% |
| deixam de ser avaliáveis | **2** (ENGI11, GOAU4) |

**A via do acionista não muda em ativo nenhum** — ela não tem ponte de dívida.

**O sinal é monótono por construção**: render `R_f` em vez de `R_f + spread`
reduz o fluxo do acionista em `C·spread·(1−τ)` em cada ano, e nenhum ativo pode
subir.

## Consequências aceitas

**Duas avaliações a menos**: ENGI11 e GOAU4. Com o fluxo do acionista menor, o
capital próprio não sobrevive à projeção, e o ponto fixo recusa das duas partidas
(decisão 110). **É perda de cobertura, e está contada**: 99 avaliados passam a
97 na montagem do aplicativo.

**Toda a medição desta rodada foi refeita.** Horizonte, prêmio de mercado,
tamanho, múltiplos, excedente terminal e reversão do `ROIC` haviam sido medidos
sobre o motor com o defeito, e foram remedidos depois dele. As decisões 114 a 118
carregam os números **de depois**.

**O motor fica mais conservador, e o desacordo com o mercado aumenta.** O
potencial mediano cai, e a divergência contra os múltiplos de pares
([decisão 118](118-a-triangulacao-por-multiplos-e-segunda-leitura-declarada-e-nao-entra-no-preco.md))
cresce. **Isso não é argumento contra a correção**: a identidade do fluxo do
acionista não é negociável, e um motor que inflava o fluxo de quem tem caixa
estava certo pelo motivo errado quando concordava com o preço.

**Duas correções da mesma família em duas rodadas.** A decisão 113 e esta saíram
da mesma lente, com o mesmo argumento, em lugares diferentes do mesmo caminho.
Vale como aviso sobre o método: **corrigir uma ocorrência não corrige a regra**,
e a próxima varredura deve procurar `K_d` aplicado a grandeza líquida em todo o
núcleo.
