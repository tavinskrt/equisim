---
numero: 121
titulo: O cenário de desconto move o Ke um por um, e as três leituras possíveis estão medidas
status: aceita
origem: voce
data: 2026-09-21
citacao: >
  Seus itens de escopo para esta rodada são B20, B22, B23, B21 e C5.
afeta:
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - tool/cenario.dart
  - docs/validacao/cenario.md
substitui: []
---

## Contexto

O item B20 nasceu de um achado LOCAL da lente `metodo`, em 21/09/2026: o cenário
perturba `DcfAssumptions.discountRate`, e a rota derivada soma esse deslocamento
ao `Ke` **um a um** — mas `Ke` e `WACC` não se movem na mesma razão.

**O achado estava certo, e a resposta não era óbvia**, porque a razão depende do
que o cenário está perturbando, e ele não diz. O item pedia uma decisão que
escolhesse, com o efeito na faixa medido.

## O que foi medido

Sobre a entrada congelada, nos **77 avaliados pela via da firma** — na do
acionista as três leituras coincidem ([cenario.md](../validacao/cenario.md)).

| leitura | fator | com faixa | largura mediana | contra o um a um | base ≠ justo | preço justo muda |
|---|---|---:|---:|---:|---:|---:|
| **um a um** | `ΔWACC` | **77** | **24,9%** | 1,000× | 0 | 0 |
| estrutura fixa | `ΔWACC ÷ w_E` | **76** | 40,2% | **1,246×** | 0 | 0 |
| taxa livre | `ΔWACC ÷ (1 − w_D·t)` | 77 | 28,2% | 1,070× | 0 | 0 |

**O preço justo não muda em nenhuma**, e a pós-condição da decisão 105 — o
cenário base volta ao preço justo — vale nas três.

**E amplificar custa uma faixa**: sob `estrutura fixa` a **YDUQ3** perde os
cenários, porque o lado otimista baixa o `Ke` de equilíbrio até `Ke_∞ − g_∞`
cair abaixo do mínimo e o terminal do acionista divergir.

## Decisão

**O um a um fica. As outras duas entram no enum
`ScenarioTranslation` como imposição de diagnóstico.**

1. **É a leitura que o rótulo nomeia.** O cartão diz «Crescimento e desconto» e
   «Sensibilidade: três conjuntos fixos de premissas». A premissa nomeada é o
   **desconto**, e na rota derivada o que desconta é o `Ke`: mover o `Ke` por
   `Δ` é a leitura literal de «e se o desconto fosse `Δ` maior».
2. **É a única que faz as duas vias quererem dizer a mesma coisa.** Na via do
   acionista o campo perturbado **é** o `Ke`. Sob `estrutura fixa`, duas
   companhias idênticas teriam faixas 1,25× diferentes por causa de qual via a
   cascata escolheu — e os ativos trocam de via conforme o dado, não conforme o
   negócio.
3. **É a única que não apaga faixa.** A tradução feita para alargar é a que
   deixa um ativo sem cenários.
4. **A leitura de estrutura fixa não está errada — responde outra pergunta.**
   «Se o custo de capital da firma subisse 1 p.p. com a alavancagem parada,
   quanto o acionista sentiria?» tem resposta, e é 1,25 p.p. Ela fica no enum
   para quem quiser fazê-la, e não no caminho de produção.
5. **O fator usa a participação do ano zero** — do caminho resolvido quando há
   um, do WACC estático quando não há. Participação fora de `(0, 1]`, que é o
   caso do caixa líquido, devolve fator 1: ali «amplificar» viraria «reduzir».

**O motor não muda.** O que muda é que o um a um deixa de ser o que estava lá e
passa a ser o que foi escolhido, com as alternativas medidas ao lado.

## Consequências aceitas

**A faixa de cenários da via da firma é 1,25× mais estreita** do que a leitura de
estrutura fixa daria. Isso importaria se ela fosse a medida de incerteza do
projeto, e **não é**: a [decisão 92](092-a-incerteza-e-a-faixa-calibrada-e-os-cenarios-sao-sensibilidade.md)
separou as duas, e a incerteza é a faixa calibrada, que sai da volatilidade
realizada e não passa por aqui.

**A assimetria da faixa também depende da leitura** — 1,27 no um a um contra 1,58
na estrutura fixa. Amplificar não é só escalar: o lado otimista cresce mais,
porque o desconto entra no denominador.

**As duas leituras alternativas ficam sem teste de produção.** Elas existem para
medir, e o teste que as cobre é o da própria escolha: que o padrão é o um a um e
que as outras movem a faixa na direção e na ordem de grandeza medidas aqui.
