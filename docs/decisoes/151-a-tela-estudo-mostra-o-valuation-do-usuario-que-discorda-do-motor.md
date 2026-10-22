---
numero: 151
titulo: A tela Estudo mostra o valuation do usuário quando ele discorda do motor
status: aceita
origem: voce
data: 2026-10-22
citacao: >
  the valuations should be updated on main screen "Estudo" (upside and fair
  price) too, if modified against the engine.
afeta:
  - lib/presentation/valuation/saved_valuations.dart
  - lib/presentation/study/study_page.dart
  - docs/motor/07-aplicativo.md
  - test/ui/study_user_valuation_test.dart
substitui: []
---

## Contexto

A decisão 150 passou a gravar o valuation que o usuário confirma na edição, e
o mostrou na aba Valuation e no painel de logs. A tela Estudo, onde as
carteiras Principal e Reserva listam o potencial e o preço justo de cada ação,
continuou mostrando só o do motor: quem discordava do motor e confirmava a
própria conta não a via onde monta as carteiras.

## Decisão

**Na lista de ativos do Estudo, o valuation do usuário substitui o do motor
quando discorda dele.**

1. Vale o **mais recente** valuation confirmado para o ativo, se algum campo
   foi trocado em relação ao motor. Confirmar os números do motor tal como
   estão é concordar com ele, e devolve o ativo ao preço do motor.
2. O preço justo é o gravado, e o potencial é contra a **cotação de hoje** — a
   da avaliação do motor em tela —, e não a do dia da confirmação: o que a
   coluna pergunta é quanto falta hoje para o preço que o usuário defende.
3. A linha diz de quem é o preço: "seu R$ …" no lugar de "justo R$ …", e a
   dica nomeia a data da confirmação e o preço do motor.
4. O valuation é **do usuário**, e não de um estudo: o mesmo ativo mostra o
   mesmo preço dele na Principal e na Reserva, em qualquer estudo aberto. O
   documento do estudo não muda.

## Consequências aceitas

- **O "Esperado da carteira" não muda**: ele não usa preço justo nenhum
  (decisões 58 e 103), e o do usuário não tem validação que o sustente.
- **A simulação continua de preço**, sem relação com o preço justo.
- Guardar o valuation dentro de cada estudo foi descartado: o mesmo ativo
  poderia ter dois preços do usuário em dois estudos, e a confirmação feita na
  aba Valuation não saberia para qual estudo ir.
