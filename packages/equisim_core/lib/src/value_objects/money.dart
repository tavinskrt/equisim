/// Valor monetário representado em **centavos inteiros**.
///
/// Dinheiro nunca é `double` no domínio: somas repetidas de `double` acumulam
/// erro de ponto flutuante, e num backtest com 120 aportes o desvio é visível.
/// Preços de mercado continuam sendo `double` (são cotações, não saldos).
///
/// **Consequência para comparação.** Por serem inteiros, `==` e os operadores
/// de ordem são exatos aqui — a proibição usual de comparar dinheiro com `==`
/// vale para representação em ponto flutuante, não para esta. Comparar dois
/// `Money` é comparar dois `int`.
///
/// **Regra de arredondamento.** [operator *], [operator /] e [Money.fromReais]
/// arredondam por `num.round()`, que em Dart é *meio afastado de zero* — não
/// *meio para cima*. Verificado: `(-2.5).round() == -3`, enquanto meio para
/// cima devolveria `-2`. A diferença só aparece em valores negativos exatamente
/// no meio (estornos, fatias de aporte negativo), e é simétrica: o mesmo módulo
/// arredonda para o mesmo módulo, com o sinal preservado.
///
/// **O que esta classe não faz.** Não distribui resto. Multiplicar um valor por
/// N pesos que somam 1,0 e somar as fatias **não** reconstitui o valor original,
/// porque cada fatia arredonda isoladamente. Quem divide dinheiro entre vários
/// destinos precisa tratar o resíduo explicitamente no ponto da divisão.
class Money implements Comparable<Money> {
  /// Quantidade de centavos. É a única representação canônica do valor;
  /// [reais] é derivado e existe para exibição.
  final int cents;

  /// Constrói a partir da quantidade de centavos, sem validação.
  ///
  /// Valores negativos são legítimos e representam saída de caixa — aporte na
  /// convenção da TIR, estorno, imposto retido.
  const Money(this.cents);

  /// Converte um valor em reais para centavos, arredondando.
  ///
  /// **Não é arredondamento decimal exato.** O produto `reais * 100` é
  /// calculado em ponto flutuante binário antes do arredondamento, e valores
  /// que parecem estar no meio muitas vezes não estão. Verificado:
  /// `Money.fromReais(1.005).cents == 100`, não 101, porque `1.005 * 100`
  /// resulta em `100.49999999999999`.
  ///
  /// Use este construtor apenas na fronteira de entrada, sobre valores que já
  /// vêm como cotação ou digitação do usuário. Para aritmética interna, opere
  /// sobre [cents].
  ///
  /// - [reais]: valor em reais. Aceita `int` ou `double`.
  ///
  /// Retorna o [Money] correspondente.
  ///
  /// Lança [UnsupportedError] se [reais] for `NaN` ou infinito — `round()` não
  /// tem inteiro para devolver.
  factory Money.fromReais(num reais) => Money((reais * 100).round());

  /// Zero absoluto. Ponto neutro da soma.
  static const Money zero = Money(0);

  /// Valor em reais, para exibição e para cálculo em ponto flutuante.
  ///
  /// **Fronteira de apresentação.** Acumular sobre este getter reintroduz
  /// exatamente o erro que a representação em centavos existe para evitar.
  double get reais => cents / 100.0;

  /// `true` quando o valor é exatamente zero centavo.
  bool get isZero => cents == 0;

  /// `true` quando o valor é **estritamente** maior que zero.
  ///
  /// Zero não é positivo: `Money.zero.isPositive` é `false`. É o que permite
  /// usar este getter como guarda antes de dividir por um saldo.
  bool get isPositive => cents > 0;

  /// Soma exata, em aritmética inteira.
  Money operator +(Money other) => Money(cents + other.cents);

  /// Subtração exata, em aritmética inteira. O resultado pode ser negativo.
  Money operator -(Money other) => Money(cents - other.cents);

  /// Multiplica por um fator adimensional, arredondando o resultado.
  ///
  /// Usado para aplicar peso, alíquota ou margem. O arredondamento é meio
  /// afastado de zero (ver a doc da classe), e **o resto é perdido**: a soma de
  /// `valor * w` sobre pesos que somam 1,0 não reconstitui `valor`.
  ///
  /// - [factor]: fator em fração (`0.15` para 15%).
  ///
  /// Lança [UnsupportedError] se [factor] for `NaN` ou infinito.
  Money operator *(num factor) => Money((cents * factor).round());

  /// Divide por um escalar, arredondando o resultado.
  ///
  /// - [divisor]: divisor adimensional.
  ///
  /// Lança [UnsupportedError] quando [divisor] é `0`: a divisão inteira em
  /// Dart devolve `double`, então `cents / 0` produz `Infinity` (ou `NaN` se
  /// [cents] também for zero) e `round()` recusa convertê-lo. Verificado — o
  /// erro é `Unsupported operation: Infinity or NaN toInt`. **Não há retorno
  /// silencioso**: a falha é visível no ponto da divisão, e por isso o chamador
  /// precisa garantir `divisor != 0` em vez de conferir o resultado depois.
  Money operator /(num divisor) => Money((cents / divisor).round());

  /// Inverte o sinal. Exato.
  Money operator -() => Money(-cents);

  /// Estritamente menor que [other].
  bool operator <(Money other) => cents < other.cents;

  /// Menor ou igual a [other].
  bool operator <=(Money other) => cents <= other.cents;

  /// Estritamente maior que [other].
  bool operator >(Money other) => cents > other.cents;

  /// Maior ou igual a [other].
  bool operator >=(Money other) => cents >= other.cents;

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => 'R\$ ${reais.toStringAsFixed(2)}';
}
