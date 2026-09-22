# A tradução do cenário para o `Ke` — item B20

> **Medido em 21/09/2026**, sobre a entrada congelada do gabarito da cascata.
>
> ```bash
> dart run tool/gabarito_cascata.dart   # congela a entrada
> dart run tool/cenario.dart            # grava cenario.json
> ```
>
> Leitura de hoje conferida contra o gabarito ativo a ativo: **zero
> divergências**.

## 0. A pergunta

O cenário perturba `DcfAssumptions.discountRate`. **Na via do acionista esse
campo é o `Ke`**, e o deslocamento é um a um por construção. **Na via da firma
ele é o WACC**, e a rota derivada desconta ao `Ke` (decisão 102): traduzir exige
escolher o que o cenário está perturbando — e ele não diz.

São três leituras, e três fatores:

| leitura | fator | o que o cenário perturba |
|---|---|---|
| **um a um** | `ΔK_e = ΔWACC` | a taxa **aplicada ao fluxo** |
| estrutura fixa | `ΔK_e = ΔWACC ÷ w_E` | o **custo de capital da firma**, com `K_d` e os pesos parados |
| taxa livre | `ΔK_e = ΔWACC ÷ (1 − w_D·t)` | a **taxa livre de risco**, que move `K_e` e `K_d` juntos |

## 1. O que cada uma faz com a faixa

Nos **77 avaliados pela via da firma**. Na do acionista as três coincidem **por
construção**: `_descontarFluxo` devolve o fluxo do acionista antes de calcular o
fator, porque lá o campo perturbado já **é** o `Ke` — medi-las ali seria medir
nada.

| leitura | com faixa | largura p25 / mediana / p75 | contra o um a um | base ≠ justo | preço justo muda |
|---|---:|---|---:|---:|---:|
| **um a um** | **77** | 3,5% / **24,9%** / 30,0% | 1,000× | 0 | 0 |
| estrutura fixa | **76** | 26,4% / **40,2%** / 60,0% | **1,246×** | 0 | 0 |
| taxa livre | 77 | 8,9% / **28,2%** / 33,3% | 1,070× | 0 | 0 |

**Três fatos.**

**O preço justo não muda em nenhuma.** É o esperado — o cenário base tem
deslocamento zero, e multiplicar zero por qualquer fator dá zero —, mas precisa
estar medido, porque uma tradução que mexesse no centro estaria cercando outro
número.

**A pós-condição da decisão 105 continua valendo nas três**: o cenário base volta
ao preço justo em 100% dos casos, `base ≠ justo` em zero.

**E amplificar custa uma faixa.** Sob `estrutura fixa`, a **YDUQ3** perde os
cenários: o deslocamento do lado otimista baixa o `Ke` de equilíbrio o bastante
para que `Ke_∞ − g_∞` caia abaixo do mínimo, e o valor terminal do acionista
diverge. **Uma tradução feita para alargar a faixa é a única que apaga uma.**

## 2. Qual é a certa

**A que o rótulo da tela nomeia.** O cartão diz «Crescimento e desconto» e
«Sensibilidade: três conjuntos fixos de premissas». A premissa nomeada é o
**desconto**, e na rota derivada o que desconta é o `Ke`. Mover o `Ke` por `Δ` é
a leitura literal de «e se o desconto fosse `Δ` maior».

**E é a única que faz as duas vias quererem dizer a mesma coisa.** Na via do
acionista o campo perturbado já é o `Ke`, e o cenário move um a um. Sob
`estrutura fixa`, duas companhias idênticas teriam faixas 1,25× diferentes por
causa de **qual via a cascata escolheu** — e os ativos trocam de via conforme o
dado, não conforme o negócio.

**A leitura de estrutura fixa não está errada; ela responde outra pergunta.**
«Se o custo de capital da firma subisse 1 p.p. com a alavancagem parada, quanto
o acionista sentiria?» é pergunta legítima, e a resposta é 1,25 p.p. Mas não é a
pergunta que o cartão faz.

## 3. O que se decidiu, e o que custa

[Decisão 121](../decisoes/121-o-cenario-move-o-ke-um-por-um-e-as-tres-leituras-estao-medidas.md):
**o um a um fica, e as outras duas ficam no enum como imposição de
diagnóstico.**

**O custo declarado:** a faixa de cenários da via da firma é **1,25× mais
estreita** do que a leitura de estrutura fixa daria. Isso importaria se a faixa
fosse a medida de incerteza do projeto — e ela não é. A
[decisão 92](../decisoes/092-a-incerteza-e-a-faixa-calibrada-e-os-cenarios-sao-sensibilidade.md)
separou as duas: **a incerteza é a faixa calibrada**, que sai da volatilidade
realizada e não passa por aqui; os cenários são sensibilidade a uma premissa
nomeada.

## 4. O que isto não diz

- **Não mede qual faixa cobre melhor o preço futuro.** Cobertura é a faixa
  calibrada, e ela é medida em coorte (C2b, C2c).
- **A assimetria muda junto.** A razão entre o lado otimista e o pessimista vai
  de 1,27 no um a um a 1,58 na estrutura fixa: amplificar não é só escalar, e o
  lado de cima cresce mais porque o desconto entra no denominador.
- **O fator usa a participação do ano zero.** Com o caminho resolvido ela sai do
  capital próprio que o modelo produz; sem ele, do WACC estático. Participação
  fora de `(0, 1]` — caixa líquido — devolve fator 1, porque ali o «amplificar»
  viraria «reduzir», que nenhuma das três leituras quer dizer.
