import '../value_objects/money.dart';

/// Uma emissão de ações **por valor**, como o Formulário de Referência da CVM a
/// declara (item B28).
///
/// Subscrição pública ou particular, incorporação, conversão de título,
/// exercício de opção ou de bônus de subscrição: tudo o que põe ações novas em
/// circulação **trazendo alguma coisa em troca** — dinheiro, crédito, outra
/// companhia. **Bonificação não é emissão aqui**: ela redistribui capital que
/// já estava no balanço e não traz valor nenhum, e quem a trata é o ajuste dos
/// eventos de ações ([ShareEvent]).
///
/// **Por que a cascata precisa disto.** O capital próprio sai do último balanço
/// publicado, e o divisor é a contagem que forma a cotação de hoje. Uma emissão
/// entre as duas datas entra no divisor e não entra no patrimônio: o preço
/// justo por papel saía subavaliado na proporção do capital captado.
class ShareIssue {
  /// Data da emissão — ou da deliberação, quando o formulário não traz a da
  /// emissão.
  final DateTime date;

  /// Valor total da emissão, em centavos inteiros: é dinheiro, e somas de
  /// emissões não acumulam erro de ponto flutuante.
  final Money amount;

  /// Ações emitidas, na base do dia da emissão — inteiras, como toda
  /// quantidade de ação. Informativo: o valor é o que entra no patrimônio, e
  /// ele não depende de desdobramento posterior.
  final int shares;

  /// `true` quando o valor é o **da emissão**, declarado por ela — o quadro de
  /// aumentos do Formulário de Referência, que tem o tipo de subscrição e a
  /// forma de integralização.
  ///
  /// `false` quando é só a **variação do capital integralizado** entre duas
  /// versões do formulário, que é o que resta desde que a CVM tirou o quadro de
  /// aumentos, em 2023. Ela não distingue a bonificação que capitaliza reserva
  /// de uma emissão, nem a fusão que troca ações de uma subscrição, e já
  /// apareceu com R$ 49,8 bilhões num ativo cujo preço nem se mexeu. **A
  /// cascata não a soma**: diz que ela existe e quanto o preço justo mudaria se
  /// fosse emissão por valor.
  final bool declared;

  /// Declara a emissão.
  const ShareIssue({
    required this.date,
    required this.amount,
    required this.shares,
    this.declared = true,
  });

  /// Valor e quantidade positivos.
  bool get isUsable => amount.isPositive && shares > 0;
}
