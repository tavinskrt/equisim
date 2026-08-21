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

  final String label;
  const DividendKind(this.label);

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
  final Ticker ticker;
  final DateTime exDate;
  final DateTime paymentDate;

  /// Valor por ação, exatamente como a fonte informa.
  ///
  /// A interpretação — bruto ou líquido de retenção — não vive aqui: é
  /// decidida pela `TaxPolicy` através de `DividendBasis`. A premissa vigente
  /// do trabalho é **base bruta**, sujeita a conferência documental.
  final double amountPerShare;

  final DividendKind kind;

  /// `true` quando a fonte marcou a data de pagamento como estimada
  /// (`remarks = "csv:payment_date_estimated"`).
  final bool paymentDateEstimated;

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
