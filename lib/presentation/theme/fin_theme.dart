import 'package:flutter/material.dart';

import 'fin_colors.dart';
import 'fin_typography.dart';

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
    dividerTheme: DividerThemeData(color: fin.divider, thickness: 1, space: 1),
  );
}

/// Acesso aos tokens a partir do contexto.
///
/// `context.fin.positive` no lugar de um literal de cor, e
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
