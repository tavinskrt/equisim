---
numero: 94
titulo: A faixa calibrada do aplicativo passa a sair da amostra com as deslistadas, que a cobre a até 5 p.p. da nominal dos dois jeitos
status: aceita
origem: voce
data: 2026-09-15
citacao: >
  autorizo o prosseguimento da implantação da Fase 2, com os itens C2b, C0b,
  C1a e C1b.
afeta:
  - tool/cobertura_banda.py
  - assets/validacao/banda_calibrada.json
  - docs/validacao/cobertura_banda.md
  - docs/validacao/cobertura_banda_deslistadas.json
substitui: []
---

## Contexto

O item C2b do plano. A [decisão 92](092-a-incerteza-e-a-faixa-calibrada-e-os-cenarios-sao-sensibilidade.md)
pôs na tela de avaliação a faixa calibrada — os quantis da razão entre o preço
mais proventos realizado e o preço justo, nas coortes — e declarou a ressalva que
impedia dar o R2 por atingido: **a amostra era a dos sobreviventes**, e a cauda de
baixo do realizado, que decide a borda inferior, é a que as quebras esconderiam.

O C1b ([decisão 93](093-as-deslistadas-entram-nas-coortes-e-o-t-e-o-menor.md))
pôs as deslistadas nas coortes, na mesma execução das listadas.

## Decisão

1. **A remedição é cruzada e fora da amostra**: calibrada nas listadas — a faixa
   que o aplicativo mostrava — ou em todas, e testada em cada grupo, cada coorte
   só com as coortes cujo horizonte já tinha terminado.

   | calibrada em → testada em | 12 meses (90 / 80 / 50%) | 36 meses (90 / 80 / 50%) |
   |---|---|---|
   | listadas → todas | 89,9 / 79,9 / 53,5 (733) | 92,2 / 79,4 / 52,9 (257) |
   | listadas → deslistadas | 87,8 / 76,8 / 47,6 (82) | 96,2 / 84,6 / 53,8 (26) |
   | **todas → todas** | **91,3 / 81,4 / 54,2** (733) | **93,0 / 82,1 / 49,0** (257) |

   **A faixa dos sobreviventes cobre a amostra com as deslistadas a até 5 p.p. da
   nominal nos dois horizontes**, e a recalibrada com elas também.

2. **O pacote do aplicativo passa a sair da amostra com as deslistadas.** As
   duas passam no critério, e é esta a amostra que o R2 pede. A faixa de 80% em
   12 meses vai de 0,62–9,21 vezes o preço justo para **0,64–10,67**; em 36 meses,
   de 0,51–9,75 para **0,55–10,86**.

3. **O que se temia não aconteceu, e fica dito.** A borda de baixo não desceu: o
   quinto percentil do realizado sobre o justo é de 0,43 com as deslistadas contra
   0,43 sem elas em 12 meses, e 0,36 contra 0,35 em 36. As deslistadas terminaram,
   na mediana, **acima** das listadas — 3,6 vezes o preço justo contra 2,1. É o
   que se esperaria de saídas por aquisição ou por oferta de fechamento de capital,
   a preço de oferta, mais do que por quebra; o motivo da saída de cada companhia
   **não foi levantado**, e a explicação fica como hipótese. A borda que se moveu
   foi a de cima.

## Consequências aceitas

**O teste nas deslistadas sozinhas é pequeno**: 82 observações em 12 meses e 26
em 36. A cobertura delas oscila mais — 87,8% para 90% em 12 meses — e não sustenta
conclusão própria.

**A calibração continua marginal.** No terço de maior potencial, a faixa de 90%
cobre 83,9% em 12 meses e 82,3% em 36 — abaixo do critério, que é agregado.

**O viés não sai inteiro.** As 126 companhias com ação em bolsa e sem ponte para
o preço seguem fora, e as janelas que atravessam evento suspeito também.

**Os números da tela mudam** para todo ativo, na borda de cima mais que na de
baixo. O teste do pacote continua reprovando a suíte se alguma cobertura sair de
5 p.p. da nominal.

Ver [cobertura_banda.md](../validacao/cobertura_banda.md) §7.
