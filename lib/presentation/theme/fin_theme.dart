import 'package:flutter/material.dart';

import 'fin_colors.dart';
import 'fin_typography.dart';

/// Faixas de largura.
///
/// Nomeadas pelo que a tela **pode fazer** em cada uma, e nao pelo aparelho:
/// [compact] e iPhone SE em retrato, e e tambem a metade de uma janela de
/// desktop dividida ao meio.
enum FinBreakpoint {
  /// Menos de 600 dp: uma coluna.
  compact,

  /// De 600 a 899 dp: uma coluna larga, metricas em grade.
  medium,

  /// 900 dp ou mais: duas carteiras lado a lado.
  expanded;

  /// Classifica uma largura em dp.
  static FinBreakpoint of(double width) => width < 600
      ? FinBreakpoint.compact
      : width < 900
          ? FinBreakpoint.medium
          : FinBreakpoint.expanded;

  /// `true` na faixa estreita.
  bool get isCompact => this == FinBreakpoint.compact;

  /// `true` na faixa larga.
  bool get isExpanded => this == FinBreakpoint.expanded;
}

/// Monta o tema a partir dos tokens.
///
/// O `ColorScheme` e **derivado** da paleta, nao semeado numa cor arbitraria.
/// E isto que faz um `CircularProgressIndicator` sem cor explicita nascer
/// certo, em vez de girar no azul padrao do Material no meio de uma tela
/// verde -- o que acontecia enquanto o tema era semeado pela cor que o
/// `flutter create` escreve e que nunca havia sido tocada.
ThemeData buildFinTheme({required bool isLight}) {
  final fin = isLight ? FinColors.light : FinColors.dark;
  final type = FinTypography.standard();

  final scheme = ColorScheme(
    brightness: isLight ? Brightness.light : Brightness.dark,
    primary: fin.brand,
    onPrimary: fin.textOnBrand,
    secondary: fin.brand,
    onSecondary: fin.textOnBrand,
    error: fin.negative,
    onError: fin.surface,
    surface: fin.surface,
    onSurface: fin.textPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: fin.canvas,
    dividerColor: fin.divider,
    extensions: <ThemeExtension<dynamic>>[fin, type],
    progressIndicatorTheme: ProgressIndicatorThemeData(color: fin.brand),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: fin.surfaceRaised,
      contentTextStyle: type.bodyMd.copyWith(color: fin.textPrimary),
      behavior: SnackBarBehavior.floating,
    ),
    // Um cartao institucional nao flutua: elevacao zero e contorno de 1 px, em
    // vez da sombra que o Material aplica por padrao.
    cardTheme: CardThemeData(
      color: fin.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: fin.border),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: fin.divider,
      thickness: 1,
      space: 1,
    ),
  );
}

/// Acesso aos tokens a partir do contexto.
///
/// `context.fin.positive` no lugar de `AppColors.primary`, e
/// `context.finType.numSm` no lugar de um `TextStyle` montado a mao.
///
/// Ler do contexto, em vez de receber `isLight` por parametro em cada widget,
/// e o que permite eliminar o booleano que hoje viaja por toda a arvore. O
/// teste monta um `MaterialApp` com `buildFinTheme` -- tres linhas -- e a
/// arvore inteira enxerga a paleta.
extension FinThemeAccess on BuildContext {
  /// Paleta corrente.
  FinColors get fin => Theme.of(this).extension<FinColors>()!;

  /// Escala tipografica corrente.
  FinTypography get finType => Theme.of(this).extension<FinTypography>()!;
}
