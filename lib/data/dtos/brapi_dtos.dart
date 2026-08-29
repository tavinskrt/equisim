import 'package:equisim_core/equisim_core.dart';

/// Utilitários de extração tolerante do JSON da brapi.
///
/// A API varia a forma da resposta entre endpoints — `results` na maioria,
/// `data` aninhado ou plano, ora objeto ora lista. Toda essa irregularidade
/// fica confinada aqui: nada dela atravessa para o domínio.
abstract final class BrapiJson {
  /// Lista `results` da resposta padrão.
  static List<dynamic> results(dynamic body) {
    if (body is Map<String, dynamic>) {
      final value = body['results'];
      if (value is List) return value;
    }
    return const [];
  }

  /// Primeiro `results[0].data`, aceitando `data` ausente (payload plano).
  static Map<String, dynamic>? firstData(dynamic body) {
    final list = results(body);
    if (list.isEmpty) return null;
    final first = list.first;
    if (first is! Map<String, dynamic>) return null;
    final data = first['data'];
    if (data is Map<String, dynamic>) return data;
    return first;
  }

  /// `results[0].data` quando ele é uma **lista** — caso de `mode=history`.
  static List<dynamic> firstDataList(dynamic body) {
    final list = results(body);
    if (list.isEmpty) return const [];
    final first = list.first;
    if (first is! Map<String, dynamic>) return const [];
    final data = first['data'];
    return data is List ? data : const [];
  }

  /// Extrai um número, aceitando `num` ou texto.
  ///
  /// Troca vírgula por ponto antes de converter, porque a fonte alterna entre
  /// as duas convenções decimais. Devolve `null` para qualquer outra coisa —
  /// **inclusive texto não numérico**, que não lança.
  static double? asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.'));
    return null;
  }

  /// Extrai um texto não vazio, já aparado.
  ///
  /// Devolve `null` para valor ausente, de outro tipo, ou composto só de
  /// espaços — o que trata string vazia e ausência como a mesma coisa.
  static String? asString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  /// Converte epoch em segundos ou string ISO para data sem horário.
  ///
  /// Aceita `int` (epoch em **segundos**, não milissegundos) e texto ISO, com
  /// ou sem componente de hora. O resultado é sempre truncado para o dia, em
  /// hora local.
  ///
  /// **O epoch é interpretado como UTC e a data resultante é local.** Um
  /// instante logo após a meia-noite UTC vira o dia anterior em Brasília. É
  /// aceitável porque a fonte publica datas de pregão e de provento ao meio-dia
  /// UTC, longe da virada.
  ///
  /// Devolve `null` para valor ausente, de outro tipo ou não parseável.
  static DateTime? asDate(dynamic value) {
    if (value is int) {
      final dt = DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
      return DateTime(dt.year, dt.month, dt.day);
    }
    if (value is String && value.isNotEmpty) {
      final iso = value.contains('T') ? value.split('T').first : value;
      final parsed = DateTime.tryParse(iso);
      if (parsed == null) return null;
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
    return null;
  }

  /// Formata a data como `AAAA-MM-DD`, para chave de cache e identidade.
  static String isoDay(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// Cotação diária vinda de `/v2/stocks/historical`.
class BrapiPriceDto {
  /// Dia do pregão, truncado.
  final DateTime date;

  /// Fechamento ajustado por desdobramento e grupamento.
  final double close;

  /// Fechamento ajustado também por proventos. **Não usar em cálculo**:
  /// subajusta proventos brasileiros, sobretudo JCP.
  final double? adjustedClose;

  /// Declara o DTO.
  const BrapiPriceDto({
    required this.date,
    required this.close,
    this.adjustedClose,
  });

  static BrapiPriceDto? fromJson(Map<String, dynamic> json) {
    final date = BrapiJson.asDate(json['date']);
    final close = BrapiJson.asDouble(json['close']);
    if (date == null || close == null || close <= 0) return null;
    return BrapiPriceDto(
      date: date,
      close: close,
      adjustedClose: BrapiJson.asDouble(json['adjustedClose']),
    );
  }

  PricePoint toDomain() => PricePoint(
        date: date,
        close: close,
        adjustedClose: adjustedClose,
      );
}

/// Provento vindo de `/v2/stocks/dividends` → `cashDividends`.
class BrapiDividendDto {
  /// Data-ex — `lastDatePrior` na fonte. Define quem tem direito.
  final DateTime exDate;

  /// Data de pagamento. Define quando o caixa entra.
  final DateTime paymentDate;

  /// Valor por papel, na convenção bruta da fonte.
  final double rate;

  /// Rótulo fiscal cru (`JCP`, `DIVIDENDO`, `RENDIMENTO`, …).
  final String label;

  /// Observações da fonte. É onde vem a marca de data estimada.
  final String? remarks;

  /// Declara o DTO.
  const BrapiDividendDto({
    required this.exDate,
    required this.paymentDate,
    required this.rate,
    required this.label,
    this.remarks,
  });

  /// `lastDatePrior` é a data-ex (quem detém tem direito); `paymentDate` é
  /// quando o caixa entra. Quando falta a data-ex, o pagamento é usado como
  /// aproximação conservadora.
  static BrapiDividendDto? fromJson(Map<String, dynamic> json) {
    final payment = BrapiJson.asDate(json['paymentDate']);
    final ex = BrapiJson.asDate(json['lastDatePrior']) ?? payment;
    final rate = BrapiJson.asDouble(json['rate']);
    if (payment == null || ex == null || rate == null || rate <= 0) return null;
    return BrapiDividendDto(
      exDate: ex,
      paymentDate: payment,
      rate: rate,
      label: BrapiJson.asString(json['label']) ?? '',
      remarks: BrapiJson.asString(json['remarks']),
    );
  }

  /// A fonte marca parte das datas de pagamento como estimadas
  /// (`csv:payment_date_estimated`) — 154 ocorrências só em ITUB4. O motor
  /// credita o provento na data de pagamento, então isso desloca o
  /// reinvestimento em alguns dias e precisa chegar ao domínio.
  bool get paymentDateEstimated =>
      (remarks ?? '').contains('payment_date_estimated');

  /// Converte para a entidade de domínio.
  ///
  /// - [ticker]: ativo pagador, que o payload de proventos não repete.
  ///
  /// O rótulo cru vira [DividendKind] por `fromLabel`, que nunca falha: rótulo
  /// desconhecido vira [DividendKind.desconhecido].
  DividendEvent toDomain(Ticker ticker) => DividendEvent(
        ticker: ticker,
        exDate: exDate,
        paymentDate: paymentDate,
        amountPerShare: rate,
        kind: DividendKind.fromLabel(label),
        paymentDateEstimated: paymentDateEstimated,
      );

  /// Identidade para eliminar duplicatas **exatas**.
  ///
  /// Não colapsa múltiplas tranches legítimas na mesma data-ex: BBAS3 em
  /// 11/03/2025 tem dois JCP de valores diferentes mais um dividendo, e todos
  /// são reais. Só some o registro repetido idêntico, que a fonte produz
  /// ocasionalmente (ex.: PETR4 em 01/06/2026).
  String get identity =>
      '${BrapiJson.isoDay(exDate)}|${BrapiJson.isoDay(paymentDate)}|$rate|$label';
}

/// Fundamentos consolidados de um exercício, montados a partir de quatro
/// endpoints distintos que compartilham a chave `endDate`.
class BrapiFundamentalsDto {
  /// Encerramento do exercício a que os números se referem.
  final DateTime fiscalPeriodEnd;

  /// Campos crus do exercício, mesclados dos quatro endpoints da fonte.
  ///
  /// Mantidos como mapa de propósito: a fonte acrescenta e renomeia campos, e
  /// tipar cada um aqui obrigaria a alterar o DTO a cada mudança dela. A
  /// tipagem acontece na conversão para o domínio.
  final Map<String, dynamic> fields;

  /// Declara o DTO.
  const BrapiFundamentalsDto({
    required this.fiscalPeriodEnd,
    required this.fields,
  });

  double? _num(String key) => BrapiJson.asDouble(fields[key]);

  /// A fonte não entrega D&A nem alíquota efetiva; ambas são derivadas no
  /// domínio a partir de EBITDA/EBIT e imposto/lucro antes de impostos.
  FundamentalsSnapshot toDomain(Ticker ticker) => FundamentalsSnapshot(
        ticker: ticker,
        fiscalPeriodEnd: fiscalPeriodEnd,
        totalRevenue: _num('totalRevenue'),
        ebit: _num('cleanEbit') ?? _num('ebit'),
        ebitda: _num('cleanEbitda'),
        netIncome: _num('cleanNetIncome') ?? _num('netIncome'),
        incomeBeforeTax: _num('incomeBeforeTax'),
        incomeTaxExpense: _num('incomeTaxExpense'),
        interestExpense: _num('interestExpense') ?? _num('financialExpenses'),
        earningsPerShare:
            _num('earningsPerShare') ?? _num('trailingEps') ?? _num('basicEarningsPerShare'),
        cash: _num('cash'),
        shortTermInvestments: _num('shortTermInvestments'),
        shortTermDebt: _num('shortLongTermDebt') ?? _num('loansAndFinancing'),
        longTermDebt: _num('longTermDebt') ?? _num('longTermLoansAndFinancing'),
        totalStockholderEquity:
            _num('totalStockholderEquity') ?? _num('shareholdersEquity'),
        bookValuePerShare: _num('bookValue'),
        operatingCashFlow: _num('operatingCashFlow'),
        investmentCashFlow: _num('investmentCashFlow'),
        freeCashFlow: _num('freeCashFlow'),
        sharesOutstanding: _num('sharesOutstanding'),
        marketCap: _num('marketCap'),
        enterpriseToEbitda: _num('enterpriseToEbitda'),
      );
}

/// Perfil cadastral vindo de `/v2/stocks/profile`.
class BrapiProfileDto {
  /// Razão social ou nome de pregão. `null` quando a fonte não o traz.
  final String? name;

  /// Chave estável do setor, para agrupar.
  final String? sectorKey;

  /// Rótulo de exibição do setor.
  final String? sectorLabel;

  /// Subsetor. Não participa de cálculo algum.
  final String? industry;

  /// Declara o DTO.
  const BrapiProfileDto({
    this.name,
    this.sectorKey,
    this.sectorLabel,
    this.industry,
  });

  static BrapiProfileDto fromJson(Map<String, dynamic> json) =>
      BrapiProfileDto(
        name: BrapiJson.asString(json['longBusinessSummaryName']) ??
            BrapiJson.asString(json['name']),
        sectorKey: BrapiJson.asString(json['sectorKey']),
        sectorLabel: BrapiJson.asString(json['sector']) ??
            BrapiJson.asString(json['sectorDisp']),
        industry: BrapiJson.asString(json['industry']) ??
            BrapiJson.asString(json['industryDisp']),
      );

  /// A taxonomia é própria da brapi, em português — **não é GICS nem a
  /// classificação setorial oficial da B3**. Declarar na metodologia.
  Asset toDomain(Ticker ticker, {String? fallbackName}) => Asset(
        ticker: ticker,
        name: name ?? fallbackName ?? ticker.value,
        sector: sectorKey == null
            ? Sector.unknown
            : Sector.fromKey(sectorKey!, label: sectorLabel ?? sectorKey!),
        industry: industry,
      );
}
