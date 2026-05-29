import 'package:flutter/material.dart';

/// Definição do sistema de cores e identidades visuais da aplicação.
class AppColors {
  // Construtor privado para impedir instanciação da classe utilitária
  AppColors._();

  // Cores Base do Sistema Adaptadas para os Modos Claro e Escuro
  static Color backgroundStart(bool isLight) => isLight ? const Color(0xFFF0F3FA) : const Color(0xFF0B1E4B);
  static Color backgroundMiddle(bool isLight) => isLight ? const Color(0xFFF0F3FA) : const Color(0xFF0F2C6A);
  static Color backgroundEnd(bool isLight) => isLight ? const Color(0xFFF0F3FA) : const Color(0xFF0D3D2F);

  static Color textPrimary(bool isLight) => isLight ? const Color(0xFF0B1E4B) : Colors.white;
  static Color textSecondary(bool isLight) => isLight ? const Color(0xFF8896B3) : Colors.white.withValues(alpha: 0.5);
  static Color textMuted(bool isLight) => isLight ? const Color(0xFFA8B4CC) : Colors.white.withValues(alpha: 0.3);

  // Cores de Componentes de Interface (Superfícies, Inputs e Delimitadores)
  static Color surface(bool isLight) => isLight ? Colors.white : Colors.white.withValues(alpha: 0.04);
  static Color surfaceBorder(bool isLight) => isLight ? const Color(0xFFDDE3F0) : Colors.white.withValues(alpha: 0.1);
  static Color inputBackground(bool isLight) => isLight ? const Color(0xFFF4F6FB) : Colors.white.withValues(alpha: 0.07);
  
  static Color divider(bool isLight) => isLight ? const Color(0xFFEEF1F8) : Colors.white.withValues(alpha: 0.07);

  // Cores Globais da Marca (Sem alteração conforme o tema da aplicação)
  static const Color primary = Color(0xFF00B37E);
  static const Color primaryLight = Color(0xFF00CC8F);
  static const Color danger = Color(0xFFEF4444);

  // Gradientes Visuais Utilitários da Marca
  static LinearGradient brandGradient = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryLight],
  );

  static LinearGradient backgroundGradient(bool isLight) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      backgroundStart(isLight),
      backgroundMiddle(isLight),
      backgroundEnd(isLight),
    ],
    stops: const [0.0, 0.55, 1.0],
  );
}
