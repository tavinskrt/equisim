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
  /// aceitável porque a fonte publica as datas ao meio-dia UTC, longe da
  /// virada.
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

  /// Fechamento ajustado também por proventos, como a fonte o publica.
  /// **Não usar em cálculo** — o domínio calcula sobre `close`.
  final double? adjustedClose;

  /// Volume negociado, em quantidade de papéis. Alimenta o corte de liquidez
  /// da Porta 0 (decisão 25).
  final double? volume;

  /// Declara o DTO.
  const BrapiPriceDto({
    required this.date,
    required this.close,
    this.adjustedClose,
    this.volume,
  });

  static BrapiPriceDto? fromJson(Map<String, dynamic> json) {
    final date = BrapiJson.asDate(json['date']);
    final close = BrapiJson.asDouble(json['close']);
    if (date == null || close == null || close <= 0) return null;
    return BrapiPriceDto(
      date: date,
      close: close,
      adjustedClose: BrapiJson.asDouble(json['adjustedClose']),
      volume: BrapiJson.asDouble(json['volume']),
    );
  }

  PricePoint toDomain() => PricePoint(
        date: date,
        close: close,
        adjustedClose: adjustedClose,
        volume: volume,
      );
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
        // A fonte publica NOPAT pronto em 16 dos 18 ativos medidos; ausente só
        // em banco, que não tem EBIT publicado e não chega à via da firma.
        nopat: _num('cleanNopat'),
        propertyPlantEquipment: _num('propertyPlantEquipment'),
        intangibleAssets: _num('intangibleAsset') ?? _num('intangibleAssets'),
        // `totalCurrentLiabilities` vem nulo na fonte; o campo preenchido é
        // `currentLiabilities`. Verificado em 16 de 16 exercícios.
        totalCurrentAssets: _num('totalCurrentAssets'),
        currentLiabilities: _num('currentLiabilities'),
        realizedShareCapital:
            _num('realizedShareCapital') ?? _num('commonStock'),
        profitReserves: _num('profitReserves'),
        sharesOutstanding: _num('sharesOutstanding'),
        sharesOutstandingAsOf: _num('sharesOutstandingAsOf'),
        marketCap: _num('marketCap'),
        enterpriseToEbitda: _num('enterpriseToEbitda'),
        // Os dois termos da ponte (decisão 49). `minorityInterest` é a
        // participação dos não controladores **dentro** do patrimônio
        // consolidado; `equityIncomeResult` é a equivalência patrimonial, que
        // na DRE brasileira entra **acima** do EBIT.
        minorityInterest: _num('minorityInterest') ??
            _num('nonControllingShareholdersEquity'),
        equityIncomeResult: _num('equityIncomeResult'),
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
