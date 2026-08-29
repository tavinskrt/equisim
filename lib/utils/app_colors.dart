import 'package:flutter/material.dart';

/// Definição do sistema de cores e identidades visuais da aplicação.
///
/// **Duas famílias, com regras distintas.** As cores de superfície e de texto
/// são funções de `isLight` e mudam com o tema; as cores de marca e de estado
/// são constantes e valem nos dois modos, porque o significado que carregam —
/// lucro, perda, ressalva — não pode inverter junto com o fundo.
///
/// Receber `isLight` por parâmetro, em vez de ler o tema do `BuildContext`,
/// mantém a paleta utilizável fora da árvore de widgets: em teste, em geração
/// de gráfico e no cálculo de contraste.
class AppColors {
  // Construtor privado para impedir instanciação da classe utilitária
  AppColors._();

  // --- Fundo e texto: variam com o tema ---

  /// Primeira parada do gradiente de fundo.
  ///
  /// No modo claro as três paradas são idênticas — o gradiente degenera em cor
  /// chapada de propósito, porque sobre fundo claro o degradê competia com o
  /// conteúdo. No escuro elas percorrem do azul-marinho ao verde-petróleo.
  static Color backgroundStart(bool isLight) => isLight ? const Color(0xFFF0F3FA) : const Color(0xFF0B1E4B);
  /// Parada intermediária do gradiente de fundo, em 55%.
  static Color backgroundMiddle(bool isLight) => isLight ? const Color(0xFFF0F3FA) : const Color(0xFF0F2C6A);
  /// Última parada do gradiente de fundo.
  static Color backgroundEnd(bool isLight) => isLight ? const Color(0xFFF0F3FA) : const Color(0xFF0D3D2F);

  /// Texto de leitura principal — títulos e valores.
  static Color textPrimary(bool isLight) => isLight ? const Color(0xFF0B1E4B) : Colors.white;
  /// Texto de apoio: rótulos, legendas, unidades.
  static Color textSecondary(bool isLight) => isLight ? const Color(0xFF8896B3) : Colors.white.withValues(alpha: 0.5);
  /// Texto de menor hierarquia: marcas de eixo e notas de rodapé.
  ///
  /// É o nível mais fraco da escala; abaixo dele o contraste deixa de ser
  /// legível sobre o fundo.
  static Color textMuted(bool isLight) => isLight ? const Color(0xFFA8B4CC) : Colors.white.withValues(alpha: 0.3);

  // --- Superfícies e delimitadores: variam com o tema ---

  /// Fundo de cartão. No escuro é **translúcido**, não opaco: é o que deixa o
  /// gradiente atravessar e dá o efeito de vidro de `GlassCard`.
  static Color surface(bool isLight) => isLight ? Colors.white : Colors.white.withValues(alpha: 0.04);
  /// Contorno de cartão, um degrau acima da superfície em contraste.
  static Color surfaceBorder(bool isLight) => isLight ? const Color(0xFFDDE3F0) : Colors.white.withValues(alpha: 0.1);
  /// Fundo de campo de entrada, distinto da superfície para sinalizar que a
  /// área aceita digitação.
  static Color inputBackground(bool isLight) => isLight ? const Color(0xFFF4F6FB) : Colors.white.withValues(alpha: 0.07);
  
  /// Linha divisória. É o menor contraste da paleta — separa sem competir.
  static Color divider(bool isLight) => isLight ? const Color(0xFFEEF1F8) : Colors.white.withValues(alpha: 0.07);

  // --- Marca e estado: constantes nos dois temas ---

  /// Verde da marca. Também significa ganho nos gráficos e nas métricas.
  static const Color primary = Color(0xFF00B37E);

  /// Variante clara do verde, usada apenas como segunda parada de gradiente.
  static const Color primaryLight = Color(0xFF00CC8F);

  /// Vermelho de perda e de erro. **Reservado a valor negativo e a falha** —
  /// ver [warning] para o caso de número duvidoso porém positivo.
  static const Color danger = Color(0xFFEF4444);

  /// Ressalva: o número existe, mas não deve ser lido como precisão.
  ///
  /// Separada de [danger] de propósito. Vermelho já significa "perda" nesta
  /// interface — pintar de vermelho um upside de +447% diria a coisa errada.
  /// O âmbar diz "olhe as premissas antes de confiar".
  static const Color warning = Color(0xFFD97706);
  /// Variante do âmbar para fundo escuro, onde [warning] perde contraste.
  static const Color warningDark = Color(0xFFFBBF24);

  // --- Gradientes ---

  /// Gradiente da marca, do canto superior esquerdo ao inferior direito.
  /// Usado em elementos de destaque, nunca como fundo de tela.
  static LinearGradient brandGradient = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryLight],
  );

  /// Gradiente de fundo de tela, montado a partir das três paradas.
  ///
  /// No modo claro resulta em cor chapada, porque as três paradas coincidem.
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
