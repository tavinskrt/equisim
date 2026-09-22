---
numero: 120
titulo: O minoritário fica fora do peso do WACC, e a condição de exposição passa a ser declarada
status: aceita
origem: lente
data: 2026-09-21
citacao: >
  A ponderação do WACC [...] usando apenas o capital próprio da controladora e a
  dívida, omitindo completamente a participação dos acionistas minoritários [...]
  Ao omitir a fatia dos minoritários do divisor (E + D), o código infla
  matematicamente a participação percentual da dívida.
afeta:
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - tool/minoritario.dart
  - docs/validacao/minoritario.md
substitui: []
---

## Contexto

O item B23 nasceu de um achado LOCAL da lente `metodo`: o fluxo que o WACC
desconta é o **consolidado**, e o peso do capital próprio é `divisor × preço` —
o valor de mercado da **controladora**. A fatia dos não controladores fica fora
do denominador `E + D`.

**A fórmula está mesmo assim.** O que faltava era saber onde isso morde.

## O que foi medido

Sobre a entrada congelada, com a montagem de hoje conferida ativo a ativo
([minoritario.md](../validacao/minoritario.md)).

**O escopo é menor do que a acusação sugere, e a razão é estrutural.** O caminho
**resolvido** pondera por `E_t = V_t − D_t`, com `V` vindo de um fluxo
consolidado: esse `E` **já inclui** o minoritário. E a via do acionista não tem
WACC nenhum. Só o WACC **estático** — o recuo — usa o valor de mercado da
controladora.

A exposição exige então três condições ao mesmo tempo:

| | |
|---|---:|
| pela via da firma (têm WACC) | 77 de 97 |
| recuam ao WACC estático | 19 |
| **via da firma E estático** | **0** |
| com minoritário ≥ 1% do consolidado | 33 |
| **firma, estático E material** | **0** |

**A interseção é vazia.** E o minoritário não é pequeno — 31,6% do consolidado
no extremo: o defeito não morde por causa do **caminho**, não do tamanho.

**Impor o minoritário no peso não move nada**: 0,00% de preço justo nos 97, pelas
duas formas, com postos de 1,0000.

## Decisão

**O ajuste é recusado, e a condição de exposição passa a ser declarada.**

1. **Recusado porque o dado não existe.** O valor de **mercado** do minoritário
   não é observável. As duas formas de contorná-lo são ruins de maneiras
   diferentes: somar o valor **contábil** põe duas unidades no mesmo
   denominador; usar `PL_min × (E_mercado ÷ PL_contr)` supõe que o minoritário
   negocia ao mesmo `P/VP` do controlador, que é premissa sem evidência. **Trocar
   uma distorção conhecida por uma suposição não medida não é melhoria.**
2. **Recusado porque não muda nada.** 0,00% ao centavo nos 97 avaliados, pelas
   duas formas. Não é margem estreita: é exatamente zero, porque o peso estático
   não chega ao resultado quando as taxas resolvem — nem pela partida do ponto
   fixo, que é independente do chute desde a
   [decisão 110](110-o-ponto-fixo-e-tentado-de-duas-partidas-e-a-recusa-deixa-de-ser-do-chute.md).
3. **Declarado porque vazio hoje não é vazio sempre.** Um ativo da via da firma
   pode recuar ao estático — sem beta desalavancado, ou com o ponto fixo não
   convergindo. Quando as três condições se encontrarem, a avaliação **diz**,
   com a fatia medida, em vez de entregar um desconto achatado em silêncio.
   `ValuationCascade.minorityWeightMateriality` é o corte, em 1% do consolidado.
4. **A ponte não muda.** O minoritário continua saindo do valor do acionista ao
   final (decisão 49); o que esta decisão examina é só o **peso da taxa**.

**O preço justo não muda em ativo nenhum**, e o gabarito confere: nas montagens
de diagnóstico que desligam o caminho resolvido — `curva`, `doisPontos` e
`impostos` — o aviso aparece em **64 montagens** e **nenhum preço se move**.

## Consequências aceitas

**A assimetria entre o estático e o resolvido fica.** Os dois não calculam a
mesma taxa para a mesma companhia quando há minoritário, e é o resolvido que está
certo. Como o recuo só age onde o resolvido falhou, a avaliação afetada já
carrega a ressalva de que a alavancagem foi suposta constante — e agora carrega
também esta.

**O corte de 1% é declarado, e não medido.** Não há distribuição que o
justifique: ele separa o minoritário que move a taxa do que move o terceiro
decimal.

**Se um dia a interseção deixar de ser vazia, o item volta.** O aviso é a
condição de reabertura, e não a solução — resolver de verdade depende de o
mercado precificar a participação, o que hoje não acontece.
