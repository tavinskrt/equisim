---
numero: 147
titulo: O usuário refaz a conta do motor com os números dele, e o preço do motor continua o validado
status: aceita
origem: voce
data: 2026-10-11
citacao: >
  A ideia de poder deixar manual é justamente permitir que o usuário discorde
  do motor e possibilitar que ele faça os seus próprios cálculos usando o
  motor. De qualquer maneira, precisamos deixar os campos alteráveis.
afeta:
  - packages/equisim_core/lib/src/services/valuation/manual_valuation.dart
  - packages/equisim_core/lib/src/services/valuation/dcf.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/entities/valuation.dart
  - lib/presentation/valuation/manual_valuation_page.dart
  - lib/presentation/valuation/manual_copy.dart
  - lib/presentation/valuation/valuation_page.dart
  - lib/presentation/shared/domain_copy.dart
  - tool/conferir_calculo_manual.dart
substitui: []
---

## Contexto

O motor tirou do aplicativo toda a parte manual que as calculadoras de
valuation têm — digitar taxa de desconto, lucro, crescimento e perpetuidade.
Em 11/10/2026 o usuário pediu esses campos de volta, com o valor presente
recalculado enquanto se digita, num botão "Editar valuation".

O primeiro protótipo travava os campos em nome do método: a taxa era montada
pela curva, pelo beta e pelo prêmio, e não digitada; o crescimento perpétuo
tinha o teto da economia; o crescimento andava preso ao retorno. O usuário
recusou: **a tela existe para quem discorda do motor**, e um campo que só
aceita o que o motor aceitaria não deixa discordar. O segundo protótipo soltou
os campos e foi aprovado, com o pedido de mais destaque para cada campo e da
linha visual das outras telas.

## Decisão

**A avaliação do motor leva a própria conta congelada, e o usuário a refaz com
os números dele. O preço justo do motor não muda, e é ele que a validação
mede.**

1. **A conta é a do motor, e não uma cópia dela.** Ao concluir a via, a cascata
   guarda em `ValuationResult.manual` (`ManualValuation`) o fluxo-base, as
   premissas finais, a taxa que descontou cada ano e a rota da dívida
   (`FirmDiscountRoute`). O cálculo do usuário desconta de novo **pela mesma
   calculadora** (`DcfCalculator`), trocando só o que ele digitou. Sem
   nenhuma troca, o resultado é o preço justo do motor, bit a bit — travado
   por teste nas sete rotas da cascata e conferido nos 110 ativos avaliados
   da entrada congelada por `tool/conferir_calculo_manual.dart`.
2. **Os campos são livres.** Lucro de partida, em reais; crescimento dos
   primeiros anos, que cai até a perpetuidade ou fica constante; taxa de
   desconto, que segue a curva do motor deslocada ou é uma taxa só; crescimento
   na perpetuidade, sem o teto da economia; reinvestimento pelo retorno sobre
   o capital, como o motor, ou por uma parcela fixa do lucro; e o retorno do
   capital novo na perpetuidade, igual à taxa ou outro.
3. **A conta só recusa o que não tem conta**, com o campo nomeado: lucro de
   partida não positivo, taxa não positiva, parcela reinvestida fora de
   `[0, 100%)`, retorno do capital novo não positivo, e perpetuidade de Gordon
   com a taxa a menos de 0,5 ponto do crescimento perpétuo, onde ela não tem
   valor finito. O confinamento do crescimento ao que o retorno financia
   continua valendo no modo "pelo retorno" — é a identidade da retenção, e não
   opinião —, e a tela diz o ano em que ele agiu; quem quer o crescimento
   solto escolhe a parcela fixa.
4. **A taxa digitada desconta, e só desconta.** Na via da firma ela entra no
   custo do capital próprio, que é a taxa que desconta o fluxo do acionista; o
   custo médio do capital, para onde o retorno converge e que fixa o
   reinvestimento da perpetuidade da firma, fica o do motor. Mover os dois
   juntos, pela tradução dos cenários (decisão 121), foi medido e recusado: em
   12 dos 90 ativos da via da firma, subir a taxa subia o preço, porque o
   retorno convergindo a um custo maior pede menos reinvestimento, e na
   companhia endividada isso supera o desconto.
5. **A tela diz o que a conta fez**: o valor presente dos dez anos e o da
   perpetuidade, a ponte até o preço por ação, a tabela ano a ano com o fator
   de desconto, "onde você discorda do motor" — do preço do motor ao do
   usuário, um grupo de premissas de cada vez — e "o que o preço de hoje
   supõe", o valor de um campo que iguala o preço justo ao de mercado.
6. **O preço do usuário não herda a validação.** A faixa calibrada, a
   habilidade medida e as ressalvas continuam sendo do preço do motor, e a tela
   o diz.

## Consequências aceitas

- **As premissas do DCF ganharam duas costuras que a produção não usa**: a
  parcela fixa (`ReinvestmentPolicy.parcelaFixa`, `fixedRetention`) e o caminho
  de crescimento explícito (`growthPath`). Desligadas, a cascata é a mesma: o
  gabarito saiu idêntico nos 376 ativos e nas nove montagens, saída e rastro
  bit a bit.
- **O usuário pode chegar a qualquer preço**, inclusive absurdo. É a opinião
  dele sobre a conta do motor, e a tela o diz em vez de impedir.
- **A taxa digitada não move o custo médio do capital na via da firma**, e por
  isso o preço do usuário com a taxa trocada não é o que o motor daria se a
  curva subisse: aquilo é a sensibilidade do motor, e isto é a opinião do
  usuário sobre quanto exigir. Quem discorda do retorno usa o campo do retorno.
- **A conta congelada envelhece com a avaliação**: ela é a do motor na data da
  avaliação, e a tela abre de novo nela a cada vez.
