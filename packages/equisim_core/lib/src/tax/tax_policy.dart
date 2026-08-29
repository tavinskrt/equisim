import '../entities/dividend_event.dart';

/// Regra tributária aplicável a um tipo de provento em uma janela de vigência.
class TaxRule {
  /// Tipo de provento a que a regra se aplica.
  final DividendKind kind;

  /// Alíquota em fração (0.15 = 15%).
  ///
  /// Deve ficar em `[0, 1)`. O valor `1.0` — tributação integral — não é
  /// representável: [TaxPolicy.withheldAmount] divide por `(1 − rate)` em base
  /// líquida e devolveria `Infinity`.
  final double rate;

  /// Vigência. `null` significa sem limite naquela ponta.
  final DateTime? effectiveFrom;

  /// Fim da vigência, inclusivo. `null` significa vigente indefinidamente.
  final DateTime? effectiveUntil;

  /// Declara uma regra. Não valida [rate] — a política é parâmetro do
  /// trabalho, e travar faixa aqui impediria simular cenários legislativos.
  const TaxRule({
    required this.kind,
    required this.rate,
    this.effectiveFrom,
    this.effectiveUntil,
  });

  /// `true` se a regra está vigente em [date], com as duas pontas inclusivas.
  ///
  /// Uma regra sem [effectiveFrom] nem [effectiveUntil] vale sempre.
  bool appliesOn(DateTime date) {
    if (effectiveFrom != null && date.isBefore(effectiveFrom!)) return false;
    if (effectiveUntil != null && date.isAfter(effectiveUntil!)) return false;
    return true;
  }
}

/// Como interpretar o valor por ação informado pela fonte.
///
/// **Premissa declarada do trabalho: [gross].** O payload de proventos traz
/// `assetIssued, paymentDate, rate, relatedTo, approvedOn, isinCode, label,
/// lastDatePrior, remarks` — nenhum campo indica a base, e nenhum permite
/// deduzi-la. Adota-se o valor bruto por ser a convenção de divulgação da B3
/// e da CVM nos avisos aos acionistas.
///
/// A premissa segue **sujeita a conferência documental** contra o "Aviso aos
/// Acionistas" de relações com investidores (ver `docs/validacao/limitacoes.md`
/// §1.5). Se a conferência indicar base líquida, basta trocar a política para
/// [TaxPolicy.brasilBaseLiquida]: o enum existe para que a reversão seja uma
/// linha de configuração, e não uma revisão dos cálculos.
///
/// A escolha importa: em base bruta, R$ 1,00 de JCP rende R$ 0,85 ao
/// investidor; tratar o mesmo R$ 1,00 como líquido quando na verdade era
/// bruto subestimaria os proventos em 15%.
enum DividendBasis {
  /// O valor informado é bruto; o imposto é deduzido dele.
  gross('bruto declarado'),

  /// O valor informado já é líquido; o imposto é deduzido por reversão.
  net('líquido de retenção');

  final String label;
  const DividendBasis(this.label);
}

/// Política fiscal aplicada aos proventos.
///
/// As alíquotas são **parâmetro declarado**, não constante de código: a API não
/// fornece alíquota alguma, e a tributação de proventos no Brasil está em
/// revisão legislativa. Fixar valores no motor tornaria o trabalho obsoleto
/// por mudança de lei.
class TaxPolicy {
  /// Nome da política, para exibição e para constar na metodologia.
  final String name;

  /// Regras avaliadas **em ordem**: a primeira que casa tipo e vigência vence.
  /// Regras posteriores para o mesmo tipo e período são inalcançáveis.
  final List<TaxRule> rules;

  /// Como interpretar o valor que a fonte informa por ação.
  final DividendBasis basis;

  const TaxPolicy({
    required this.name,
    required this.rules,
    this.basis = DividendBasis.gross,
  });

  /// Sem tributação. Usada para isolar o efeito fiscal em comparações.
  static const TaxPolicy zero = TaxPolicy(name: 'Sem tributação', rules: []);

  /// Regime vigente: JCP com 15% de IRRF retido na fonte; dividendos isentos.
  ///
  /// A base é [DividendBasis.gross] — premissa declarada, ver [DividendBasis].
  static const TaxPolicy brasil = TaxPolicy(
    name: 'Brasil — regime vigente',
    basis: DividendBasis.gross,
    rules: [
      TaxRule(kind: DividendKind.jcp, rate: 0.15),
      TaxRule(kind: DividendKind.dividendo, rate: 0.0),
      TaxRule(kind: DividendKind.rendimento, rate: 0.0),
      TaxRule(kind: DividendKind.desconhecido, rate: 0.0),
    ],
  );

  /// Variante para o caso de a conferência documental indicar que a fonte
  /// informa valores já líquidos. Trocar de política é a única alteração
  /// necessária — nenhum cálculo precisa ser reescrito.
  static const TaxPolicy brasilBaseLiquida = TaxPolicy(
    name: 'Brasil — regime vigente, fonte em base líquida',
    basis: DividendBasis.net,
    rules: [
      TaxRule(kind: DividendKind.jcp, rate: 0.15),
      TaxRule(kind: DividendKind.dividendo, rate: 0.0),
      TaxRule(kind: DividendKind.rendimento, rate: 0.0),
      TaxRule(kind: DividendKind.desconhecido, rate: 0.0),
    ],
  );

  /// Alíquota aplicável ao provento na data de pagamento.
  ///
  /// - [kind]: natureza fiscal do provento.
  /// - [on]: data de apuração, normalmente a de pagamento.
  ///
  /// Devolve `0.0` quando nenhuma regra casa — **isento por omissão**. É a
  /// escolha conservadora para o resultado bruto, e o motivo de
  /// [DividendKind.desconhecido] existir com alíquota explícita em vez de
  /// depender deste padrão.
  double rateFor(DividendKind kind, DateTime on) {
    for (final r in rules) {
      if (r.kind == kind && r.appliesOn(on)) return r.rate;
    }
    return 0.0;
  }

  /// Valor efetivamente recebido por ação, após retenção na fonte.
  ///
  /// Em [DividendBasis.gross] deduz o imposto do valor informado; em
  /// [DividendBasis.net] devolve o valor informado intacto, porque ele já é o
  /// que entra no caixa.
  ///
  /// - [event]: provento. A alíquota é apurada em `event.paymentDate`.
  double netAmount(DividendEvent event) {
    final rate = rateFor(event.kind, event.paymentDate);
    return switch (basis) {
      // O informado é bruto: o investidor recebe o que sobra após o imposto.
      DividendBasis.gross => event.amountPerShare * (1.0 - rate),
      // O informado já é líquido: é exatamente o que entra no caixa.
      DividendBasis.net => event.amountPerShare,
    };
  }

  /// Imposto retido por ação.
  ///
  /// - [event]: provento. A alíquota é apurada em `event.paymentDate`.
  ///
  /// **Precondição em base líquida: `rate < 1`.** Com [DividendBasis.net] o
  /// bruto é reconstruído por `valor · rate / (1 − rate)`, e uma alíquota de
  /// 100% produz `Infinity` — verificado — que se propaga em silêncio até a
  /// interface em vez de lançar. Não há guarda porque nenhuma política do
  /// pacote chega perto disso (a máxima vigente é 0,15) e um `clamp` mudaria o
  /// número em vez de expor o parâmetro inválido. Quem declarar política
  /// própria precisa respeitar a faixa.
  ///
  /// Devolve `0.0` sempre que a alíquota é nula, em qualquer base.
  double withheldAmount(DividendEvent event) {
    final rate = rateFor(event.kind, event.paymentDate);
    if (rate <= 0) return 0.0;
    return switch (basis) {
      DividendBasis.gross => event.amountPerShare * rate,
      // Em base líquida o imposto é deduzido por reversão: se R$ 0,85 é o
      // líquido de 15%, o bruto era 0,85/0,85 = R$ 1,00 e retiveram R$ 0,15.
      DividendBasis.net => event.amountPerShare * rate / (1.0 - rate),
    };
  }

  /// Valor bruto declarado por ação, antes de qualquer retenção.
  ///
  /// Vale `netAmount + withheldAmount` nas duas bases, por construção: em base
  /// bruta reconstitui o valor informado; em base líquida devolve o bruto
  /// implícito. Herda a precondição `rate < 1` de [withheldAmount].
  double grossAmount(DividendEvent event) =>
      netAmount(event) + withheldAmount(event);
}
