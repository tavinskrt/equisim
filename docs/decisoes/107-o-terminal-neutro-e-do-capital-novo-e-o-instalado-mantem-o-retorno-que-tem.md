---
numero: 107
titulo: O retorno terminal neutro é do capital novo; o instalado mantém o retorno que a projeção alcança, e isso passa a ser declarado
status: aceita
origem: voce
data: 2026-09-21
citacao: >
  Seus itens de escopo para esta rodada são B12, B14 e B15.
afeta:
  - packages/equisim_core/lib/src/services/valuation/dcf.dart
  - packages/equisim_core/lib/src/entities/valuation.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - tool/gabarito_cascata.dart
  - docs/validacao/terminal_excedente.md
substitui: []
---

## Contexto

A lente `metodo` apontou em 14/09/2026, e a álgebra confirma, que o terminal
neutro carrega uma premissa que o rótulo não diz:

```
VT = lucro_{N+1}/r = capital_N + EVA_{N+1}/r
com  EVA_{N+1} = lucro_{N+1} − r·capital_N
```

O retorno terminal neutro recusa valor ao capital **novo** — `RONIC_∞ = r`, e é
isso que faz o crescimento sair da fórmula. Ele não diz nada sobre o capital que
**já existe** no ano N, que segue rendendo o que a projeção alcançar, para
sempre. Nas concessões a [decisão 88](088-o-prazo-da-concessao-corta-o-excedente.md)
já corta esse excedente no fim do contrato, pela mesma álgebra; fora delas, ele
é perpétuo.

O item B12 pedia três coisas: declarar, medir o peso no universo, e decidir se
ele fica, decai ou acaba num horizonte.

## O que foi medido

Sobre a entrada congelada do gabarito, em 21/09/2026, nos 83 avaliados em que a
decomposição se aplica ([terminal_excedente.md](../validacao/terminal_excedente.md)):

**A premissa é o contrário do que o item supunha.** O capital instalado rende,
na perpetuidade, **0,71 vez** o custo de capital de equilíbrio na mediana —
12,9% contra 18,9% — e fica **abaixo** dele em **71 dos 83**. O terminal não
mantém um excedente para sempre: ele mantém um **déficit**.

| peso no preço justo | p10 | p25 | mediana | p75 | p90 |
|---|---:|---:|---:|---:|---:|
| `EVA_{N+1}/r` | −61,8% | −30,7% | **−14,1%** | −2,6% | +2,3% |

Passa de 10% em módulo em 50 dos 83, e de 20% em 33.

**Decair num horizonte não é uma opção distinta de manter.** A 18,9% ao ano, o
excedente é quase todo valor presente dos primeiros anos:

| horizonte do excedente | efeito no preço justo (mediana) |
|---|---:|
| 0 anos — o terminal vale `capital_N` | **+14,1%** |
| 10 anos | +2,5% |
| 20 anos | +0,4% |
| perpétuo — o que o motor faz | 0 |

Vinte anos devolvem 0,4% do preço. **A escolha é binária**: ou o instalado
mantém o retorno que tem, ou ele converge ao custo de capital de imediato.

## Decisão

1. **O número fica.** O terminal continua capitalizando o lucro que a projeção
   alcança, e não o capital implícito nela.
2. **O rótulo muda.** O retorno neutro passa a ser declarado como `RONIC_∞ = r`
   — o capital **novo** sem valor —, e não como "não há lucro econômico em
   perpetuidade", que é afirmação sobre o retorno médio e é falsa em 71 dos 83.
3. **O peso é declarado.** Ele sai nos diagnósticos
   (`ValuationDiagnostics.terminalExcessShare` e `impliedTerminalReturn`),
   aparece **sempre** no rastro de auditoria, e vira ressalva na avaliação
   quando passa de 20% do valor do capital próprio em módulo.

**Por que fica.** Trocar o terminal por `capital_N` é afirmar que a
rentabilidade reverte à média — que a companhia que rende 12,9% sobre o capital
passará a render 18,9%. **O motor não mediu isso**, e a
[decisão 35](035-dcf-reverso-e-regressao-condicional.md) é explícita: quem
propuser trocar o terminal depois dela precisa de um argumento que não seja o
viés de nível. O argumento que o B12 tem é sobre **declaração**, não sobre a
conta, e é isso que esta decisão executa.

**E o DCF desconta fluxo.** O capital investido da projeção é um construto do
freio de reinvestimento; substituir o terminal por ele faria o preço depender de
uma grandeza que a cascata usa para outra coisa. Manter o lucro que a projeção
alcança é a leitura conservadora **e** a que fecha com o resto do modelo.

## Consequências aceitas

**Um terço dos avaliados ganha uma ressalva nova.** Em 33 dos 83, a parcela
passa de 20% do preço justo, e a avaliação passa a dizer que a perpetuidade supõe
o capital instalado rendendo abaixo — ou acima — do custo dele. É informação
dura de ler e é a premissa dominante desses casos.

**O preço justo do motor fica 14% abaixo, na mediana, do que ficaria com o
terminal em `capital_N`.** É consequência escolhida, e a validação já mede que o
realizado fica **acima** do preço justo: a escolha conservadora anda no sentido
do erro conhecido, e não contra ele. Quem quiser mudá-la precisa medir a
reversão da rentabilidade à média — item B19.

**A decomposição vale só onde a álgebra é essa.** Com vantagem competitiva
concedida o terminal é outro, com contrato o corte já está feito, e sem capital
medível não há o que separar: nesses casos os dois campos saem nulos, e o rastro
não afirma nada.
