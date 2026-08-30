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

A lente `registro` reportou as Ondas 1 a 4 como ESTRUTURA SEM REGISTRO, por
correrem fora do roadmap do parecer. **A leitura estava incompleta, e o registro
corrige isso aqui:** o `PLANO_ARQUITETURA.md` é um plano de *transição* do
Equisim antigo para esta versão, escrito por volta de 15/08/2026 e já
descontinuado quando as Ondas aconteceram — todas em 29/08/2026. Elas não
pertencem àquele roadmap e não devem ser retroencaixadas nele.

O que o agente enxergou como lacuna era, na verdade, um documento que já tinha
cumprido seu papel. Isso reforça a decisão 19 em vez de contrariá-la: o parecer
estava descontinuado de fato antes de ser congelado de direito.

A interface anterior declarava cor, tipografia e espaçamento no ponto de uso.
O efeito medido antes da migração: 62 literais `Color(0x...)` e 209 espaçadores
sem origem comum. Cor declarada onde é usada não pode ser corrigida de um lugar
só, e foi assim que contraste reprovado se espalhou pela base.

## Decisão

Migrar a camada de apresentação para um sistema de design próprio, em quatro
ondas, e adequá-la à WCAG. O que ficou construído:

- **Tokens** em [lib/presentation/theme/](../../lib/presentation/theme/) —
  `fin_colors.dart`, `fin_typography.dart`, `fin_space.dart`, `fin_theme.dart`.
- **Contraste medido, não estimado.** Cada token de cor de texto ou de estado
  carrega a razão de contraste ao lado, com asserção correspondente em
  `test/presentation/contrast_test.dart`.
- **Verificação de estouro por largura e escala de texto** em
  `test/presentation/overflow_test.dart`: quatro telas × 320/390/1024 dp ×
  escala 1.0/1.3/2.0.
- **Regras R17 a R25** no rulebook do auditor, dormentes até `fin_colors.dart`
  existir e despertas a partir dele.

## Consequências aceitas

- **Isto resolveu a base do código, não a direção visual.** Tokens, contraste e
  ausência de estouro são condições necessárias e não suficientes: a disposição
  dos elementos, a hierarquia e a arquitetura de informação continuam abertas.

  São objeto da lente `tela` do conselheiro, e a **redisposição da UI começa
  quando as fases da integração terminarem** — como trabalho declarado, com
  fronteira escrita e decisão própria, sob a postura de reconstrução.

- **A migração torna desconfortável mover linha legada.** O git registra linha
  movida como adicionada, e a regra dispara. A ordem de trabalho pretendida é
  migrar o arquivo inteiro e só então commitar.

## Restrições sob as quais isto foi feito

Estas valiam no repositório e moldaram o resultado, mas **não foram decididas
nesta ocasião** e sua origem não está registrada em lugar nenhum. Ficam aqui
como contexto, não como decisão — quem quiser mudá-las precisa primeiro
descobrir de onde vieram:

- **Nenhum pacote de UI de terceiros.** `google_fonts`, `flutter_screenutil`,
  `responsive_framework`, `gap` e `shimmer` são proibidos por regra explícita no
  rulebook do auditor.
- **Literal novo em arquivo já migrado é tratado como regressão**, e é a única
  situação em que uma regra de design reprova o commit.
