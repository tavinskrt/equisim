---
numero: 100
titulo: A faixa calibrada sai do preço, da volatilidade do papel e do preço justo com o peso medido
status: aceita
origem: voce
data: 2026-09-15
citacao: >
  Seus itens de escopo para esta rodada são C2b e B1.0, dando início à Fase 3.
afeta:
  - tool/cobertura_banda.py
  - tool/backtest_valuation.dart
  - packages/equisim_core/lib/src/services/valuation/calibrated_band.dart
  - packages/equisim_core/lib/src/entities/valuation.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - lib/presentation/valuation/valuation_page.dart
  - assets/validacao/banda_calibrada.json
  - docs/validacao/cobertura_banda.md
substitui: []
---

## Contexto

A [decisão 92](092-a-incerteza-e-a-faixa-calibrada-e-os-cenarios-sao-sensibilidade.md)
fez a incerteza que o aplicativo declara ser a **faixa calibrada**: os quantis da
razão entre o realizado e o preço justo nas coortes. A
[decisão 97](097-a-coorte-forma-preco-contagem-e-valor-de-mercado-na-base-da-data.md)
corrigiu a base de preço das coortes, e a faixa deixou de cobrir: 84,8/74,9% em 12
meses e 83,6/73,0% em 36, fora dos 5 p.p. do R2. Seis formas de recalibrar foram
medidas na terceira rodada e nenhuma fechou; o aplicativo passou a declarar a
cobertura medida.

Nesta rodada o diagnóstico foi refeito antes de tentar de novo, e está na §9 de
[cobertura_banda.md](../validacao/cobertura_banda.md): **as deslistadas não são a
causa** — a faixa cobre 90,4% delas em 12 meses e 96,3% em 36 —; **o choque comum
às coortes é pequeno** — o desvio da mediana entre coortes é de 0,18 contra 0,98
dentro delas —; **o que muda é a cauda de baixo**, que se alarga de 2018 para
2021 e 2022; e **o centro da forma antiga está errado**, porque ela impõe
convergência total ao preço justo onde o medido é `b = 0,02` a `0,08`.

**A forma e a regra foram fixadas por escrito antes de medir** (§9, escrita e
posta em staging antes de a ferramenta rodar): a convergência parcial na escala
da volatilidade do papel — simulação histórica filtrada —, medida como a §8 mede,
com as formas de controle sobre as mesmas observações, e o critério do R2 como
régua. É a sétima forma tentada desde a decisão 92, e foi a única desta rodada.

## Decisão

**A faixa que o aplicativo declara passa a ser, por horizonte e frequência:**

    [P₀·exp(a + b·ln(V/P₀) + σ·z_inferior),  P₀·exp(a + b·ln(V/P₀) + σ·z_superior)]

com `P₀` o preço de hoje, `V` o preço justo, `σ` a volatilidade anualizada do
papel nos 252 pregões até a data — da **mesma série** que a avaliação usou —, e
`a`, `b` e os `z` calibrados nas coortes. Sem volatilidade, sem preço ou sem
preço justo positivo, **não há faixa**, e o cartão some.

O pacote `assets/validacao/banda_calibrada.json` passa à versão 2, e o núcleo lê
as duas versões: `VolatilityBandTable` é a forma nova e `FairValueBandTable`
continua sendo a da decisão 92.

## Consequências aceitas

**A faixa cobre, e o R2 se atinge pelo que ele pede.** Fora da amostra,
87,9/79,0/50,3% em 12 meses e 88,2/80,4/51,2% em 36 — 2,1 e 1,8 p.p. da nominal,
contra 5,4 e 7,2 da forma em torno do justo nas mesmas observações.

**A faixa não é mais "em torno do preço justo", e o cartão diz isso.** Com
`b = 0,028` em 12 meses e `0,083` em 36, dobrar o preço justo move a faixa 2% e
6%. A incerteza que o motor declara é, sobretudo, o preço de hoje mais a
volatilidade do papel — o que é uma afirmação honesta sobre o que a validação
mediu, e uma afirmação pequena sobre o preço justo. **Quem quiser o erro do preço
justo contra o realizado continua tendo**: é a faixa da decisão 92, de 0,76 a
8,16 vezes o justo em 12 meses, registrada na §8.

**Ela calibra na média das coortes, e não em cada uma.** A cobertura de 90% por
coorte de teste vai de 59,8% a 100% em 12 meses e de 70,2% a 96,6% em 36 —
dispersão maior que a da forma antiga. As piores são as primeiras, calibradas com
poucas coortes.

**O 36 meses continua com pouca evidência.** Cada coorte de teste é calibrada com
o equivalente a 1,4 janela independente, pela estrutura da
[decisão 96](096-o-t-da-habilidade-e-corrigido-pela-sobreposicao-contra-o-critico-dela.md).
O resultado é o que a amostra permite medir, e não uma demonstração de que a
forma cobre em qualquer regime.

**A sétima tentativa é a sétima.** Uma forma escolhida depois de ver seis
falharem carrega busca de especificação, mesmo pré-registrada. O que separa esta
de um ajuste ao teste é que ela foi escrita antes, que a regra do pacote está no
código da ferramenta (`regra_do_pacote`), e que **a Fase 4 a remede sobre o motor
que a Fase 3 deixar, sem escolher outra** — é o C2c, e é lá que ela se confirma
ou cai.

**A volatilidade entra no resultado da avaliação.** `ValuationResult.priceVolatility`
sai da mesma série que alimentou o beta e a Porta 0; recalculá-la na tela, de
outra janela, daria outra faixa. Papel com menos de 120 retornos na janela fica
sem faixa — 34 observações em 12 meses e 30 em 36, de 3.551 e 2.611.

**A alternativa descartada** era manter a faixa em torno do justo e declarar que
o R2 não se atinge com a amostra que há. Ela continua registrada na §8 e no
pacote da versão 1; o que a derruba é que a forma nova cobre sobre exatamente as
mesmas observações, e que o motivo pelo qual a antiga não cobria — impor
convergência que não existe — é um defeito de forma, e não falta de amostra.
