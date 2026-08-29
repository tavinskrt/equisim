import '../value_objects/ticker.dart';

/// Natureza fiscal do provento, conforme o campo `label` da fonte.
enum DividendKind {
  /// Juros sobre Capital Próprio — sofre IRRF retido na fonte.
  jcp('JCP'),

  /// Dividendo — isento sob a regra vigente.
  dividendo('DIVIDENDO'),

  /// Rendimento — tratado como dividendo (ponto em aberto nº 16).
  rendimento('RENDIMENTO'),

  /// Rótulo desconhecido: tratado de forma conservadora como dividendo.
  desconhecido('DESCONHECIDO');

  /// Rótulo em maiúsculas, exatamente como a fonte o publica.
  final String label;

  const DividendKind(this.label);

  /// Converte o rótulo da fonte no tipo fiscal.
  ///
  /// - [raw]: rótulo bruto. Aceita `null`, espaços e caixa mista.
  ///
  /// Devolve [DividendKind.desconhecido] para rótulo nulo, vazio ou não
  /// reconhecido — **nunca lança**. Como `desconhecido` é tributado como
  /// dividendo (isento), um rótulo novo da fonte superestima o líquido em vez
  /// de derrubar a simulação; é a escolha deliberada, e o tipo separado existe
  /// para que o caso fique visível na auditoria.
  static DividendKind fromLabel(String? raw) {
    final normalized = (raw ?? '').trim().toUpperCase();
    for (final k in DividendKind.values) {
      if (k.label == normalized) return k;
    }
    return DividendKind.desconhecido;
  }
}

/// Provento distribuído por uma empresa.
///
/// [exDate] (`lastDatePrior` na fonte) determina **quem tem direito**;
/// [paymentDate] determina **quando o caixa entra**. O motor usa as duas.
class DividendEvent {
  /// Ativo que distribuiu o provento.
  final Ticker ticker;

  /// Data-ex: quem detinha a ação **antes** dela tem direito ao provento.
  /// Truncada para o dia na construção.
  final DateTime exDate;

  /// Data em que o caixa entra e o reinvestimento acontece. Truncada para o
  /// dia. Pode ser anterior a [exDate] em dado malformado — não há validação
  /// de ordem, e o motor trata o par como o encontra.
  final DateTime paymentDate;

  /// Valor por ação, exatamente como a fonte informa.
  ///
  /// A interpretação — bruto ou líquido de retenção — não vive aqui: é
  /// decidida pela `TaxPolicy` através de `DividendBasis`. A premissa vigente
  /// do trabalho é **base bruta**, sujeita a conferência documental.
  ///
  /// Vem por **unit** nos ativos negociados em unit, na mesma convenção da
  /// cotação — e não por ação, como os demonstrativos.
  final double amountPerShare;

  /// Natureza fiscal, que determina a alíquota aplicada pela `TaxPolicy`.
  final DividendKind kind;

  /// `true` quando a fonte marcou a data de pagamento como estimada
  /// (`remarks = "csv:payment_date_estimated"`).
  final bool paymentDateEstimated;

  /// Constrói o evento truncando [exDate] e [paymentDate] para o dia.
  ///
  /// O truncamento é o que permite comparar essas datas com as de pregão sem
  /// que a hora publicada pela fonte desloque um evento para o dia seguinte.
  DividendEvent({
    required this.ticker,
    required DateTime exDate,
    required DateTime paymentDate,
    required this.amountPerShare,
    required this.kind,
    this.paymentDateEstimated = false,
  })  : exDate = DateTime(exDate.year, exDate.month, exDate.day),
        paymentDate =
            DateTime(paymentDate.year, paymentDate.month, paymentDate.day);
}
