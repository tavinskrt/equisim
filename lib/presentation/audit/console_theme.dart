import 'package:flutter/material.dart';

/// Paleta do console de auditoria.
///
/// **Segunda paleta declarada do repositorio, e isso e deliberado.** Ela vive
/// em arquivo proprio pelo mesmo motivo que `FinColors`: literal de cor so
/// existe onde a paleta e DECLARADA, nunca no ponto de uso. A fronteira ser um
/// caminho, e nao uma excecao anotada, e o que permite ao gate verifica-la.
///
/// Nao se funde com `FinColors` porque as duas respondem a perguntas
/// diferentes: aquela carrega semantica financeira -- lucro, perda, ressalva --
/// e esta carrega realce de sintaxe de um console de depuracao (chave de JSON,
/// literal de texto, numero). Forcar uma na outra tornaria as duas piores.
///
/// Independente do tema da aplicação de propósito: a janela de auditoria é uma
/// instância separada, sem sessão e sem preferências carregadas, e o painel
/// costuma ser projetado num telão — onde ora o escuro, ora o claro é o
/// legível. O alternador local resolve isso sem arrastar o controlador de tema
/// e sua dependência de Firebase para dentro do painel.
class ConsoleTheme {
  const ConsoleTheme(this.dark);

  final bool dark;

  Color get background =>
      dark ? const Color(0xFF0B1020) : const Color(0xFFF4F6FB);
  Color get panel => dark ? const Color(0xFF121A33) : Colors.white;
  Color get border => dark ? const Color(0xFF25314F) : const Color(0xFFDDE3F0);
  Color get text => dark ? const Color(0xFFE6ECFA) : const Color(0xFF0B1E4B);
  Color get dim => dark ? const Color(0xFF8494B8) : const Color(0xFF7A88A6);

  Color get accent => const Color(0xFF00B37E);
  Color get network => const Color(0xFF4C8DFF);
  Color get warning => dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
  Color get danger => const Color(0xFFEF4444);

  Color get jsonKey => dark ? const Color(0xFF7FD1FF) : const Color(0xFF0A6C9E);
  Color get jsonString =>
      dark ? const Color(0xFFB6E3A8) : const Color(0xFF2E7D32);
  Color get jsonNumber =>
      dark ? const Color(0xFFFFC48A) : const Color(0xFFB45309);
  Color get jsonBool =>
      dark ? const Color(0xFFD8A6FF) : const Color(0xFF7B1FA2);

  /// Estilo monoespaçado com cadeia de reserva.
  ///
  /// O alvo web não embarca fonte monoespaçada; a lista cobre Windows, macOS e
  /// Linux para que o alinhamento das colunas de números não dependa de qual
  /// máquina abrir o painel na apresentação.
  TextStyle mono({required Color color, double size = 12, bool bold = false}) =>
      TextStyle(
        color: color,
        fontSize: size,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        fontFamily: 'monospace',
        fontFamilyFallback: const [
          'Consolas',
          'Menlo',
          'DejaVu Sans Mono',
          'Courier New',
          'monospace',
        ],
      );
}
