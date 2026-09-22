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
/// **Regra de arredondamento.** [operator *] e [operator /] arredondam por
/// `num.round()`, e [Money.fromReais] pelo decimal escrito (ver lá) — nos dois
/// casos *meio afastado de zero*, e não *meio para cima*. Verificado: `(-2.5).round() == -3`, enquanto meio para
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

  /// Converte um valor em reais para centavos, arredondando **o decimal
  /// escrito** meio afastado de zero.
  ///
  /// **É a fronteira do `double` para o dinheiro** — por onde passam o preço
  /// justo, os cenários e a faixa da avaliação, a cotação da simulação e o que
  /// o usuário digita. Até 22/09/2026 ela fazia `(reais * 100).round()`, e o
  /// produto em ponto flutuante perdia o meio: `1.005 * 100` resulta em
  /// `100.49999999999999`, e R$ 1,005 virava R$ 1,00. É o defeito que
  /// `test/qa_fixtures/financial_edge_cases.json` registra como
  /// `tostringasfixed-nao-e-half-up` (item B21, decisão 125).
  ///
  /// Agora o arredondamento é feito sobre a **menor representação decimal**
  /// do `double` — a que `toString` devolve, e que é a que se escreveu: `1.005`
  /// dá 101 centavos, `2.675` dá 268, `-1.005` dá −101. Um valor que já chega
  /// com erro de conta, como `0.1 + 0.2`, é arredondado pelo que ele é:
  /// `0.30000000000000004` dá 30.
  ///
  /// - [reais]: valor em reais. Aceita `int` ou `double`.
  ///
  /// Lança [UnsupportedError] se [reais] for `NaN` ou infinito — não há
  /// centavo para devolver.
  factory Money.fromReais(num reais) => Money(_centavos(reais));

  /// Centavos de [reais], arredondando o decimal escrito meio afastado de zero.
  static int _centavos(num reais) {
    if (reais is int) return reais * 100;
    final d = reais.toDouble();
    if (!d.isFinite) {
      throw UnsupportedError('Infinity or NaN toInt');
    }
    final modulo = d.abs();
    // Acima de 1e15 o `double` já não tem casa de centavo, e o produto é
    // inteiro; abaixo de 1e-6 `toString` usa notação científica, e o valor é
    // menos de meio centavo.
    if (modulo >= 1e15) return (d * 100).round();
    if (modulo < 1e-6) return 0;
    final partes = modulo.toString().split('.');
    final fracao = (partes.length > 1 ? partes[1] : '').padRight(3, '0');
    var c = int.parse(partes[0]) * 100 + int.parse(fracao.substring(0, 2));
    // O terceiro dígito decide: 5 ou mais é meio centavo ou além.
    if (fracao.codeUnitAt(2) >= 0x35) c += 1;
    return d < 0 ? -c : c;
  }

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
