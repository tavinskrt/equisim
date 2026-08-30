---
numero: 21
titulo: Sistema de design próprio e adequação à WCAG, em quatro ondas
status: aceita
origem: voce
data: 2026-08-29
afeta:
  - lib/presentation/theme
  - lib/presentation/shared
  - lib/presentation/components
  - test/presentation
substitui: []
---

## Contexto

Segunda tensão ESTRUTURAL reportada pela lente `registro`, ancorada no commit
`85fd0c1`: o parecer declara as Fases 0 a 5 concluídas e "o plano completo e
validado", e nove commits posteriores — as Ondas 1 a 4 — reconstruíram a
camada de apresentação sem que nada disso tenha lugar no roadmap.

A interface anterior declarava cor, tipografia e espaçamento no ponto de uso.
O efeito medido antes da migração: 62 literais `Color(0x...)` e 209 espaçadores
sem origem comum. Cor declarada onde é usada não pode ser corrigida de um lugar
só, e foi assim que contraste reprovado se espalhou pela base.

## Decisão

Construir um sistema de design próprio, sem pacote de terceiros, e migrar a
camada de apresentação para ele em quatro ondas:

- **Tokens** em [lib/presentation/theme/](../../lib/presentation/theme/) —
  `fin_colors.dart`, `fin_typography.dart`, `fin_space.dart`, `fin_theme.dart`.
- **Contraste medido, não estimado.** Cada token de cor de texto ou de estado
  carrega a razão de contraste ao lado, com asserção correspondente em
  `test/presentation/contrast_test.dart`.
- **Verificação de estouro por largura e escala de texto** em
  `test/presentation/overflow_test.dart`: quatro telas × 320/390/1024 dp ×
  escala 1.0/1.3/2.0.
- **Regras R17 a R25** no rulebook do auditor, dormentes até
  `fin_colors.dart` existir e despertas a partir dele.

## Consequências aceitas

- **Nenhum pacote de UI de terceiros.** `google_fonts`, `flutter_screenutil`,
  `responsive_framework`, `gap` e `shimmer` ficam proibidos por regra explícita
  no rulebook. O custo é escrever o que eles dariam pronto; o ganho é que a
  correção de contraste tem um lugar só.
- **Literal novo em arquivo já migrado é regressão, não dívida.** É a única
  situação em que uma regra de design reprova o commit — o sistema existe
  naquele arquivo e foi contornado deliberadamente.
- **A migração torna desconfortável mover linha legada.** O git registra linha
  movida como adicionada, e a regra dispara. A ordem de trabalho pretendida é
  migrar o arquivo inteiro e só então commitar.
- **Isto resolveu a base do código, não a direção visual.** Tokens, contraste e
  ausência de estouro são condições necessárias e não suficientes: a disposição
  dos elementos, a hierarquia e a arquitetura de informação continuam abertas, e
  são objeto da lente `tela` do conselheiro.
