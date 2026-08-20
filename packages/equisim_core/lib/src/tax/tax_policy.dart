import '../entities/dividend_event.dart';

/// Regra tributária aplicável a um tipo de provento em uma janela de vigência.
class TaxRule {
  final DividendKind kind;

  /// Alíquota em fração (0.15 = 15%).
  final double rate;

  /// Vigência. `null` significa sem limite naquela ponta.
  final DateTime? effectiveFrom;
  final DateTime? effectiveUntil;

  const TaxRule({
    required this.kind,
    required this.rate,
    this.effectiveFrom,
    this.effectiveUntil,
  });

  bool appliesOn(DateTime date) {
    if (effectiveFrom != null && date.isBefore(effectiveFrom!)) return false;
    if (effectiveUntil != null && date.isAfter(effectiveUntil!)) return false;
    return true;
  }
}

/// Política fiscal aplicada aos proventos.
///
/// As alíquotas são **parâmetro declarado**, não constante de código: a API não
/// fornece alíquota alguma, e a tributação de proventos no Brasil está em
/// revisão legislativa. Fixar valores no motor tornaria o trabalho obsoleto
/// por mudança de lei.
class TaxPolicy {
  final String name;
  final List<TaxRule> rules;

  const TaxPolicy({required this.name, required this.rules});

  /// Sem tributação. Usada para isolar o efeito fiscal em comparações.
  static const TaxPolicy zero = TaxPolicy(name: 'Sem tributação', rules: []);

  /// Regime vigente: JCP com 15% de IRRF retido na fonte; dividendos isentos.
  static const TaxPolicy brasil = TaxPolicy(
    name: 'Brasil — regime vigente',
    rules: [
      TaxRule(kind: DividendKind.jcp, rate: 0.15),
      TaxRule(kind: DividendKind.dividendo, rate: 0.0),
      TaxRule(kind: DividendKind.rendimento, rate: 0.0),
      TaxRule(kind: DividendKind.desconhecido, rate: 0.0),
    ],
  );

  /// Alíquota aplicável ao provento na data de pagamento.
  double rateFor(DividendKind kind, DateTime on) {
    for (final r in rules) {
      if (r.kind == kind && r.appliesOn(on)) return r.rate;
    }
    return 0.0;
  }

  /// Valor líquido por ação após retenção na fonte.
  double netAmount(DividendEvent event) =>
      event.amountPerShare * (1.0 - rateFor(event.kind, event.paymentDate));

  /// Imposto retido por ação.
  double withheldAmount(DividendEvent event) =>
      event.amountPerShare * rateFor(event.kind, event.paymentDate);
}
