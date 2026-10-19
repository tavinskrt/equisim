import '../presentation/theme/fin_colors.dart';

/// Força de uma senha, do ponto de vista do domínio.
///
/// Existe para tirar **cor** de dentro do controlador. Antes cada um destes
/// níveis vinha embrulhado num `Map<String, dynamic>` com uma chave `'color'`
/// carregando um literal — o que juntava dois defeitos num só: a camada de
/// regra decidindo apresentação, e a cor escapando do sistema de tokens onde
/// ninguém podia corrigi-la.
///
/// O controlador devolve significado; a tela decide como pintá-lo.
enum PasswordStrength {
  /// Nada digitado ainda.
  empty(0, ''),

  /// Curta demais.
  weak(1, 'Fraca'),

  /// Aceitável, mas sem dígito ou sem comprimento.
  medium(2, 'Média'),

  /// Boa; falta só caractere especial.
  good(3, 'Boa'),

  /// Atende a tudo que se cobra.
  strong(4, 'Forte');

  /// Quantas barras do medidor acendem.
  final int level;

  /// Rótulo exibido ao usuário.
  final String label;

  const PasswordStrength(this.level, this.label);

  /// Direção semântica correspondente, para a tela resolver a cor.
  ///
  /// O mapeamento vive aqui, e não em cada tela, porque as duas telas que
  /// mostram o medidor precisam concordar — quando estava espalhado, uma delas
  /// tinha quatro níveis e a outra três, com azul numa e não na outra.
  FinTrend get trend => switch (this) {
    PasswordStrength.empty => FinTrend.blocked,
    PasswordStrength.weak => FinTrend.negative,
    PasswordStrength.medium => FinTrend.caution,
    PasswordStrength.good => FinTrend.pending,
    PasswordStrength.strong => FinTrend.positive,
  };
}
