/// Valor monetário representado em **centavos inteiros**.
///
/// Dinheiro nunca é `double` no domínio: somas repetidas de `double` acumulam
/// erro de ponto flutuante, e num backtest com 120 aportes o desvio é visível.
/// Preços de mercado continuam sendo `double` (são cotações, não saldos).
class Money implements Comparable<Money> {
  final int cents;

  const Money(this.cents);

  factory Money.fromReais(num reais) => Money((reais * 100).round());

  static const Money zero = Money(0);

  double get reais => cents / 100.0;
  bool get isZero => cents == 0;
  bool get isPositive => cents > 0;

  Money operator +(Money other) => Money(cents + other.cents);
  Money operator -(Money other) => Money(cents - other.cents);
  Money operator *(num factor) => Money((cents * factor).round());
  Money operator /(num divisor) => Money((cents / divisor).round());
  Money operator -() => Money(-cents);

  bool operator <(Money other) => cents < other.cents;
  bool operator <=(Money other) => cents <= other.cents;
  bool operator >(Money other) => cents > other.cents;
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
