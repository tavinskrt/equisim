# 2026-10-14 — orientador

Recado do orientador, trazido pelo usuário.

- Parabenizou o trabalho até o último commit. Refez os valuations por Gordon
  padrão e chegou a valores que diferiam dos do motor por centavos.
- Pediu que se detalhasse melhor o motivo das normalizações: "Ele quer entender
  o porquê das normalizações (e não retirar), e também o motivo de ter
  normalizado pra cima ou pra baixo."
- O usuário pediu a mudança no painel de logs e na tela de edição do valuation.

## Destino

- A Saída 1 passou a guardar a decisão da normalização num registro com os
  valores que a tomaram (`BaseNormalization`, em
  `ValuationDiagnostics.baseNormalization`), sem mudar regra nem número: o
  gabarito saiu igual em preço, cenários e diagnósticos.
- O painel de logs abre o passo "Base do fluxo" com o quadro "Por quê", em texto
  corrido: por que normalizar, a direção com os números do ativo, o teste e a
  conta (`CalculationTrace.explanation`).
- A tela Editar valuation traz, no cartão do lucro de partida, a pergunta "Por
  que o motor subiu (ou baixou) o lucro de partida?", com os anos do ciclo em
  barras, o teste, a conta e as travas.
- O porquê de cada um dos 110 avaliados está em
  [normalizacoes.md](../validacao/normalizacoes.md).
- Conferir a explicação contra o código achou uma frase errada no aviso e no
  rastro — "a base converge para o ciclo ao longo da projeção" —, corrigida: o
  fator vale já no ano zero, e o que converge é o retorno sobre o capital.
- Documentado no capítulo 3 do motor (3.2.1), no 7 (7.5), no guia de estudo
  (4.4), no glossário e na auditoria de cálculos.
