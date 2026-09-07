// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_database.dart';

// ignore_for_file: type=lint
class $CachedPricesTable extends CachedPrices
    with TableInfo<$CachedPricesTable, CachedPrice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedPricesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tickerMeta = const VerificationMeta('ticker');
  @override
  late final GeneratedColumn<String> ticker = GeneratedColumn<String>(
    'ticker',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _closeMeta = const VerificationMeta('close');
  @override
  late final GeneratedColumn<double> close = GeneratedColumn<double>(
    'close',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _adjustedCloseMeta = const VerificationMeta(
    'adjustedClose',
  );
  @override
  late final GeneratedColumn<double> adjustedClose = GeneratedColumn<double>(
    'adjusted_close',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _volumeMeta = const VerificationMeta('volume');
  @override
  late final GeneratedColumn<double> volume = GeneratedColumn<double>(
    'volume',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ticker,
    date,
    close,
    adjustedClose,
    volume,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_prices';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedPrice> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ticker')) {
      context.handle(
        _tickerMeta,
        ticker.isAcceptableOrUnknown(data['ticker']!, _tickerMeta),
      );
    } else if (isInserting) {
      context.missing(_tickerMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('close')) {
      context.handle(
        _closeMeta,
        close.isAcceptableOrUnknown(data['close']!, _closeMeta),
      );
    } else if (isInserting) {
      context.missing(_closeMeta);
    }
    if (data.containsKey('adjusted_close')) {
      context.handle(
        _adjustedCloseMeta,
        adjustedClose.isAcceptableOrUnknown(
          data['adjusted_close']!,
          _adjustedCloseMeta,
        ),
      );
    }
    if (data.containsKey('volume')) {
      context.handle(
        _volumeMeta,
        volume.isAcceptableOrUnknown(data['volume']!, _volumeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ticker, date};
  @override
  CachedPrice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedPrice(
      ticker: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ticker'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      close: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}close'],
      )!,
      adjustedClose: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}adjusted_close'],
      ),
      volume: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}volume'],
      ),
    );
  }

  @override
  $CachedPricesTable createAlias(String alias) {
    return $CachedPricesTable(attachedDatabase, alias);
  }
}

class CachedPrice extends DataClass implements Insertable<CachedPrice> {
  final String ticker;

  /// Data do pregão em `yyyy-MM-dd`, para permitir comparação lexicográfica
  /// em consultas de intervalo sem conversão.
  final String date;
  final double close;
  final double? adjustedClose;

  /// Volume negociado no pregão, em quantidade de papéis.
  ///
  /// Entra com a decisão 25: a Porta 0 filtra por volume financeiro médio, e
  /// sem ele o corte de liquidez não é computável. Nulo em série cacheada antes
  /// da versão 3 do esquema.
  final double? volume;
  const CachedPrice({
    required this.ticker,
    required this.date,
    required this.close,
    this.adjustedClose,
    this.volume,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ticker'] = Variable<String>(ticker);
    map['date'] = Variable<String>(date);
    map['close'] = Variable<double>(close);
    if (!nullToAbsent || adjustedClose != null) {
      map['adjusted_close'] = Variable<double>(adjustedClose);
    }
    if (!nullToAbsent || volume != null) {
      map['volume'] = Variable<double>(volume);
    }
    return map;
  }

  CachedPricesCompanion toCompanion(bool nullToAbsent) {
    return CachedPricesCompanion(
      ticker: Value(ticker),
      date: Value(date),
      close: Value(close),
      adjustedClose: adjustedClose == null && nullToAbsent
          ? const Value.absent()
          : Value(adjustedClose),
      volume: volume == null && nullToAbsent
          ? const Value.absent()
          : Value(volume),
    );
  }

  factory CachedPrice.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedPrice(
      ticker: serializer.fromJson<String>(json['ticker']),
      date: serializer.fromJson<String>(json['date']),
      close: serializer.fromJson<double>(json['close']),
      adjustedClose: serializer.fromJson<double?>(json['adjustedClose']),
      volume: serializer.fromJson<double?>(json['volume']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ticker': serializer.toJson<String>(ticker),
      'date': serializer.toJson<String>(date),
      'close': serializer.toJson<double>(close),
      'adjustedClose': serializer.toJson<double?>(adjustedClose),
      'volume': serializer.toJson<double?>(volume),
    };
  }

  CachedPrice copyWith({
    String? ticker,
    String? date,
    double? close,
    Value<double?> adjustedClose = const Value.absent(),
    Value<double?> volume = const Value.absent(),
  }) => CachedPrice(
    ticker: ticker ?? this.ticker,
    date: date ?? this.date,
    close: close ?? this.close,
    adjustedClose: adjustedClose.present
        ? adjustedClose.value
        : this.adjustedClose,
    volume: volume.present ? volume.value : this.volume,
  );
  CachedPrice copyWithCompanion(CachedPricesCompanion data) {
    return CachedPrice(
      ticker: data.ticker.present ? data.ticker.value : this.ticker,
      date: data.date.present ? data.date.value : this.date,
      close: data.close.present ? data.close.value : this.close,
      adjustedClose: data.adjustedClose.present
          ? data.adjustedClose.value
          : this.adjustedClose,
      volume: data.volume.present ? data.volume.value : this.volume,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedPrice(')
          ..write('ticker: $ticker, ')
          ..write('date: $date, ')
          ..write('close: $close, ')
          ..write('adjustedClose: $adjustedClose, ')
          ..write('volume: $volume')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ticker, date, close, adjustedClose, volume);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedPrice &&
          other.ticker == this.ticker &&
          other.date == this.date &&
          other.close == this.close &&
          other.adjustedClose == this.adjustedClose &&
          other.volume == this.volume);
}

class CachedPricesCompanion extends UpdateCompanion<CachedPrice> {
  final Value<String> ticker;
  final Value<String> date;
  final Value<double> close;
  final Value<double?> adjustedClose;
  final Value<double?> volume;
  final Value<int> rowid;
  const CachedPricesCompanion({
    this.ticker = const Value.absent(),
    this.date = const Value.absent(),
    this.close = const Value.absent(),
    this.adjustedClose = const Value.absent(),
    this.volume = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedPricesCompanion.insert({
    required String ticker,
    required String date,
    required double close,
    this.adjustedClose = const Value.absent(),
    this.volume = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ticker = Value(ticker),
       date = Value(date),
       close = Value(close);
  static Insertable<CachedPrice> custom({
    Expression<String>? ticker,
    Expression<String>? date,
    Expression<double>? close,
    Expression<double>? adjustedClose,
    Expression<double>? volume,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ticker != null) 'ticker': ticker,
      if (date != null) 'date': date,
      if (close != null) 'close': close,
      if (adjustedClose != null) 'adjusted_close': adjustedClose,
      if (volume != null) 'volume': volume,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedPricesCompanion copyWith({
    Value<String>? ticker,
    Value<String>? date,
    Value<double>? close,
    Value<double?>? adjustedClose,
    Value<double?>? volume,
    Value<int>? rowid,
  }) {
    return CachedPricesCompanion(
      ticker: ticker ?? this.ticker,
      date: date ?? this.date,
      close: close ?? this.close,
      adjustedClose: adjustedClose ?? this.adjustedClose,
      volume: volume ?? this.volume,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ticker.present) {
      map['ticker'] = Variable<String>(ticker.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (close.present) {
      map['close'] = Variable<double>(close.value);
    }
    if (adjustedClose.present) {
      map['adjusted_close'] = Variable<double>(adjustedClose.value);
    }
    if (volume.present) {
      map['volume'] = Variable<double>(volume.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedPricesCompanion(')
          ..write('ticker: $ticker, ')
          ..write('date: $date, ')
          ..write('close: $close, ')
          ..write('adjustedClose: $adjustedClose, ')
          ..write('volume: $volume, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedFundamentalsTableTable extends CachedFundamentalsTable
    with TableInfo<$CachedFundamentalsTableTable, CachedFundamentals> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedFundamentalsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tickerMeta = const VerificationMeta('ticker');
  @override
  late final GeneratedColumn<String> ticker = GeneratedColumn<String>(
    'ticker',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fiscalPeriodEndMeta = const VerificationMeta(
    'fiscalPeriodEnd',
  );
  @override
  late final GeneratedColumn<String> fiscalPeriodEnd = GeneratedColumn<String>(
    'fiscal_period_end',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalRevenueMeta = const VerificationMeta(
    'totalRevenue',
  );
  @override
  late final GeneratedColumn<double> totalRevenue = GeneratedColumn<double>(
    'total_revenue',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ebitMeta = const VerificationMeta('ebit');
  @override
  late final GeneratedColumn<double> ebit = GeneratedColumn<double>(
    'ebit',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ebitdaMeta = const VerificationMeta('ebitda');
  @override
  late final GeneratedColumn<double> ebitda = GeneratedColumn<double>(
    'ebitda',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _netIncomeMeta = const VerificationMeta(
    'netIncome',
  );
  @override
  late final GeneratedColumn<double> netIncome = GeneratedColumn<double>(
    'net_income',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _incomeBeforeTaxMeta = const VerificationMeta(
    'incomeBeforeTax',
  );
  @override
  late final GeneratedColumn<double> incomeBeforeTax = GeneratedColumn<double>(
    'income_before_tax',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _incomeTaxExpenseMeta = const VerificationMeta(
    'incomeTaxExpense',
  );
  @override
  late final GeneratedColumn<double> incomeTaxExpense = GeneratedColumn<double>(
    'income_tax_expense',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _interestExpenseMeta = const VerificationMeta(
    'interestExpense',
  );
  @override
  late final GeneratedColumn<double> interestExpense = GeneratedColumn<double>(
    'interest_expense',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _earningsPerShareMeta = const VerificationMeta(
    'earningsPerShare',
  );
  @override
  late final GeneratedColumn<double> earningsPerShare = GeneratedColumn<double>(
    'earnings_per_share',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cashMeta = const VerificationMeta('cash');
  @override
  late final GeneratedColumn<double> cash = GeneratedColumn<double>(
    'cash',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _shortTermInvestmentsMeta =
      const VerificationMeta('shortTermInvestments');
  @override
  late final GeneratedColumn<double> shortTermInvestments =
      GeneratedColumn<double>(
        'short_term_investments',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _shortTermDebtMeta = const VerificationMeta(
    'shortTermDebt',
  );
  @override
  late final GeneratedColumn<double> shortTermDebt = GeneratedColumn<double>(
    'short_term_debt',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longTermDebtMeta = const VerificationMeta(
    'longTermDebt',
  );
  @override
  late final GeneratedColumn<double> longTermDebt = GeneratedColumn<double>(
    'long_term_debt',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalStockholderEquityMeta =
      const VerificationMeta('totalStockholderEquity');
  @override
  late final GeneratedColumn<double> totalStockholderEquity =
      GeneratedColumn<double>(
        'total_stockholder_equity',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _bookValuePerShareMeta = const VerificationMeta(
    'bookValuePerShare',
  );
  @override
  late final GeneratedColumn<double> bookValuePerShare =
      GeneratedColumn<double>(
        'book_value_per_share',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _operatingCashFlowMeta = const VerificationMeta(
    'operatingCashFlow',
  );
  @override
  late final GeneratedColumn<double> operatingCashFlow =
      GeneratedColumn<double>(
        'operating_cash_flow',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _investmentCashFlowMeta =
      const VerificationMeta('investmentCashFlow');
  @override
  late final GeneratedColumn<double> investmentCashFlow =
      GeneratedColumn<double>(
        'investment_cash_flow',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _freeCashFlowMeta = const VerificationMeta(
    'freeCashFlow',
  );
  @override
  late final GeneratedColumn<double> freeCashFlow = GeneratedColumn<double>(
    'free_cash_flow',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sharesOutstandingMeta = const VerificationMeta(
    'sharesOutstanding',
  );
  @override
  late final GeneratedColumn<double> sharesOutstanding =
      GeneratedColumn<double>(
        'shares_outstanding',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _sharesOutstandingAsOfMeta =
      const VerificationMeta('sharesOutstandingAsOf');
  @override
  late final GeneratedColumn<double> sharesOutstandingAsOf =
      GeneratedColumn<double>(
        'shares_outstanding_as_of',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _marketCapMeta = const VerificationMeta(
    'marketCap',
  );
  @override
  late final GeneratedColumn<double> marketCap = GeneratedColumn<double>(
    'market_cap',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enterpriseToEbitdaMeta =
      const VerificationMeta('enterpriseToEbitda');
  @override
  late final GeneratedColumn<double> enterpriseToEbitda =
      GeneratedColumn<double>(
        'enterprise_to_ebitda',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _nopatMeta = const VerificationMeta('nopat');
  @override
  late final GeneratedColumn<double> nopat = GeneratedColumn<double>(
    'nopat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _propertyPlantEquipmentMeta =
      const VerificationMeta('propertyPlantEquipment');
  @override
  late final GeneratedColumn<double> propertyPlantEquipment =
      GeneratedColumn<double>(
        'property_plant_equipment',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _intangibleAssetsMeta = const VerificationMeta(
    'intangibleAssets',
  );
  @override
  late final GeneratedColumn<double> intangibleAssets = GeneratedColumn<double>(
    'intangible_assets',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalCurrentAssetsMeta =
      const VerificationMeta('totalCurrentAssets');
  @override
  late final GeneratedColumn<double> totalCurrentAssets =
      GeneratedColumn<double>(
        'total_current_assets',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _currentLiabilitiesMeta =
      const VerificationMeta('currentLiabilities');
  @override
  late final GeneratedColumn<double> currentLiabilities =
      GeneratedColumn<double>(
        'current_liabilities',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _realizedShareCapitalMeta =
      const VerificationMeta('realizedShareCapital');
  @override
  late final GeneratedColumn<double> realizedShareCapital =
      GeneratedColumn<double>(
        'realized_share_capital',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _profitReservesMeta = const VerificationMeta(
    'profitReserves',
  );
  @override
  late final GeneratedColumn<double> profitReserves = GeneratedColumn<double>(
    'profit_reserves',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ticker,
    fiscalPeriodEnd,
    totalRevenue,
    ebit,
    ebitda,
    netIncome,
    incomeBeforeTax,
    incomeTaxExpense,
    interestExpense,
    earningsPerShare,
    cash,
    shortTermInvestments,
    shortTermDebt,
    longTermDebt,
    totalStockholderEquity,
    bookValuePerShare,
    operatingCashFlow,
    investmentCashFlow,
    freeCashFlow,
    sharesOutstanding,
    sharesOutstandingAsOf,
    marketCap,
    enterpriseToEbitda,
    nopat,
    propertyPlantEquipment,
    intangibleAssets,
    totalCurrentAssets,
    currentLiabilities,
    realizedShareCapital,
    profitReserves,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_fundamentals_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedFundamentals> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ticker')) {
      context.handle(
        _tickerMeta,
        ticker.isAcceptableOrUnknown(data['ticker']!, _tickerMeta),
      );
    } else if (isInserting) {
      context.missing(_tickerMeta);
    }
    if (data.containsKey('fiscal_period_end')) {
      context.handle(
        _fiscalPeriodEndMeta,
        fiscalPeriodEnd.isAcceptableOrUnknown(
          data['fiscal_period_end']!,
          _fiscalPeriodEndMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fiscalPeriodEndMeta);
    }
    if (data.containsKey('total_revenue')) {
      context.handle(
        _totalRevenueMeta,
        totalRevenue.isAcceptableOrUnknown(
          data['total_revenue']!,
          _totalRevenueMeta,
        ),
      );
    }
    if (data.containsKey('ebit')) {
      context.handle(
        _ebitMeta,
        ebit.isAcceptableOrUnknown(data['ebit']!, _ebitMeta),
      );
    }
    if (data.containsKey('ebitda')) {
      context.handle(
        _ebitdaMeta,
        ebitda.isAcceptableOrUnknown(data['ebitda']!, _ebitdaMeta),
      );
    }
    if (data.containsKey('net_income')) {
      context.handle(
        _netIncomeMeta,
        netIncome.isAcceptableOrUnknown(data['net_income']!, _netIncomeMeta),
      );
    }
    if (data.containsKey('income_before_tax')) {
      context.handle(
        _incomeBeforeTaxMeta,
        incomeBeforeTax.isAcceptableOrUnknown(
          data['income_before_tax']!,
          _incomeBeforeTaxMeta,
        ),
      );
    }
    if (data.containsKey('income_tax_expense')) {
      context.handle(
        _incomeTaxExpenseMeta,
        incomeTaxExpense.isAcceptableOrUnknown(
          data['income_tax_expense']!,
          _incomeTaxExpenseMeta,
        ),
      );
    }
    if (data.containsKey('interest_expense')) {
      context.handle(
        _interestExpenseMeta,
        interestExpense.isAcceptableOrUnknown(
          data['interest_expense']!,
          _interestExpenseMeta,
        ),
      );
    }
    if (data.containsKey('earnings_per_share')) {
      context.handle(
        _earningsPerShareMeta,
        earningsPerShare.isAcceptableOrUnknown(
          data['earnings_per_share']!,
          _earningsPerShareMeta,
        ),
      );
    }
    if (data.containsKey('cash')) {
      context.handle(
        _cashMeta,
        cash.isAcceptableOrUnknown(data['cash']!, _cashMeta),
      );
    }
    if (data.containsKey('short_term_investments')) {
      context.handle(
        _shortTermInvestmentsMeta,
        shortTermInvestments.isAcceptableOrUnknown(
          data['short_term_investments']!,
          _shortTermInvestmentsMeta,
        ),
      );
    }
    if (data.containsKey('short_term_debt')) {
      context.handle(
        _shortTermDebtMeta,
        shortTermDebt.isAcceptableOrUnknown(
          data['short_term_debt']!,
          _shortTermDebtMeta,
        ),
      );
    }
    if (data.containsKey('long_term_debt')) {
      context.handle(
        _longTermDebtMeta,
        longTermDebt.isAcceptableOrUnknown(
          data['long_term_debt']!,
          _longTermDebtMeta,
        ),
      );
    }
    if (data.containsKey('total_stockholder_equity')) {
      context.handle(
        _totalStockholderEquityMeta,
        totalStockholderEquity.isAcceptableOrUnknown(
          data['total_stockholder_equity']!,
          _totalStockholderEquityMeta,
        ),
      );
    }
    if (data.containsKey('book_value_per_share')) {
      context.handle(
        _bookValuePerShareMeta,
        bookValuePerShare.isAcceptableOrUnknown(
          data['book_value_per_share']!,
          _bookValuePerShareMeta,
        ),
      );
    }
    if (data.containsKey('operating_cash_flow')) {
      context.handle(
        _operatingCashFlowMeta,
        operatingCashFlow.isAcceptableOrUnknown(
          data['operating_cash_flow']!,
          _operatingCashFlowMeta,
        ),
      );
    }
    if (data.containsKey('investment_cash_flow')) {
      context.handle(
        _investmentCashFlowMeta,
        investmentCashFlow.isAcceptableOrUnknown(
          data['investment_cash_flow']!,
          _investmentCashFlowMeta,
        ),
      );
    }
    if (data.containsKey('free_cash_flow')) {
      context.handle(
        _freeCashFlowMeta,
        freeCashFlow.isAcceptableOrUnknown(
          data['free_cash_flow']!,
          _freeCashFlowMeta,
        ),
      );
    }
    if (data.containsKey('shares_outstanding')) {
      context.handle(
        _sharesOutstandingMeta,
        sharesOutstanding.isAcceptableOrUnknown(
          data['shares_outstanding']!,
          _sharesOutstandingMeta,
        ),
      );
    }
    if (data.containsKey('shares_outstanding_as_of')) {
      context.handle(
        _sharesOutstandingAsOfMeta,
        sharesOutstandingAsOf.isAcceptableOrUnknown(
          data['shares_outstanding_as_of']!,
          _sharesOutstandingAsOfMeta,
        ),
      );
    }
    if (data.containsKey('market_cap')) {
      context.handle(
        _marketCapMeta,
        marketCap.isAcceptableOrUnknown(data['market_cap']!, _marketCapMeta),
      );
    }
    if (data.containsKey('enterprise_to_ebitda')) {
      context.handle(
        _enterpriseToEbitdaMeta,
        enterpriseToEbitda.isAcceptableOrUnknown(
          data['enterprise_to_ebitda']!,
          _enterpriseToEbitdaMeta,
        ),
      );
    }
    if (data.containsKey('nopat')) {
      context.handle(
        _nopatMeta,
        nopat.isAcceptableOrUnknown(data['nopat']!, _nopatMeta),
      );
    }
    if (data.containsKey('property_plant_equipment')) {
      context.handle(
        _propertyPlantEquipmentMeta,
        propertyPlantEquipment.isAcceptableOrUnknown(
          data['property_plant_equipment']!,
          _propertyPlantEquipmentMeta,
        ),
      );
    }
    if (data.containsKey('intangible_assets')) {
      context.handle(
        _intangibleAssetsMeta,
        intangibleAssets.isAcceptableOrUnknown(
          data['intangible_assets']!,
          _intangibleAssetsMeta,
        ),
      );
    }
    if (data.containsKey('total_current_assets')) {
      context.handle(
        _totalCurrentAssetsMeta,
        totalCurrentAssets.isAcceptableOrUnknown(
          data['total_current_assets']!,
          _totalCurrentAssetsMeta,
        ),
      );
    }
    if (data.containsKey('current_liabilities')) {
      context.handle(
        _currentLiabilitiesMeta,
        currentLiabilities.isAcceptableOrUnknown(
          data['current_liabilities']!,
          _currentLiabilitiesMeta,
        ),
      );
    }
    if (data.containsKey('realized_share_capital')) {
      context.handle(
        _realizedShareCapitalMeta,
        realizedShareCapital.isAcceptableOrUnknown(
          data['realized_share_capital']!,
          _realizedShareCapitalMeta,
        ),
      );
    }
    if (data.containsKey('profit_reserves')) {
      context.handle(
        _profitReservesMeta,
        profitReserves.isAcceptableOrUnknown(
          data['profit_reserves']!,
          _profitReservesMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ticker, fiscalPeriodEnd};
  @override
  CachedFundamentals map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedFundamentals(
      ticker: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ticker'],
      )!,
      fiscalPeriodEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fiscal_period_end'],
      )!,
      totalRevenue: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_revenue'],
      ),
      ebit: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}ebit'],
      ),
      ebitda: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}ebitda'],
      ),
      netIncome: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}net_income'],
      ),
      incomeBeforeTax: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}income_before_tax'],
      ),
      incomeTaxExpense: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}income_tax_expense'],
      ),
      interestExpense: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}interest_expense'],
      ),
      earningsPerShare: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}earnings_per_share'],
      ),
      cash: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cash'],
      ),
      shortTermInvestments: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}short_term_investments'],
      ),
      shortTermDebt: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}short_term_debt'],
      ),
      longTermDebt: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}long_term_debt'],
      ),
      totalStockholderEquity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_stockholder_equity'],
      ),
      bookValuePerShare: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}book_value_per_share'],
      ),
      operatingCashFlow: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}operating_cash_flow'],
      ),
      investmentCashFlow: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}investment_cash_flow'],
      ),
      freeCashFlow: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}free_cash_flow'],
      ),
      sharesOutstanding: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}shares_outstanding'],
      ),
      sharesOutstandingAsOf: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}shares_outstanding_as_of'],
      ),
      marketCap: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}market_cap'],
      ),
      enterpriseToEbitda: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}enterprise_to_ebitda'],
      ),
      nopat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}nopat'],
      ),
      propertyPlantEquipment: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}property_plant_equipment'],
      ),
      intangibleAssets: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}intangible_assets'],
      ),
      totalCurrentAssets: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_current_assets'],
      ),
      currentLiabilities: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}current_liabilities'],
      ),
      realizedShareCapital: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}realized_share_capital'],
      ),
      profitReserves: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}profit_reserves'],
      ),
    );
  }

  @override
  $CachedFundamentalsTableTable createAlias(String alias) {
    return $CachedFundamentalsTableTable(attachedDatabase, alias);
  }
}

class CachedFundamentals extends DataClass
    implements Insertable<CachedFundamentals> {
  final String ticker;
  final String fiscalPeriodEnd;
  final double? totalRevenue;
  final double? ebit;
  final double? ebitda;
  final double? netIncome;
  final double? incomeBeforeTax;
  final double? incomeTaxExpense;
  final double? interestExpense;
  final double? earningsPerShare;
  final double? cash;
  final double? shortTermInvestments;
  final double? shortTermDebt;
  final double? longTermDebt;
  final double? totalStockholderEquity;
  final double? bookValuePerShare;
  final double? operatingCashFlow;
  final double? investmentCashFlow;
  final double? freeCashFlow;
  final double? sharesOutstanding;

  /// Contagem de ações **do exercício**, antes da sobrescrita pela corrente.
  /// Sem ela não há patrimônio nem capital investido reconstituíveis.
  final double? sharesOutstandingAsOf;
  final double? marketCap;
  final double? enterpriseToEbitda;
  final double? nopat;
  final double? propertyPlantEquipment;
  final double? intangibleAssets;
  final double? totalCurrentAssets;
  final double? currentLiabilities;
  final double? realizedShareCapital;
  final double? profitReserves;
  const CachedFundamentals({
    required this.ticker,
    required this.fiscalPeriodEnd,
    this.totalRevenue,
    this.ebit,
    this.ebitda,
    this.netIncome,
    this.incomeBeforeTax,
    this.incomeTaxExpense,
    this.interestExpense,
    this.earningsPerShare,
    this.cash,
    this.shortTermInvestments,
    this.shortTermDebt,
    this.longTermDebt,
    this.totalStockholderEquity,
    this.bookValuePerShare,
    this.operatingCashFlow,
    this.investmentCashFlow,
    this.freeCashFlow,
    this.sharesOutstanding,
    this.sharesOutstandingAsOf,
    this.marketCap,
    this.enterpriseToEbitda,
    this.nopat,
    this.propertyPlantEquipment,
    this.intangibleAssets,
    this.totalCurrentAssets,
    this.currentLiabilities,
    this.realizedShareCapital,
    this.profitReserves,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ticker'] = Variable<String>(ticker);
    map['fiscal_period_end'] = Variable<String>(fiscalPeriodEnd);
    if (!nullToAbsent || totalRevenue != null) {
      map['total_revenue'] = Variable<double>(totalRevenue);
    }
    if (!nullToAbsent || ebit != null) {
      map['ebit'] = Variable<double>(ebit);
    }
    if (!nullToAbsent || ebitda != null) {
      map['ebitda'] = Variable<double>(ebitda);
    }
    if (!nullToAbsent || netIncome != null) {
      map['net_income'] = Variable<double>(netIncome);
    }
    if (!nullToAbsent || incomeBeforeTax != null) {
      map['income_before_tax'] = Variable<double>(incomeBeforeTax);
    }
    if (!nullToAbsent || incomeTaxExpense != null) {
      map['income_tax_expense'] = Variable<double>(incomeTaxExpense);
    }
    if (!nullToAbsent || interestExpense != null) {
      map['interest_expense'] = Variable<double>(interestExpense);
    }
    if (!nullToAbsent || earningsPerShare != null) {
      map['earnings_per_share'] = Variable<double>(earningsPerShare);
    }
    if (!nullToAbsent || cash != null) {
      map['cash'] = Variable<double>(cash);
    }
    if (!nullToAbsent || shortTermInvestments != null) {
      map['short_term_investments'] = Variable<double>(shortTermInvestments);
    }
    if (!nullToAbsent || shortTermDebt != null) {
      map['short_term_debt'] = Variable<double>(shortTermDebt);
    }
    if (!nullToAbsent || longTermDebt != null) {
      map['long_term_debt'] = Variable<double>(longTermDebt);
    }
    if (!nullToAbsent || totalStockholderEquity != null) {
      map['total_stockholder_equity'] = Variable<double>(
        totalStockholderEquity,
      );
    }
    if (!nullToAbsent || bookValuePerShare != null) {
      map['book_value_per_share'] = Variable<double>(bookValuePerShare);
    }
    if (!nullToAbsent || operatingCashFlow != null) {
      map['operating_cash_flow'] = Variable<double>(operatingCashFlow);
    }
    if (!nullToAbsent || investmentCashFlow != null) {
      map['investment_cash_flow'] = Variable<double>(investmentCashFlow);
    }
    if (!nullToAbsent || freeCashFlow != null) {
      map['free_cash_flow'] = Variable<double>(freeCashFlow);
    }
    if (!nullToAbsent || sharesOutstanding != null) {
      map['shares_outstanding'] = Variable<double>(sharesOutstanding);
    }
    if (!nullToAbsent || sharesOutstandingAsOf != null) {
      map['shares_outstanding_as_of'] = Variable<double>(sharesOutstandingAsOf);
    }
    if (!nullToAbsent || marketCap != null) {
      map['market_cap'] = Variable<double>(marketCap);
    }
    if (!nullToAbsent || enterpriseToEbitda != null) {
      map['enterprise_to_ebitda'] = Variable<double>(enterpriseToEbitda);
    }
    if (!nullToAbsent || nopat != null) {
      map['nopat'] = Variable<double>(nopat);
    }
    if (!nullToAbsent || propertyPlantEquipment != null) {
      map['property_plant_equipment'] = Variable<double>(
        propertyPlantEquipment,
      );
    }
    if (!nullToAbsent || intangibleAssets != null) {
      map['intangible_assets'] = Variable<double>(intangibleAssets);
    }
    if (!nullToAbsent || totalCurrentAssets != null) {
      map['total_current_assets'] = Variable<double>(totalCurrentAssets);
    }
    if (!nullToAbsent || currentLiabilities != null) {
      map['current_liabilities'] = Variable<double>(currentLiabilities);
    }
    if (!nullToAbsent || realizedShareCapital != null) {
      map['realized_share_capital'] = Variable<double>(realizedShareCapital);
    }
    if (!nullToAbsent || profitReserves != null) {
      map['profit_reserves'] = Variable<double>(profitReserves);
    }
    return map;
  }

  CachedFundamentalsTableCompanion toCompanion(bool nullToAbsent) {
    return CachedFundamentalsTableCompanion(
      ticker: Value(ticker),
      fiscalPeriodEnd: Value(fiscalPeriodEnd),
      totalRevenue: totalRevenue == null && nullToAbsent
          ? const Value.absent()
          : Value(totalRevenue),
      ebit: ebit == null && nullToAbsent ? const Value.absent() : Value(ebit),
      ebitda: ebitda == null && nullToAbsent
          ? const Value.absent()
          : Value(ebitda),
      netIncome: netIncome == null && nullToAbsent
          ? const Value.absent()
          : Value(netIncome),
      incomeBeforeTax: incomeBeforeTax == null && nullToAbsent
          ? const Value.absent()
          : Value(incomeBeforeTax),
      incomeTaxExpense: incomeTaxExpense == null && nullToAbsent
          ? const Value.absent()
          : Value(incomeTaxExpense),
      interestExpense: interestExpense == null && nullToAbsent
          ? const Value.absent()
          : Value(interestExpense),
      earningsPerShare: earningsPerShare == null && nullToAbsent
          ? const Value.absent()
          : Value(earningsPerShare),
      cash: cash == null && nullToAbsent ? const Value.absent() : Value(cash),
      shortTermInvestments: shortTermInvestments == null && nullToAbsent
          ? const Value.absent()
          : Value(shortTermInvestments),
      shortTermDebt: shortTermDebt == null && nullToAbsent
          ? const Value.absent()
          : Value(shortTermDebt),
      longTermDebt: longTermDebt == null && nullToAbsent
          ? const Value.absent()
          : Value(longTermDebt),
      totalStockholderEquity: totalStockholderEquity == null && nullToAbsent
          ? const Value.absent()
          : Value(totalStockholderEquity),
      bookValuePerShare: bookValuePerShare == null && nullToAbsent
          ? const Value.absent()
          : Value(bookValuePerShare),
      operatingCashFlow: operatingCashFlow == null && nullToAbsent
          ? const Value.absent()
          : Value(operatingCashFlow),
      investmentCashFlow: investmentCashFlow == null && nullToAbsent
          ? const Value.absent()
          : Value(investmentCashFlow),
      freeCashFlow: freeCashFlow == null && nullToAbsent
          ? const Value.absent()
          : Value(freeCashFlow),
      sharesOutstanding: sharesOutstanding == null && nullToAbsent
          ? const Value.absent()
          : Value(sharesOutstanding),
      sharesOutstandingAsOf: sharesOutstandingAsOf == null && nullToAbsent
          ? const Value.absent()
          : Value(sharesOutstandingAsOf),
      marketCap: marketCap == null && nullToAbsent
          ? const Value.absent()
          : Value(marketCap),
      enterpriseToEbitda: enterpriseToEbitda == null && nullToAbsent
          ? const Value.absent()
          : Value(enterpriseToEbitda),
      nopat: nopat == null && nullToAbsent
          ? const Value.absent()
          : Value(nopat),
      propertyPlantEquipment: propertyPlantEquipment == null && nullToAbsent
          ? const Value.absent()
          : Value(propertyPlantEquipment),
      intangibleAssets: intangibleAssets == null && nullToAbsent
          ? const Value.absent()
          : Value(intangibleAssets),
      totalCurrentAssets: totalCurrentAssets == null && nullToAbsent
          ? const Value.absent()
          : Value(totalCurrentAssets),
      currentLiabilities: currentLiabilities == null && nullToAbsent
          ? const Value.absent()
          : Value(currentLiabilities),
      realizedShareCapital: realizedShareCapital == null && nullToAbsent
          ? const Value.absent()
          : Value(realizedShareCapital),
      profitReserves: profitReserves == null && nullToAbsent
          ? const Value.absent()
          : Value(profitReserves),
    );
  }

  factory CachedFundamentals.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedFundamentals(
      ticker: serializer.fromJson<String>(json['ticker']),
      fiscalPeriodEnd: serializer.fromJson<String>(json['fiscalPeriodEnd']),
      totalRevenue: serializer.fromJson<double?>(json['totalRevenue']),
      ebit: serializer.fromJson<double?>(json['ebit']),
      ebitda: serializer.fromJson<double?>(json['ebitda']),
      netIncome: serializer.fromJson<double?>(json['netIncome']),
      incomeBeforeTax: serializer.fromJson<double?>(json['incomeBeforeTax']),
      incomeTaxExpense: serializer.fromJson<double?>(json['incomeTaxExpense']),
      interestExpense: serializer.fromJson<double?>(json['interestExpense']),
      earningsPerShare: serializer.fromJson<double?>(json['earningsPerShare']),
      cash: serializer.fromJson<double?>(json['cash']),
      shortTermInvestments: serializer.fromJson<double?>(
        json['shortTermInvestments'],
      ),
      shortTermDebt: serializer.fromJson<double?>(json['shortTermDebt']),
      longTermDebt: serializer.fromJson<double?>(json['longTermDebt']),
      totalStockholderEquity: serializer.fromJson<double?>(
        json['totalStockholderEquity'],
      ),
      bookValuePerShare: serializer.fromJson<double?>(
        json['bookValuePerShare'],
      ),
      operatingCashFlow: serializer.fromJson<double?>(
        json['operatingCashFlow'],
      ),
      investmentCashFlow: serializer.fromJson<double?>(
        json['investmentCashFlow'],
      ),
      freeCashFlow: serializer.fromJson<double?>(json['freeCashFlow']),
      sharesOutstanding: serializer.fromJson<double?>(
        json['sharesOutstanding'],
      ),
      sharesOutstandingAsOf: serializer.fromJson<double?>(
        json['sharesOutstandingAsOf'],
      ),
      marketCap: serializer.fromJson<double?>(json['marketCap']),
      enterpriseToEbitda: serializer.fromJson<double?>(
        json['enterpriseToEbitda'],
      ),
      nopat: serializer.fromJson<double?>(json['nopat']),
      propertyPlantEquipment: serializer.fromJson<double?>(
        json['propertyPlantEquipment'],
      ),
      intangibleAssets: serializer.fromJson<double?>(json['intangibleAssets']),
      totalCurrentAssets: serializer.fromJson<double?>(
        json['totalCurrentAssets'],
      ),
      currentLiabilities: serializer.fromJson<double?>(
        json['currentLiabilities'],
      ),
      realizedShareCapital: serializer.fromJson<double?>(
        json['realizedShareCapital'],
      ),
      profitReserves: serializer.fromJson<double?>(json['profitReserves']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ticker': serializer.toJson<String>(ticker),
      'fiscalPeriodEnd': serializer.toJson<String>(fiscalPeriodEnd),
      'totalRevenue': serializer.toJson<double?>(totalRevenue),
      'ebit': serializer.toJson<double?>(ebit),
      'ebitda': serializer.toJson<double?>(ebitda),
      'netIncome': serializer.toJson<double?>(netIncome),
      'incomeBeforeTax': serializer.toJson<double?>(incomeBeforeTax),
      'incomeTaxExpense': serializer.toJson<double?>(incomeTaxExpense),
      'interestExpense': serializer.toJson<double?>(interestExpense),
      'earningsPerShare': serializer.toJson<double?>(earningsPerShare),
      'cash': serializer.toJson<double?>(cash),
      'shortTermInvestments': serializer.toJson<double?>(shortTermInvestments),
      'shortTermDebt': serializer.toJson<double?>(shortTermDebt),
      'longTermDebt': serializer.toJson<double?>(longTermDebt),
      'totalStockholderEquity': serializer.toJson<double?>(
        totalStockholderEquity,
      ),
      'bookValuePerShare': serializer.toJson<double?>(bookValuePerShare),
      'operatingCashFlow': serializer.toJson<double?>(operatingCashFlow),
      'investmentCashFlow': serializer.toJson<double?>(investmentCashFlow),
      'freeCashFlow': serializer.toJson<double?>(freeCashFlow),
      'sharesOutstanding': serializer.toJson<double?>(sharesOutstanding),
      'sharesOutstandingAsOf': serializer.toJson<double?>(
        sharesOutstandingAsOf,
      ),
      'marketCap': serializer.toJson<double?>(marketCap),
      'enterpriseToEbitda': serializer.toJson<double?>(enterpriseToEbitda),
      'nopat': serializer.toJson<double?>(nopat),
      'propertyPlantEquipment': serializer.toJson<double?>(
        propertyPlantEquipment,
      ),
      'intangibleAssets': serializer.toJson<double?>(intangibleAssets),
      'totalCurrentAssets': serializer.toJson<double?>(totalCurrentAssets),
      'currentLiabilities': serializer.toJson<double?>(currentLiabilities),
      'realizedShareCapital': serializer.toJson<double?>(realizedShareCapital),
      'profitReserves': serializer.toJson<double?>(profitReserves),
    };
  }

  CachedFundamentals copyWith({
    String? ticker,
    String? fiscalPeriodEnd,
    Value<double?> totalRevenue = const Value.absent(),
    Value<double?> ebit = const Value.absent(),
    Value<double?> ebitda = const Value.absent(),
    Value<double?> netIncome = const Value.absent(),
    Value<double?> incomeBeforeTax = const Value.absent(),
    Value<double?> incomeTaxExpense = const Value.absent(),
    Value<double?> interestExpense = const Value.absent(),
    Value<double?> earningsPerShare = const Value.absent(),
    Value<double?> cash = const Value.absent(),
    Value<double?> shortTermInvestments = const Value.absent(),
    Value<double?> shortTermDebt = const Value.absent(),
    Value<double?> longTermDebt = const Value.absent(),
    Value<double?> totalStockholderEquity = const Value.absent(),
    Value<double?> bookValuePerShare = const Value.absent(),
    Value<double?> operatingCashFlow = const Value.absent(),
    Value<double?> investmentCashFlow = const Value.absent(),
    Value<double?> freeCashFlow = const Value.absent(),
    Value<double?> sharesOutstanding = const Value.absent(),
    Value<double?> sharesOutstandingAsOf = const Value.absent(),
    Value<double?> marketCap = const Value.absent(),
    Value<double?> enterpriseToEbitda = const Value.absent(),
    Value<double?> nopat = const Value.absent(),
    Value<double?> propertyPlantEquipment = const Value.absent(),
    Value<double?> intangibleAssets = const Value.absent(),
    Value<double?> totalCurrentAssets = const Value.absent(),
    Value<double?> currentLiabilities = const Value.absent(),
    Value<double?> realizedShareCapital = const Value.absent(),
    Value<double?> profitReserves = const Value.absent(),
  }) => CachedFundamentals(
    ticker: ticker ?? this.ticker,
    fiscalPeriodEnd: fiscalPeriodEnd ?? this.fiscalPeriodEnd,
    totalRevenue: totalRevenue.present ? totalRevenue.value : this.totalRevenue,
    ebit: ebit.present ? ebit.value : this.ebit,
    ebitda: ebitda.present ? ebitda.value : this.ebitda,
    netIncome: netIncome.present ? netIncome.value : this.netIncome,
    incomeBeforeTax: incomeBeforeTax.present
        ? incomeBeforeTax.value
        : this.incomeBeforeTax,
    incomeTaxExpense: incomeTaxExpense.present
        ? incomeTaxExpense.value
        : this.incomeTaxExpense,
    interestExpense: interestExpense.present
        ? interestExpense.value
        : this.interestExpense,
    earningsPerShare: earningsPerShare.present
        ? earningsPerShare.value
        : this.earningsPerShare,
    cash: cash.present ? cash.value : this.cash,
    shortTermInvestments: shortTermInvestments.present
        ? shortTermInvestments.value
        : this.shortTermInvestments,
    shortTermDebt: shortTermDebt.present
        ? shortTermDebt.value
        : this.shortTermDebt,
    longTermDebt: longTermDebt.present ? longTermDebt.value : this.longTermDebt,
    totalStockholderEquity: totalStockholderEquity.present
        ? totalStockholderEquity.value
        : this.totalStockholderEquity,
    bookValuePerShare: bookValuePerShare.present
        ? bookValuePerShare.value
        : this.bookValuePerShare,
    operatingCashFlow: operatingCashFlow.present
        ? operatingCashFlow.value
        : this.operatingCashFlow,
    investmentCashFlow: investmentCashFlow.present
        ? investmentCashFlow.value
        : this.investmentCashFlow,
    freeCashFlow: freeCashFlow.present ? freeCashFlow.value : this.freeCashFlow,
    sharesOutstanding: sharesOutstanding.present
        ? sharesOutstanding.value
        : this.sharesOutstanding,
    sharesOutstandingAsOf: sharesOutstandingAsOf.present
        ? sharesOutstandingAsOf.value
        : this.sharesOutstandingAsOf,
    marketCap: marketCap.present ? marketCap.value : this.marketCap,
    enterpriseToEbitda: enterpriseToEbitda.present
        ? enterpriseToEbitda.value
        : this.enterpriseToEbitda,
    nopat: nopat.present ? nopat.value : this.nopat,
    propertyPlantEquipment: propertyPlantEquipment.present
        ? propertyPlantEquipment.value
        : this.propertyPlantEquipment,
    intangibleAssets: intangibleAssets.present
        ? intangibleAssets.value
        : this.intangibleAssets,
    totalCurrentAssets: totalCurrentAssets.present
        ? totalCurrentAssets.value
        : this.totalCurrentAssets,
    currentLiabilities: currentLiabilities.present
        ? currentLiabilities.value
        : this.currentLiabilities,
    realizedShareCapital: realizedShareCapital.present
        ? realizedShareCapital.value
        : this.realizedShareCapital,
    profitReserves: profitReserves.present
        ? profitReserves.value
        : this.profitReserves,
  );
  CachedFundamentals copyWithCompanion(CachedFundamentalsTableCompanion data) {
    return CachedFundamentals(
      ticker: data.ticker.present ? data.ticker.value : this.ticker,
      fiscalPeriodEnd: data.fiscalPeriodEnd.present
          ? data.fiscalPeriodEnd.value
          : this.fiscalPeriodEnd,
      totalRevenue: data.totalRevenue.present
          ? data.totalRevenue.value
          : this.totalRevenue,
      ebit: data.ebit.present ? data.ebit.value : this.ebit,
      ebitda: data.ebitda.present ? data.ebitda.value : this.ebitda,
      netIncome: data.netIncome.present ? data.netIncome.value : this.netIncome,
      incomeBeforeTax: data.incomeBeforeTax.present
          ? data.incomeBeforeTax.value
          : this.incomeBeforeTax,
      incomeTaxExpense: data.incomeTaxExpense.present
          ? data.incomeTaxExpense.value
          : this.incomeTaxExpense,
      interestExpense: data.interestExpense.present
          ? data.interestExpense.value
          : this.interestExpense,
      earningsPerShare: data.earningsPerShare.present
          ? data.earningsPerShare.value
          : this.earningsPerShare,
      cash: data.cash.present ? data.cash.value : this.cash,
      shortTermInvestments: data.shortTermInvestments.present
          ? data.shortTermInvestments.value
          : this.shortTermInvestments,
      shortTermDebt: data.shortTermDebt.present
          ? data.shortTermDebt.value
          : this.shortTermDebt,
      longTermDebt: data.longTermDebt.present
          ? data.longTermDebt.value
          : this.longTermDebt,
      totalStockholderEquity: data.totalStockholderEquity.present
          ? data.totalStockholderEquity.value
          : this.totalStockholderEquity,
      bookValuePerShare: data.bookValuePerShare.present
          ? data.bookValuePerShare.value
          : this.bookValuePerShare,
      operatingCashFlow: data.operatingCashFlow.present
          ? data.operatingCashFlow.value
          : this.operatingCashFlow,
      investmentCashFlow: data.investmentCashFlow.present
          ? data.investmentCashFlow.value
          : this.investmentCashFlow,
      freeCashFlow: data.freeCashFlow.present
          ? data.freeCashFlow.value
          : this.freeCashFlow,
      sharesOutstanding: data.sharesOutstanding.present
          ? data.sharesOutstanding.value
          : this.sharesOutstanding,
      sharesOutstandingAsOf: data.sharesOutstandingAsOf.present
          ? data.sharesOutstandingAsOf.value
          : this.sharesOutstandingAsOf,
      marketCap: data.marketCap.present ? data.marketCap.value : this.marketCap,
      enterpriseToEbitda: data.enterpriseToEbitda.present
          ? data.enterpriseToEbitda.value
          : this.enterpriseToEbitda,
      nopat: data.nopat.present ? data.nopat.value : this.nopat,
      propertyPlantEquipment: data.propertyPlantEquipment.present
          ? data.propertyPlantEquipment.value
          : this.propertyPlantEquipment,
      intangibleAssets: data.intangibleAssets.present
          ? data.intangibleAssets.value
          : this.intangibleAssets,
      totalCurrentAssets: data.totalCurrentAssets.present
          ? data.totalCurrentAssets.value
          : this.totalCurrentAssets,
      currentLiabilities: data.currentLiabilities.present
          ? data.currentLiabilities.value
          : this.currentLiabilities,
      realizedShareCapital: data.realizedShareCapital.present
          ? data.realizedShareCapital.value
          : this.realizedShareCapital,
      profitReserves: data.profitReserves.present
          ? data.profitReserves.value
          : this.profitReserves,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedFundamentals(')
          ..write('ticker: $ticker, ')
          ..write('fiscalPeriodEnd: $fiscalPeriodEnd, ')
          ..write('totalRevenue: $totalRevenue, ')
          ..write('ebit: $ebit, ')
          ..write('ebitda: $ebitda, ')
          ..write('netIncome: $netIncome, ')
          ..write('incomeBeforeTax: $incomeBeforeTax, ')
          ..write('incomeTaxExpense: $incomeTaxExpense, ')
          ..write('interestExpense: $interestExpense, ')
          ..write('earningsPerShare: $earningsPerShare, ')
          ..write('cash: $cash, ')
          ..write('shortTermInvestments: $shortTermInvestments, ')
          ..write('shortTermDebt: $shortTermDebt, ')
          ..write('longTermDebt: $longTermDebt, ')
          ..write('totalStockholderEquity: $totalStockholderEquity, ')
          ..write('bookValuePerShare: $bookValuePerShare, ')
          ..write('operatingCashFlow: $operatingCashFlow, ')
          ..write('investmentCashFlow: $investmentCashFlow, ')
          ..write('freeCashFlow: $freeCashFlow, ')
          ..write('sharesOutstanding: $sharesOutstanding, ')
          ..write('sharesOutstandingAsOf: $sharesOutstandingAsOf, ')
          ..write('marketCap: $marketCap, ')
          ..write('enterpriseToEbitda: $enterpriseToEbitda, ')
          ..write('nopat: $nopat, ')
          ..write('propertyPlantEquipment: $propertyPlantEquipment, ')
          ..write('intangibleAssets: $intangibleAssets, ')
          ..write('totalCurrentAssets: $totalCurrentAssets, ')
          ..write('currentLiabilities: $currentLiabilities, ')
          ..write('realizedShareCapital: $realizedShareCapital, ')
          ..write('profitReserves: $profitReserves')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    ticker,
    fiscalPeriodEnd,
    totalRevenue,
    ebit,
    ebitda,
    netIncome,
    incomeBeforeTax,
    incomeTaxExpense,
    interestExpense,
    earningsPerShare,
    cash,
    shortTermInvestments,
    shortTermDebt,
    longTermDebt,
    totalStockholderEquity,
    bookValuePerShare,
    operatingCashFlow,
    investmentCashFlow,
    freeCashFlow,
    sharesOutstanding,
    sharesOutstandingAsOf,
    marketCap,
    enterpriseToEbitda,
    nopat,
    propertyPlantEquipment,
    intangibleAssets,
    totalCurrentAssets,
    currentLiabilities,
    realizedShareCapital,
    profitReserves,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedFundamentals &&
          other.ticker == this.ticker &&
          other.fiscalPeriodEnd == this.fiscalPeriodEnd &&
          other.totalRevenue == this.totalRevenue &&
          other.ebit == this.ebit &&
          other.ebitda == this.ebitda &&
          other.netIncome == this.netIncome &&
          other.incomeBeforeTax == this.incomeBeforeTax &&
          other.incomeTaxExpense == this.incomeTaxExpense &&
          other.interestExpense == this.interestExpense &&
          other.earningsPerShare == this.earningsPerShare &&
          other.cash == this.cash &&
          other.shortTermInvestments == this.shortTermInvestments &&
          other.shortTermDebt == this.shortTermDebt &&
          other.longTermDebt == this.longTermDebt &&
          other.totalStockholderEquity == this.totalStockholderEquity &&
          other.bookValuePerShare == this.bookValuePerShare &&
          other.operatingCashFlow == this.operatingCashFlow &&
          other.investmentCashFlow == this.investmentCashFlow &&
          other.freeCashFlow == this.freeCashFlow &&
          other.sharesOutstanding == this.sharesOutstanding &&
          other.sharesOutstandingAsOf == this.sharesOutstandingAsOf &&
          other.marketCap == this.marketCap &&
          other.enterpriseToEbitda == this.enterpriseToEbitda &&
          other.nopat == this.nopat &&
          other.propertyPlantEquipment == this.propertyPlantEquipment &&
          other.intangibleAssets == this.intangibleAssets &&
          other.totalCurrentAssets == this.totalCurrentAssets &&
          other.currentLiabilities == this.currentLiabilities &&
          other.realizedShareCapital == this.realizedShareCapital &&
          other.profitReserves == this.profitReserves);
}

class CachedFundamentalsTableCompanion
    extends UpdateCompanion<CachedFundamentals> {
  final Value<String> ticker;
  final Value<String> fiscalPeriodEnd;
  final Value<double?> totalRevenue;
  final Value<double?> ebit;
  final Value<double?> ebitda;
  final Value<double?> netIncome;
  final Value<double?> incomeBeforeTax;
  final Value<double?> incomeTaxExpense;
  final Value<double?> interestExpense;
  final Value<double?> earningsPerShare;
  final Value<double?> cash;
  final Value<double?> shortTermInvestments;
  final Value<double?> shortTermDebt;
  final Value<double?> longTermDebt;
  final Value<double?> totalStockholderEquity;
  final Value<double?> bookValuePerShare;
  final Value<double?> operatingCashFlow;
  final Value<double?> investmentCashFlow;
  final Value<double?> freeCashFlow;
  final Value<double?> sharesOutstanding;
  final Value<double?> sharesOutstandingAsOf;
  final Value<double?> marketCap;
  final Value<double?> enterpriseToEbitda;
  final Value<double?> nopat;
  final Value<double?> propertyPlantEquipment;
  final Value<double?> intangibleAssets;
  final Value<double?> totalCurrentAssets;
  final Value<double?> currentLiabilities;
  final Value<double?> realizedShareCapital;
  final Value<double?> profitReserves;
  final Value<int> rowid;
  const CachedFundamentalsTableCompanion({
    this.ticker = const Value.absent(),
    this.fiscalPeriodEnd = const Value.absent(),
    this.totalRevenue = const Value.absent(),
    this.ebit = const Value.absent(),
    this.ebitda = const Value.absent(),
    this.netIncome = const Value.absent(),
    this.incomeBeforeTax = const Value.absent(),
    this.incomeTaxExpense = const Value.absent(),
    this.interestExpense = const Value.absent(),
    this.earningsPerShare = const Value.absent(),
    this.cash = const Value.absent(),
    this.shortTermInvestments = const Value.absent(),
    this.shortTermDebt = const Value.absent(),
    this.longTermDebt = const Value.absent(),
    this.totalStockholderEquity = const Value.absent(),
    this.bookValuePerShare = const Value.absent(),
    this.operatingCashFlow = const Value.absent(),
    this.investmentCashFlow = const Value.absent(),
    this.freeCashFlow = const Value.absent(),
    this.sharesOutstanding = const Value.absent(),
    this.sharesOutstandingAsOf = const Value.absent(),
    this.marketCap = const Value.absent(),
    this.enterpriseToEbitda = const Value.absent(),
    this.nopat = const Value.absent(),
    this.propertyPlantEquipment = const Value.absent(),
    this.intangibleAssets = const Value.absent(),
    this.totalCurrentAssets = const Value.absent(),
    this.currentLiabilities = const Value.absent(),
    this.realizedShareCapital = const Value.absent(),
    this.profitReserves = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedFundamentalsTableCompanion.insert({
    required String ticker,
    required String fiscalPeriodEnd,
    this.totalRevenue = const Value.absent(),
    this.ebit = const Value.absent(),
    this.ebitda = const Value.absent(),
    this.netIncome = const Value.absent(),
    this.incomeBeforeTax = const Value.absent(),
    this.incomeTaxExpense = const Value.absent(),
    this.interestExpense = const Value.absent(),
    this.earningsPerShare = const Value.absent(),
    this.cash = const Value.absent(),
    this.shortTermInvestments = const Value.absent(),
    this.shortTermDebt = const Value.absent(),
    this.longTermDebt = const Value.absent(),
    this.totalStockholderEquity = const Value.absent(),
    this.bookValuePerShare = const Value.absent(),
    this.operatingCashFlow = const Value.absent(),
    this.investmentCashFlow = const Value.absent(),
    this.freeCashFlow = const Value.absent(),
    this.sharesOutstanding = const Value.absent(),
    this.sharesOutstandingAsOf = const Value.absent(),
    this.marketCap = const Value.absent(),
    this.enterpriseToEbitda = const Value.absent(),
    this.nopat = const Value.absent(),
    this.propertyPlantEquipment = const Value.absent(),
    this.intangibleAssets = const Value.absent(),
    this.totalCurrentAssets = const Value.absent(),
    this.currentLiabilities = const Value.absent(),
    this.realizedShareCapital = const Value.absent(),
    this.profitReserves = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ticker = Value(ticker),
       fiscalPeriodEnd = Value(fiscalPeriodEnd);
  static Insertable<CachedFundamentals> custom({
    Expression<String>? ticker,
    Expression<String>? fiscalPeriodEnd,
    Expression<double>? totalRevenue,
    Expression<double>? ebit,
    Expression<double>? ebitda,
    Expression<double>? netIncome,
    Expression<double>? incomeBeforeTax,
    Expression<double>? incomeTaxExpense,
    Expression<double>? interestExpense,
    Expression<double>? earningsPerShare,
    Expression<double>? cash,
    Expression<double>? shortTermInvestments,
    Expression<double>? shortTermDebt,
    Expression<double>? longTermDebt,
    Expression<double>? totalStockholderEquity,
    Expression<double>? bookValuePerShare,
    Expression<double>? operatingCashFlow,
    Expression<double>? investmentCashFlow,
    Expression<double>? freeCashFlow,
    Expression<double>? sharesOutstanding,
    Expression<double>? sharesOutstandingAsOf,
    Expression<double>? marketCap,
    Expression<double>? enterpriseToEbitda,
    Expression<double>? nopat,
    Expression<double>? propertyPlantEquipment,
    Expression<double>? intangibleAssets,
    Expression<double>? totalCurrentAssets,
    Expression<double>? currentLiabilities,
    Expression<double>? realizedShareCapital,
    Expression<double>? profitReserves,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ticker != null) 'ticker': ticker,
      if (fiscalPeriodEnd != null) 'fiscal_period_end': fiscalPeriodEnd,
      if (totalRevenue != null) 'total_revenue': totalRevenue,
      if (ebit != null) 'ebit': ebit,
      if (ebitda != null) 'ebitda': ebitda,
      if (netIncome != null) 'net_income': netIncome,
      if (incomeBeforeTax != null) 'income_before_tax': incomeBeforeTax,
      if (incomeTaxExpense != null) 'income_tax_expense': incomeTaxExpense,
      if (interestExpense != null) 'interest_expense': interestExpense,
      if (earningsPerShare != null) 'earnings_per_share': earningsPerShare,
      if (cash != null) 'cash': cash,
      if (shortTermInvestments != null)
        'short_term_investments': shortTermInvestments,
      if (shortTermDebt != null) 'short_term_debt': shortTermDebt,
      if (longTermDebt != null) 'long_term_debt': longTermDebt,
      if (totalStockholderEquity != null)
        'total_stockholder_equity': totalStockholderEquity,
      if (bookValuePerShare != null) 'book_value_per_share': bookValuePerShare,
      if (operatingCashFlow != null) 'operating_cash_flow': operatingCashFlow,
      if (investmentCashFlow != null)
        'investment_cash_flow': investmentCashFlow,
      if (freeCashFlow != null) 'free_cash_flow': freeCashFlow,
      if (sharesOutstanding != null) 'shares_outstanding': sharesOutstanding,
      if (sharesOutstandingAsOf != null)
        'shares_outstanding_as_of': sharesOutstandingAsOf,
      if (marketCap != null) 'market_cap': marketCap,
      if (enterpriseToEbitda != null)
        'enterprise_to_ebitda': enterpriseToEbitda,
      if (nopat != null) 'nopat': nopat,
      if (propertyPlantEquipment != null)
        'property_plant_equipment': propertyPlantEquipment,
      if (intangibleAssets != null) 'intangible_assets': intangibleAssets,
      if (totalCurrentAssets != null)
        'total_current_assets': totalCurrentAssets,
      if (currentLiabilities != null) 'current_liabilities': currentLiabilities,
      if (realizedShareCapital != null)
        'realized_share_capital': realizedShareCapital,
      if (profitReserves != null) 'profit_reserves': profitReserves,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedFundamentalsTableCompanion copyWith({
    Value<String>? ticker,
    Value<String>? fiscalPeriodEnd,
    Value<double?>? totalRevenue,
    Value<double?>? ebit,
    Value<double?>? ebitda,
    Value<double?>? netIncome,
    Value<double?>? incomeBeforeTax,
    Value<double?>? incomeTaxExpense,
    Value<double?>? interestExpense,
    Value<double?>? earningsPerShare,
    Value<double?>? cash,
    Value<double?>? shortTermInvestments,
    Value<double?>? shortTermDebt,
    Value<double?>? longTermDebt,
    Value<double?>? totalStockholderEquity,
    Value<double?>? bookValuePerShare,
    Value<double?>? operatingCashFlow,
    Value<double?>? investmentCashFlow,
    Value<double?>? freeCashFlow,
    Value<double?>? sharesOutstanding,
    Value<double?>? sharesOutstandingAsOf,
    Value<double?>? marketCap,
    Value<double?>? enterpriseToEbitda,
    Value<double?>? nopat,
    Value<double?>? propertyPlantEquipment,
    Value<double?>? intangibleAssets,
    Value<double?>? totalCurrentAssets,
    Value<double?>? currentLiabilities,
    Value<double?>? realizedShareCapital,
    Value<double?>? profitReserves,
    Value<int>? rowid,
  }) {
    return CachedFundamentalsTableCompanion(
      ticker: ticker ?? this.ticker,
      fiscalPeriodEnd: fiscalPeriodEnd ?? this.fiscalPeriodEnd,
      totalRevenue: totalRevenue ?? this.totalRevenue,
      ebit: ebit ?? this.ebit,
      ebitda: ebitda ?? this.ebitda,
      netIncome: netIncome ?? this.netIncome,
      incomeBeforeTax: incomeBeforeTax ?? this.incomeBeforeTax,
      incomeTaxExpense: incomeTaxExpense ?? this.incomeTaxExpense,
      interestExpense: interestExpense ?? this.interestExpense,
      earningsPerShare: earningsPerShare ?? this.earningsPerShare,
      cash: cash ?? this.cash,
      shortTermInvestments: shortTermInvestments ?? this.shortTermInvestments,
      shortTermDebt: shortTermDebt ?? this.shortTermDebt,
      longTermDebt: longTermDebt ?? this.longTermDebt,
      totalStockholderEquity:
          totalStockholderEquity ?? this.totalStockholderEquity,
      bookValuePerShare: bookValuePerShare ?? this.bookValuePerShare,
      operatingCashFlow: operatingCashFlow ?? this.operatingCashFlow,
      investmentCashFlow: investmentCashFlow ?? this.investmentCashFlow,
      freeCashFlow: freeCashFlow ?? this.freeCashFlow,
      sharesOutstanding: sharesOutstanding ?? this.sharesOutstanding,
      sharesOutstandingAsOf:
          sharesOutstandingAsOf ?? this.sharesOutstandingAsOf,
      marketCap: marketCap ?? this.marketCap,
      enterpriseToEbitda: enterpriseToEbitda ?? this.enterpriseToEbitda,
      nopat: nopat ?? this.nopat,
      propertyPlantEquipment:
          propertyPlantEquipment ?? this.propertyPlantEquipment,
      intangibleAssets: intangibleAssets ?? this.intangibleAssets,
      totalCurrentAssets: totalCurrentAssets ?? this.totalCurrentAssets,
      currentLiabilities: currentLiabilities ?? this.currentLiabilities,
      realizedShareCapital: realizedShareCapital ?? this.realizedShareCapital,
      profitReserves: profitReserves ?? this.profitReserves,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ticker.present) {
      map['ticker'] = Variable<String>(ticker.value);
    }
    if (fiscalPeriodEnd.present) {
      map['fiscal_period_end'] = Variable<String>(fiscalPeriodEnd.value);
    }
    if (totalRevenue.present) {
      map['total_revenue'] = Variable<double>(totalRevenue.value);
    }
    if (ebit.present) {
      map['ebit'] = Variable<double>(ebit.value);
    }
    if (ebitda.present) {
      map['ebitda'] = Variable<double>(ebitda.value);
    }
    if (netIncome.present) {
      map['net_income'] = Variable<double>(netIncome.value);
    }
    if (incomeBeforeTax.present) {
      map['income_before_tax'] = Variable<double>(incomeBeforeTax.value);
    }
    if (incomeTaxExpense.present) {
      map['income_tax_expense'] = Variable<double>(incomeTaxExpense.value);
    }
    if (interestExpense.present) {
      map['interest_expense'] = Variable<double>(interestExpense.value);
    }
    if (earningsPerShare.present) {
      map['earnings_per_share'] = Variable<double>(earningsPerShare.value);
    }
    if (cash.present) {
      map['cash'] = Variable<double>(cash.value);
    }
    if (shortTermInvestments.present) {
      map['short_term_investments'] = Variable<double>(
        shortTermInvestments.value,
      );
    }
    if (shortTermDebt.present) {
      map['short_term_debt'] = Variable<double>(shortTermDebt.value);
    }
    if (longTermDebt.present) {
      map['long_term_debt'] = Variable<double>(longTermDebt.value);
    }
    if (totalStockholderEquity.present) {
      map['total_stockholder_equity'] = Variable<double>(
        totalStockholderEquity.value,
      );
    }
    if (bookValuePerShare.present) {
      map['book_value_per_share'] = Variable<double>(bookValuePerShare.value);
    }
    if (operatingCashFlow.present) {
      map['operating_cash_flow'] = Variable<double>(operatingCashFlow.value);
    }
    if (investmentCashFlow.present) {
      map['investment_cash_flow'] = Variable<double>(investmentCashFlow.value);
    }
    if (freeCashFlow.present) {
      map['free_cash_flow'] = Variable<double>(freeCashFlow.value);
    }
    if (sharesOutstanding.present) {
      map['shares_outstanding'] = Variable<double>(sharesOutstanding.value);
    }
    if (sharesOutstandingAsOf.present) {
      map['shares_outstanding_as_of'] = Variable<double>(
        sharesOutstandingAsOf.value,
      );
    }
    if (marketCap.present) {
      map['market_cap'] = Variable<double>(marketCap.value);
    }
    if (enterpriseToEbitda.present) {
      map['enterprise_to_ebitda'] = Variable<double>(enterpriseToEbitda.value);
    }
    if (nopat.present) {
      map['nopat'] = Variable<double>(nopat.value);
    }
    if (propertyPlantEquipment.present) {
      map['property_plant_equipment'] = Variable<double>(
        propertyPlantEquipment.value,
      );
    }
    if (intangibleAssets.present) {
      map['intangible_assets'] = Variable<double>(intangibleAssets.value);
    }
    if (totalCurrentAssets.present) {
      map['total_current_assets'] = Variable<double>(totalCurrentAssets.value);
    }
    if (currentLiabilities.present) {
      map['current_liabilities'] = Variable<double>(currentLiabilities.value);
    }
    if (realizedShareCapital.present) {
      map['realized_share_capital'] = Variable<double>(
        realizedShareCapital.value,
      );
    }
    if (profitReserves.present) {
      map['profit_reserves'] = Variable<double>(profitReserves.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedFundamentalsTableCompanion(')
          ..write('ticker: $ticker, ')
          ..write('fiscalPeriodEnd: $fiscalPeriodEnd, ')
          ..write('totalRevenue: $totalRevenue, ')
          ..write('ebit: $ebit, ')
          ..write('ebitda: $ebitda, ')
          ..write('netIncome: $netIncome, ')
          ..write('incomeBeforeTax: $incomeBeforeTax, ')
          ..write('incomeTaxExpense: $incomeTaxExpense, ')
          ..write('interestExpense: $interestExpense, ')
          ..write('earningsPerShare: $earningsPerShare, ')
          ..write('cash: $cash, ')
          ..write('shortTermInvestments: $shortTermInvestments, ')
          ..write('shortTermDebt: $shortTermDebt, ')
          ..write('longTermDebt: $longTermDebt, ')
          ..write('totalStockholderEquity: $totalStockholderEquity, ')
          ..write('bookValuePerShare: $bookValuePerShare, ')
          ..write('operatingCashFlow: $operatingCashFlow, ')
          ..write('investmentCashFlow: $investmentCashFlow, ')
          ..write('freeCashFlow: $freeCashFlow, ')
          ..write('sharesOutstanding: $sharesOutstanding, ')
          ..write('sharesOutstandingAsOf: $sharesOutstandingAsOf, ')
          ..write('marketCap: $marketCap, ')
          ..write('enterpriseToEbitda: $enterpriseToEbitda, ')
          ..write('nopat: $nopat, ')
          ..write('propertyPlantEquipment: $propertyPlantEquipment, ')
          ..write('intangibleAssets: $intangibleAssets, ')
          ..write('totalCurrentAssets: $totalCurrentAssets, ')
          ..write('currentLiabilities: $currentLiabilities, ')
          ..write('realizedShareCapital: $realizedShareCapital, ')
          ..write('profitReserves: $profitReserves, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedProfilesTable extends CachedProfiles
    with TableInfo<$CachedProfilesTable, CachedProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tickerMeta = const VerificationMeta('ticker');
  @override
  late final GeneratedColumn<String> ticker = GeneratedColumn<String>(
    'ticker',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sectorKeyMeta = const VerificationMeta(
    'sectorKey',
  );
  @override
  late final GeneratedColumn<String> sectorKey = GeneratedColumn<String>(
    'sector_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sectorLabelMeta = const VerificationMeta(
    'sectorLabel',
  );
  @override
  late final GeneratedColumn<String> sectorLabel = GeneratedColumn<String>(
    'sector_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _industryMeta = const VerificationMeta(
    'industry',
  );
  @override
  late final GeneratedColumn<String> industry = GeneratedColumn<String>(
    'industry',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ticker,
    name,
    sectorKey,
    sectorLabel,
    industry,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ticker')) {
      context.handle(
        _tickerMeta,
        ticker.isAcceptableOrUnknown(data['ticker']!, _tickerMeta),
      );
    } else if (isInserting) {
      context.missing(_tickerMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sector_key')) {
      context.handle(
        _sectorKeyMeta,
        sectorKey.isAcceptableOrUnknown(data['sector_key']!, _sectorKeyMeta),
      );
    }
    if (data.containsKey('sector_label')) {
      context.handle(
        _sectorLabelMeta,
        sectorLabel.isAcceptableOrUnknown(
          data['sector_label']!,
          _sectorLabelMeta,
        ),
      );
    }
    if (data.containsKey('industry')) {
      context.handle(
        _industryMeta,
        industry.isAcceptableOrUnknown(data['industry']!, _industryMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ticker};
  @override
  CachedProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedProfile(
      ticker: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ticker'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sectorKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sector_key'],
      ),
      sectorLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sector_label'],
      ),
      industry: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}industry'],
      ),
    );
  }

  @override
  $CachedProfilesTable createAlias(String alias) {
    return $CachedProfilesTable(attachedDatabase, alias);
  }
}

class CachedProfile extends DataClass implements Insertable<CachedProfile> {
  final String ticker;
  final String name;
  final String? sectorKey;
  final String? sectorLabel;
  final String? industry;
  const CachedProfile({
    required this.ticker,
    required this.name,
    this.sectorKey,
    this.sectorLabel,
    this.industry,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ticker'] = Variable<String>(ticker);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || sectorKey != null) {
      map['sector_key'] = Variable<String>(sectorKey);
    }
    if (!nullToAbsent || sectorLabel != null) {
      map['sector_label'] = Variable<String>(sectorLabel);
    }
    if (!nullToAbsent || industry != null) {
      map['industry'] = Variable<String>(industry);
    }
    return map;
  }

  CachedProfilesCompanion toCompanion(bool nullToAbsent) {
    return CachedProfilesCompanion(
      ticker: Value(ticker),
      name: Value(name),
      sectorKey: sectorKey == null && nullToAbsent
          ? const Value.absent()
          : Value(sectorKey),
      sectorLabel: sectorLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(sectorLabel),
      industry: industry == null && nullToAbsent
          ? const Value.absent()
          : Value(industry),
    );
  }

  factory CachedProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedProfile(
      ticker: serializer.fromJson<String>(json['ticker']),
      name: serializer.fromJson<String>(json['name']),
      sectorKey: serializer.fromJson<String?>(json['sectorKey']),
      sectorLabel: serializer.fromJson<String?>(json['sectorLabel']),
      industry: serializer.fromJson<String?>(json['industry']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ticker': serializer.toJson<String>(ticker),
      'name': serializer.toJson<String>(name),
      'sectorKey': serializer.toJson<String?>(sectorKey),
      'sectorLabel': serializer.toJson<String?>(sectorLabel),
      'industry': serializer.toJson<String?>(industry),
    };
  }

  CachedProfile copyWith({
    String? ticker,
    String? name,
    Value<String?> sectorKey = const Value.absent(),
    Value<String?> sectorLabel = const Value.absent(),
    Value<String?> industry = const Value.absent(),
  }) => CachedProfile(
    ticker: ticker ?? this.ticker,
    name: name ?? this.name,
    sectorKey: sectorKey.present ? sectorKey.value : this.sectorKey,
    sectorLabel: sectorLabel.present ? sectorLabel.value : this.sectorLabel,
    industry: industry.present ? industry.value : this.industry,
  );
  CachedProfile copyWithCompanion(CachedProfilesCompanion data) {
    return CachedProfile(
      ticker: data.ticker.present ? data.ticker.value : this.ticker,
      name: data.name.present ? data.name.value : this.name,
      sectorKey: data.sectorKey.present ? data.sectorKey.value : this.sectorKey,
      sectorLabel: data.sectorLabel.present
          ? data.sectorLabel.value
          : this.sectorLabel,
      industry: data.industry.present ? data.industry.value : this.industry,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedProfile(')
          ..write('ticker: $ticker, ')
          ..write('name: $name, ')
          ..write('sectorKey: $sectorKey, ')
          ..write('sectorLabel: $sectorLabel, ')
          ..write('industry: $industry')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(ticker, name, sectorKey, sectorLabel, industry);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedProfile &&
          other.ticker == this.ticker &&
          other.name == this.name &&
          other.sectorKey == this.sectorKey &&
          other.sectorLabel == this.sectorLabel &&
          other.industry == this.industry);
}

class CachedProfilesCompanion extends UpdateCompanion<CachedProfile> {
  final Value<String> ticker;
  final Value<String> name;
  final Value<String?> sectorKey;
  final Value<String?> sectorLabel;
  final Value<String?> industry;
  final Value<int> rowid;
  const CachedProfilesCompanion({
    this.ticker = const Value.absent(),
    this.name = const Value.absent(),
    this.sectorKey = const Value.absent(),
    this.sectorLabel = const Value.absent(),
    this.industry = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedProfilesCompanion.insert({
    required String ticker,
    required String name,
    this.sectorKey = const Value.absent(),
    this.sectorLabel = const Value.absent(),
    this.industry = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ticker = Value(ticker),
       name = Value(name);
  static Insertable<CachedProfile> custom({
    Expression<String>? ticker,
    Expression<String>? name,
    Expression<String>? sectorKey,
    Expression<String>? sectorLabel,
    Expression<String>? industry,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ticker != null) 'ticker': ticker,
      if (name != null) 'name': name,
      if (sectorKey != null) 'sector_key': sectorKey,
      if (sectorLabel != null) 'sector_label': sectorLabel,
      if (industry != null) 'industry': industry,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedProfilesCompanion copyWith({
    Value<String>? ticker,
    Value<String>? name,
    Value<String?>? sectorKey,
    Value<String?>? sectorLabel,
    Value<String?>? industry,
    Value<int>? rowid,
  }) {
    return CachedProfilesCompanion(
      ticker: ticker ?? this.ticker,
      name: name ?? this.name,
      sectorKey: sectorKey ?? this.sectorKey,
      sectorLabel: sectorLabel ?? this.sectorLabel,
      industry: industry ?? this.industry,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ticker.present) {
      map['ticker'] = Variable<String>(ticker.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sectorKey.present) {
      map['sector_key'] = Variable<String>(sectorKey.value);
    }
    if (sectorLabel.present) {
      map['sector_label'] = Variable<String>(sectorLabel.value);
    }
    if (industry.present) {
      map['industry'] = Variable<String>(industry.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedProfilesCompanion(')
          ..write('ticker: $ticker, ')
          ..write('name: $name, ')
          ..write('sectorKey: $sectorKey, ')
          ..write('sectorLabel: $sectorLabel, ')
          ..write('industry: $industry, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedMacroRatesTable extends CachedMacroRates
    with TableInfo<$CachedMacroRatesTable, CachedMacroRate> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedMacroRatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<int> seriesId = GeneratedColumn<int>(
    'series_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<double> value = GeneratedColumn<double>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [seriesId, date, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_macro_rates';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedMacroRate> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seriesIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {seriesId, date};
  @override
  CachedMacroRate map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedMacroRate(
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}series_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $CachedMacroRatesTable createAlias(String alias) {
    return $CachedMacroRatesTable(attachedDatabase, alias);
  }
}

class CachedMacroRate extends DataClass implements Insertable<CachedMacroRate> {
  /// Código da série no SGS (12 = CDI diário, 433 = IPCA mensal).
  final int seriesId;
  final String date;

  /// Valor já convertido para fração (0,000374 = 0,0374% ao dia).
  final double value;
  const CachedMacroRate({
    required this.seriesId,
    required this.date,
    required this.value,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['series_id'] = Variable<int>(seriesId);
    map['date'] = Variable<String>(date);
    map['value'] = Variable<double>(value);
    return map;
  }

  CachedMacroRatesCompanion toCompanion(bool nullToAbsent) {
    return CachedMacroRatesCompanion(
      seriesId: Value(seriesId),
      date: Value(date),
      value: Value(value),
    );
  }

  factory CachedMacroRate.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedMacroRate(
      seriesId: serializer.fromJson<int>(json['seriesId']),
      date: serializer.fromJson<String>(json['date']),
      value: serializer.fromJson<double>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seriesId': serializer.toJson<int>(seriesId),
      'date': serializer.toJson<String>(date),
      'value': serializer.toJson<double>(value),
    };
  }

  CachedMacroRate copyWith({int? seriesId, String? date, double? value}) =>
      CachedMacroRate(
        seriesId: seriesId ?? this.seriesId,
        date: date ?? this.date,
        value: value ?? this.value,
      );
  CachedMacroRate copyWithCompanion(CachedMacroRatesCompanion data) {
    return CachedMacroRate(
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      date: data.date.present ? data.date.value : this.date,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedMacroRate(')
          ..write('seriesId: $seriesId, ')
          ..write('date: $date, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(seriesId, date, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedMacroRate &&
          other.seriesId == this.seriesId &&
          other.date == this.date &&
          other.value == this.value);
}

class CachedMacroRatesCompanion extends UpdateCompanion<CachedMacroRate> {
  final Value<int> seriesId;
  final Value<String> date;
  final Value<double> value;
  final Value<int> rowid;
  const CachedMacroRatesCompanion({
    this.seriesId = const Value.absent(),
    this.date = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedMacroRatesCompanion.insert({
    required int seriesId,
    required String date,
    required double value,
    this.rowid = const Value.absent(),
  }) : seriesId = Value(seriesId),
       date = Value(date),
       value = Value(value);
  static Insertable<CachedMacroRate> custom({
    Expression<int>? seriesId,
    Expression<String>? date,
    Expression<double>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (seriesId != null) 'series_id': seriesId,
      if (date != null) 'date': date,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedMacroRatesCompanion copyWith({
    Value<int>? seriesId,
    Value<String>? date,
    Value<double>? value,
    Value<int>? rowid,
  }) {
    return CachedMacroRatesCompanion(
      seriesId: seriesId ?? this.seriesId,
      date: date ?? this.date,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (seriesId.present) {
      map['series_id'] = Variable<int>(seriesId.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (value.present) {
      map['value'] = Variable<double>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedMacroRatesCompanion(')
          ..write('seriesId: $seriesId, ')
          ..write('date: $date, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CacheEntriesTable extends CacheEntries
    with TableInfo<$CacheEntriesTable, CacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<CacheEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  CacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheEntry(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $CacheEntriesTable createAlias(String alias) {
    return $CacheEntriesTable(attachedDatabase, alias);
  }
}

class CacheEntry extends DataClass implements Insertable<CacheEntry> {
  /// Chave lógica do recurso (ex.: `prices:PETR4`, `fundamentals:VALE3`).
  final String key;
  final DateTime fetchedAt;
  const CacheEntry({required this.key, required this.fetchedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  CacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return CacheEntriesCompanion(key: Value(key), fetchedAt: Value(fetchedAt));
  }

  factory CacheEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheEntry(
      key: serializer.fromJson<String>(json['key']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  CacheEntry copyWith({String? key, DateTime? fetchedAt}) =>
      CacheEntry(key: key ?? this.key, fetchedAt: fetchedAt ?? this.fetchedAt);
  CacheEntry copyWithCompanion(CacheEntriesCompanion data) {
    return CacheEntry(
      key: data.key.present ? data.key.value : this.key,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntry(')
          ..write('key: $key, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CacheEntry &&
          other.key == this.key &&
          other.fetchedAt == this.fetchedAt);
}

class CacheEntriesCompanion extends UpdateCompanion<CacheEntry> {
  final Value<String> key;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const CacheEntriesCompanion({
    this.key = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CacheEntriesCompanion.insert({
    required String key,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       fetchedAt = Value(fetchedAt);
  static Insertable<CacheEntry> custom({
    Expression<String>? key,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CacheEntriesCompanion copyWith({
    Value<String>? key,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return CacheEntriesCompanion(
      key: key ?? this.key,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntriesCompanion(')
          ..write('key: $key, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CacheDatabase extends GeneratedDatabase {
  _$CacheDatabase(QueryExecutor e) : super(e);
  $CacheDatabaseManager get managers => $CacheDatabaseManager(this);
  late final $CachedPricesTable cachedPrices = $CachedPricesTable(this);
  late final $CachedFundamentalsTableTable cachedFundamentalsTable =
      $CachedFundamentalsTableTable(this);
  late final $CachedProfilesTable cachedProfiles = $CachedProfilesTable(this);
  late final $CachedMacroRatesTable cachedMacroRates = $CachedMacroRatesTable(
    this,
  );
  late final $CacheEntriesTable cacheEntries = $CacheEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedPrices,
    cachedFundamentalsTable,
    cachedProfiles,
    cachedMacroRates,
    cacheEntries,
  ];
}

typedef $$CachedPricesTableCreateCompanionBuilder =
    CachedPricesCompanion Function({
      required String ticker,
      required String date,
      required double close,
      Value<double?> adjustedClose,
      Value<double?> volume,
      Value<int> rowid,
    });
typedef $$CachedPricesTableUpdateCompanionBuilder =
    CachedPricesCompanion Function({
      Value<String> ticker,
      Value<String> date,
      Value<double> close,
      Value<double?> adjustedClose,
      Value<double?> volume,
      Value<int> rowid,
    });

class $$CachedPricesTableFilterComposer
    extends Composer<_$CacheDatabase, $CachedPricesTable> {
  $$CachedPricesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ticker => $composableBuilder(
    column: $table.ticker,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get close => $composableBuilder(
    column: $table.close,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get adjustedClose => $composableBuilder(
    column: $table.adjustedClose,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get volume => $composableBuilder(
    column: $table.volume,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedPricesTableOrderingComposer
    extends Composer<_$CacheDatabase, $CachedPricesTable> {
  $$CachedPricesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ticker => $composableBuilder(
    column: $table.ticker,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get close => $composableBuilder(
    column: $table.close,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get adjustedClose => $composableBuilder(
    column: $table.adjustedClose,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get volume => $composableBuilder(
    column: $table.volume,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedPricesTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CachedPricesTable> {
  $$CachedPricesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ticker =>
      $composableBuilder(column: $table.ticker, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<double> get close =>
      $composableBuilder(column: $table.close, builder: (column) => column);

  GeneratedColumn<double> get adjustedClose => $composableBuilder(
    column: $table.adjustedClose,
    builder: (column) => column,
  );

  GeneratedColumn<double> get volume =>
      $composableBuilder(column: $table.volume, builder: (column) => column);
}

class $$CachedPricesTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CachedPricesTable,
          CachedPrice,
          $$CachedPricesTableFilterComposer,
          $$CachedPricesTableOrderingComposer,
          $$CachedPricesTableAnnotationComposer,
          $$CachedPricesTableCreateCompanionBuilder,
          $$CachedPricesTableUpdateCompanionBuilder,
          (
            CachedPrice,
            BaseReferences<_$CacheDatabase, $CachedPricesTable, CachedPrice>,
          ),
          CachedPrice,
          PrefetchHooks Function()
        > {
  $$CachedPricesTableTableManager(_$CacheDatabase db, $CachedPricesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedPricesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedPricesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedPricesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ticker = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<double> close = const Value.absent(),
                Value<double?> adjustedClose = const Value.absent(),
                Value<double?> volume = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedPricesCompanion(
                ticker: ticker,
                date: date,
                close: close,
                adjustedClose: adjustedClose,
                volume: volume,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ticker,
                required String date,
                required double close,
                Value<double?> adjustedClose = const Value.absent(),
                Value<double?> volume = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedPricesCompanion.insert(
                ticker: ticker,
                date: date,
                close: close,
                adjustedClose: adjustedClose,
                volume: volume,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedPricesTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CachedPricesTable,
      CachedPrice,
      $$CachedPricesTableFilterComposer,
      $$CachedPricesTableOrderingComposer,
      $$CachedPricesTableAnnotationComposer,
      $$CachedPricesTableCreateCompanionBuilder,
      $$CachedPricesTableUpdateCompanionBuilder,
      (
        CachedPrice,
        BaseReferences<_$CacheDatabase, $CachedPricesTable, CachedPrice>,
      ),
      CachedPrice,
      PrefetchHooks Function()
    >;
typedef $$CachedFundamentalsTableTableCreateCompanionBuilder =
    CachedFundamentalsTableCompanion Function({
      required String ticker,
      required String fiscalPeriodEnd,
      Value<double?> totalRevenue,
      Value<double?> ebit,
      Value<double?> ebitda,
      Value<double?> netIncome,
      Value<double?> incomeBeforeTax,
      Value<double?> incomeTaxExpense,
      Value<double?> interestExpense,
      Value<double?> earningsPerShare,
      Value<double?> cash,
      Value<double?> shortTermInvestments,
      Value<double?> shortTermDebt,
      Value<double?> longTermDebt,
      Value<double?> totalStockholderEquity,
      Value<double?> bookValuePerShare,
      Value<double?> operatingCashFlow,
      Value<double?> investmentCashFlow,
      Value<double?> freeCashFlow,
      Value<double?> sharesOutstanding,
      Value<double?> sharesOutstandingAsOf,
      Value<double?> marketCap,
      Value<double?> enterpriseToEbitda,
      Value<double?> nopat,
      Value<double?> propertyPlantEquipment,
      Value<double?> intangibleAssets,
      Value<double?> totalCurrentAssets,
      Value<double?> currentLiabilities,
      Value<double?> realizedShareCapital,
      Value<double?> profitReserves,
      Value<int> rowid,
    });
typedef $$CachedFundamentalsTableTableUpdateCompanionBuilder =
    CachedFundamentalsTableCompanion Function({
      Value<String> ticker,
      Value<String> fiscalPeriodEnd,
      Value<double?> totalRevenue,
      Value<double?> ebit,
      Value<double?> ebitda,
      Value<double?> netIncome,
      Value<double?> incomeBeforeTax,
      Value<double?> incomeTaxExpense,
      Value<double?> interestExpense,
      Value<double?> earningsPerShare,
      Value<double?> cash,
      Value<double?> shortTermInvestments,
      Value<double?> shortTermDebt,
      Value<double?> longTermDebt,
      Value<double?> totalStockholderEquity,
      Value<double?> bookValuePerShare,
      Value<double?> operatingCashFlow,
      Value<double?> investmentCashFlow,
      Value<double?> freeCashFlow,
      Value<double?> sharesOutstanding,
      Value<double?> sharesOutstandingAsOf,
      Value<double?> marketCap,
      Value<double?> enterpriseToEbitda,
      Value<double?> nopat,
      Value<double?> propertyPlantEquipment,
      Value<double?> intangibleAssets,
      Value<double?> totalCurrentAssets,
      Value<double?> currentLiabilities,
      Value<double?> realizedShareCapital,
      Value<double?> profitReserves,
      Value<int> rowid,
    });

class $$CachedFundamentalsTableTableFilterComposer
    extends Composer<_$CacheDatabase, $CachedFundamentalsTableTable> {
  $$CachedFundamentalsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ticker => $composableBuilder(
    column: $table.ticker,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fiscalPeriodEnd => $composableBuilder(
    column: $table.fiscalPeriodEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalRevenue => $composableBuilder(
    column: $table.totalRevenue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get ebit => $composableBuilder(
    column: $table.ebit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get ebitda => $composableBuilder(
    column: $table.ebitda,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get netIncome => $composableBuilder(
    column: $table.netIncome,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get incomeBeforeTax => $composableBuilder(
    column: $table.incomeBeforeTax,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get incomeTaxExpense => $composableBuilder(
    column: $table.incomeTaxExpense,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get interestExpense => $composableBuilder(
    column: $table.interestExpense,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get earningsPerShare => $composableBuilder(
    column: $table.earningsPerShare,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cash => $composableBuilder(
    column: $table.cash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get shortTermInvestments => $composableBuilder(
    column: $table.shortTermInvestments,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get shortTermDebt => $composableBuilder(
    column: $table.shortTermDebt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longTermDebt => $composableBuilder(
    column: $table.longTermDebt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalStockholderEquity => $composableBuilder(
    column: $table.totalStockholderEquity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bookValuePerShare => $composableBuilder(
    column: $table.bookValuePerShare,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get operatingCashFlow => $composableBuilder(
    column: $table.operatingCashFlow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get investmentCashFlow => $composableBuilder(
    column: $table.investmentCashFlow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get freeCashFlow => $composableBuilder(
    column: $table.freeCashFlow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get sharesOutstanding => $composableBuilder(
    column: $table.sharesOutstanding,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get sharesOutstandingAsOf => $composableBuilder(
    column: $table.sharesOutstandingAsOf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get marketCap => $composableBuilder(
    column: $table.marketCap,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get enterpriseToEbitda => $composableBuilder(
    column: $table.enterpriseToEbitda,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get nopat => $composableBuilder(
    column: $table.nopat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get propertyPlantEquipment => $composableBuilder(
    column: $table.propertyPlantEquipment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get intangibleAssets => $composableBuilder(
    column: $table.intangibleAssets,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalCurrentAssets => $composableBuilder(
    column: $table.totalCurrentAssets,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get currentLiabilities => $composableBuilder(
    column: $table.currentLiabilities,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get realizedShareCapital => $composableBuilder(
    column: $table.realizedShareCapital,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get profitReserves => $composableBuilder(
    column: $table.profitReserves,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedFundamentalsTableTableOrderingComposer
    extends Composer<_$CacheDatabase, $CachedFundamentalsTableTable> {
  $$CachedFundamentalsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ticker => $composableBuilder(
    column: $table.ticker,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fiscalPeriodEnd => $composableBuilder(
    column: $table.fiscalPeriodEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalRevenue => $composableBuilder(
    column: $table.totalRevenue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get ebit => $composableBuilder(
    column: $table.ebit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get ebitda => $composableBuilder(
    column: $table.ebitda,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get netIncome => $composableBuilder(
    column: $table.netIncome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get incomeBeforeTax => $composableBuilder(
    column: $table.incomeBeforeTax,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get incomeTaxExpense => $composableBuilder(
    column: $table.incomeTaxExpense,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get interestExpense => $composableBuilder(
    column: $table.interestExpense,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get earningsPerShare => $composableBuilder(
    column: $table.earningsPerShare,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cash => $composableBuilder(
    column: $table.cash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get shortTermInvestments => $composableBuilder(
    column: $table.shortTermInvestments,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get shortTermDebt => $composableBuilder(
    column: $table.shortTermDebt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longTermDebt => $composableBuilder(
    column: $table.longTermDebt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalStockholderEquity => $composableBuilder(
    column: $table.totalStockholderEquity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bookValuePerShare => $composableBuilder(
    column: $table.bookValuePerShare,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get operatingCashFlow => $composableBuilder(
    column: $table.operatingCashFlow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get investmentCashFlow => $composableBuilder(
    column: $table.investmentCashFlow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get freeCashFlow => $composableBuilder(
    column: $table.freeCashFlow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get sharesOutstanding => $composableBuilder(
    column: $table.sharesOutstanding,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get sharesOutstandingAsOf => $composableBuilder(
    column: $table.sharesOutstandingAsOf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get marketCap => $composableBuilder(
    column: $table.marketCap,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get enterpriseToEbitda => $composableBuilder(
    column: $table.enterpriseToEbitda,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get nopat => $composableBuilder(
    column: $table.nopat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get propertyPlantEquipment => $composableBuilder(
    column: $table.propertyPlantEquipment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get intangibleAssets => $composableBuilder(
    column: $table.intangibleAssets,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalCurrentAssets => $composableBuilder(
    column: $table.totalCurrentAssets,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get currentLiabilities => $composableBuilder(
    column: $table.currentLiabilities,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get realizedShareCapital => $composableBuilder(
    column: $table.realizedShareCapital,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get profitReserves => $composableBuilder(
    column: $table.profitReserves,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedFundamentalsTableTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CachedFundamentalsTableTable> {
  $$CachedFundamentalsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ticker =>
      $composableBuilder(column: $table.ticker, builder: (column) => column);

  GeneratedColumn<String> get fiscalPeriodEnd => $composableBuilder(
    column: $table.fiscalPeriodEnd,
    builder: (column) => column,
  );

  GeneratedColumn<double> get totalRevenue => $composableBuilder(
    column: $table.totalRevenue,
    builder: (column) => column,
  );

  GeneratedColumn<double> get ebit =>
      $composableBuilder(column: $table.ebit, builder: (column) => column);

  GeneratedColumn<double> get ebitda =>
      $composableBuilder(column: $table.ebitda, builder: (column) => column);

  GeneratedColumn<double> get netIncome =>
      $composableBuilder(column: $table.netIncome, builder: (column) => column);

  GeneratedColumn<double> get incomeBeforeTax => $composableBuilder(
    column: $table.incomeBeforeTax,
    builder: (column) => column,
  );

  GeneratedColumn<double> get incomeTaxExpense => $composableBuilder(
    column: $table.incomeTaxExpense,
    builder: (column) => column,
  );

  GeneratedColumn<double> get interestExpense => $composableBuilder(
    column: $table.interestExpense,
    builder: (column) => column,
  );

  GeneratedColumn<double> get earningsPerShare => $composableBuilder(
    column: $table.earningsPerShare,
    builder: (column) => column,
  );

  GeneratedColumn<double> get cash =>
      $composableBuilder(column: $table.cash, builder: (column) => column);

  GeneratedColumn<double> get shortTermInvestments => $composableBuilder(
    column: $table.shortTermInvestments,
    builder: (column) => column,
  );

  GeneratedColumn<double> get shortTermDebt => $composableBuilder(
    column: $table.shortTermDebt,
    builder: (column) => column,
  );

  GeneratedColumn<double> get longTermDebt => $composableBuilder(
    column: $table.longTermDebt,
    builder: (column) => column,
  );

  GeneratedColumn<double> get totalStockholderEquity => $composableBuilder(
    column: $table.totalStockholderEquity,
    builder: (column) => column,
  );

  GeneratedColumn<double> get bookValuePerShare => $composableBuilder(
    column: $table.bookValuePerShare,
    builder: (column) => column,
  );

  GeneratedColumn<double> get operatingCashFlow => $composableBuilder(
    column: $table.operatingCashFlow,
    builder: (column) => column,
  );

  GeneratedColumn<double> get investmentCashFlow => $composableBuilder(
    column: $table.investmentCashFlow,
    builder: (column) => column,
  );

  GeneratedColumn<double> get freeCashFlow => $composableBuilder(
    column: $table.freeCashFlow,
    builder: (column) => column,
  );

  GeneratedColumn<double> get sharesOutstanding => $composableBuilder(
    column: $table.sharesOutstanding,
    builder: (column) => column,
  );

  GeneratedColumn<double> get sharesOutstandingAsOf => $composableBuilder(
    column: $table.sharesOutstandingAsOf,
    builder: (column) => column,
  );

  GeneratedColumn<double> get marketCap =>
      $composableBuilder(column: $table.marketCap, builder: (column) => column);

  GeneratedColumn<double> get enterpriseToEbitda => $composableBuilder(
    column: $table.enterpriseToEbitda,
    builder: (column) => column,
  );

  GeneratedColumn<double> get nopat =>
      $composableBuilder(column: $table.nopat, builder: (column) => column);

  GeneratedColumn<double> get propertyPlantEquipment => $composableBuilder(
    column: $table.propertyPlantEquipment,
    builder: (column) => column,
  );

  GeneratedColumn<double> get intangibleAssets => $composableBuilder(
    column: $table.intangibleAssets,
    builder: (column) => column,
  );

  GeneratedColumn<double> get totalCurrentAssets => $composableBuilder(
    column: $table.totalCurrentAssets,
    builder: (column) => column,
  );

  GeneratedColumn<double> get currentLiabilities => $composableBuilder(
    column: $table.currentLiabilities,
    builder: (column) => column,
  );

  GeneratedColumn<double> get realizedShareCapital => $composableBuilder(
    column: $table.realizedShareCapital,
    builder: (column) => column,
  );

  GeneratedColumn<double> get profitReserves => $composableBuilder(
    column: $table.profitReserves,
    builder: (column) => column,
  );
}

class $$CachedFundamentalsTableTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CachedFundamentalsTableTable,
          CachedFundamentals,
          $$CachedFundamentalsTableTableFilterComposer,
          $$CachedFundamentalsTableTableOrderingComposer,
          $$CachedFundamentalsTableTableAnnotationComposer,
          $$CachedFundamentalsTableTableCreateCompanionBuilder,
          $$CachedFundamentalsTableTableUpdateCompanionBuilder,
          (
            CachedFundamentals,
            BaseReferences<
              _$CacheDatabase,
              $CachedFundamentalsTableTable,
              CachedFundamentals
            >,
          ),
          CachedFundamentals,
          PrefetchHooks Function()
        > {
  $$CachedFundamentalsTableTableTableManager(
    _$CacheDatabase db,
    $CachedFundamentalsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedFundamentalsTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CachedFundamentalsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedFundamentalsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ticker = const Value.absent(),
                Value<String> fiscalPeriodEnd = const Value.absent(),
                Value<double?> totalRevenue = const Value.absent(),
                Value<double?> ebit = const Value.absent(),
                Value<double?> ebitda = const Value.absent(),
                Value<double?> netIncome = const Value.absent(),
                Value<double?> incomeBeforeTax = const Value.absent(),
                Value<double?> incomeTaxExpense = const Value.absent(),
                Value<double?> interestExpense = const Value.absent(),
                Value<double?> earningsPerShare = const Value.absent(),
                Value<double?> cash = const Value.absent(),
                Value<double?> shortTermInvestments = const Value.absent(),
                Value<double?> shortTermDebt = const Value.absent(),
                Value<double?> longTermDebt = const Value.absent(),
                Value<double?> totalStockholderEquity = const Value.absent(),
                Value<double?> bookValuePerShare = const Value.absent(),
                Value<double?> operatingCashFlow = const Value.absent(),
                Value<double?> investmentCashFlow = const Value.absent(),
                Value<double?> freeCashFlow = const Value.absent(),
                Value<double?> sharesOutstanding = const Value.absent(),
                Value<double?> sharesOutstandingAsOf = const Value.absent(),
                Value<double?> marketCap = const Value.absent(),
                Value<double?> enterpriseToEbitda = const Value.absent(),
                Value<double?> nopat = const Value.absent(),
                Value<double?> propertyPlantEquipment = const Value.absent(),
                Value<double?> intangibleAssets = const Value.absent(),
                Value<double?> totalCurrentAssets = const Value.absent(),
                Value<double?> currentLiabilities = const Value.absent(),
                Value<double?> realizedShareCapital = const Value.absent(),
                Value<double?> profitReserves = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedFundamentalsTableCompanion(
                ticker: ticker,
                fiscalPeriodEnd: fiscalPeriodEnd,
                totalRevenue: totalRevenue,
                ebit: ebit,
                ebitda: ebitda,
                netIncome: netIncome,
                incomeBeforeTax: incomeBeforeTax,
                incomeTaxExpense: incomeTaxExpense,
                interestExpense: interestExpense,
                earningsPerShare: earningsPerShare,
                cash: cash,
                shortTermInvestments: shortTermInvestments,
                shortTermDebt: shortTermDebt,
                longTermDebt: longTermDebt,
                totalStockholderEquity: totalStockholderEquity,
                bookValuePerShare: bookValuePerShare,
                operatingCashFlow: operatingCashFlow,
                investmentCashFlow: investmentCashFlow,
                freeCashFlow: freeCashFlow,
                sharesOutstanding: sharesOutstanding,
                sharesOutstandingAsOf: sharesOutstandingAsOf,
                marketCap: marketCap,
                enterpriseToEbitda: enterpriseToEbitda,
                nopat: nopat,
                propertyPlantEquipment: propertyPlantEquipment,
                intangibleAssets: intangibleAssets,
                totalCurrentAssets: totalCurrentAssets,
                currentLiabilities: currentLiabilities,
                realizedShareCapital: realizedShareCapital,
                profitReserves: profitReserves,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ticker,
                required String fiscalPeriodEnd,
                Value<double?> totalRevenue = const Value.absent(),
                Value<double?> ebit = const Value.absent(),
                Value<double?> ebitda = const Value.absent(),
                Value<double?> netIncome = const Value.absent(),
                Value<double?> incomeBeforeTax = const Value.absent(),
                Value<double?> incomeTaxExpense = const Value.absent(),
                Value<double?> interestExpense = const Value.absent(),
                Value<double?> earningsPerShare = const Value.absent(),
                Value<double?> cash = const Value.absent(),
                Value<double?> shortTermInvestments = const Value.absent(),
                Value<double?> shortTermDebt = const Value.absent(),
                Value<double?> longTermDebt = const Value.absent(),
                Value<double?> totalStockholderEquity = const Value.absent(),
                Value<double?> bookValuePerShare = const Value.absent(),
                Value<double?> operatingCashFlow = const Value.absent(),
                Value<double?> investmentCashFlow = const Value.absent(),
                Value<double?> freeCashFlow = const Value.absent(),
                Value<double?> sharesOutstanding = const Value.absent(),
                Value<double?> sharesOutstandingAsOf = const Value.absent(),
                Value<double?> marketCap = const Value.absent(),
                Value<double?> enterpriseToEbitda = const Value.absent(),
                Value<double?> nopat = const Value.absent(),
                Value<double?> propertyPlantEquipment = const Value.absent(),
                Value<double?> intangibleAssets = const Value.absent(),
                Value<double?> totalCurrentAssets = const Value.absent(),
                Value<double?> currentLiabilities = const Value.absent(),
                Value<double?> realizedShareCapital = const Value.absent(),
                Value<double?> profitReserves = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedFundamentalsTableCompanion.insert(
                ticker: ticker,
                fiscalPeriodEnd: fiscalPeriodEnd,
                totalRevenue: totalRevenue,
                ebit: ebit,
                ebitda: ebitda,
                netIncome: netIncome,
                incomeBeforeTax: incomeBeforeTax,
                incomeTaxExpense: incomeTaxExpense,
                interestExpense: interestExpense,
                earningsPerShare: earningsPerShare,
                cash: cash,
                shortTermInvestments: shortTermInvestments,
                shortTermDebt: shortTermDebt,
                longTermDebt: longTermDebt,
                totalStockholderEquity: totalStockholderEquity,
                bookValuePerShare: bookValuePerShare,
                operatingCashFlow: operatingCashFlow,
                investmentCashFlow: investmentCashFlow,
                freeCashFlow: freeCashFlow,
                sharesOutstanding: sharesOutstanding,
                sharesOutstandingAsOf: sharesOutstandingAsOf,
                marketCap: marketCap,
                enterpriseToEbitda: enterpriseToEbitda,
                nopat: nopat,
                propertyPlantEquipment: propertyPlantEquipment,
                intangibleAssets: intangibleAssets,
                totalCurrentAssets: totalCurrentAssets,
                currentLiabilities: currentLiabilities,
                realizedShareCapital: realizedShareCapital,
                profitReserves: profitReserves,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedFundamentalsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CachedFundamentalsTableTable,
      CachedFundamentals,
      $$CachedFundamentalsTableTableFilterComposer,
      $$CachedFundamentalsTableTableOrderingComposer,
      $$CachedFundamentalsTableTableAnnotationComposer,
      $$CachedFundamentalsTableTableCreateCompanionBuilder,
      $$CachedFundamentalsTableTableUpdateCompanionBuilder,
      (
        CachedFundamentals,
        BaseReferences<
          _$CacheDatabase,
          $CachedFundamentalsTableTable,
          CachedFundamentals
        >,
      ),
      CachedFundamentals,
      PrefetchHooks Function()
    >;
typedef $$CachedProfilesTableCreateCompanionBuilder =
    CachedProfilesCompanion Function({
      required String ticker,
      required String name,
      Value<String?> sectorKey,
      Value<String?> sectorLabel,
      Value<String?> industry,
      Value<int> rowid,
    });
typedef $$CachedProfilesTableUpdateCompanionBuilder =
    CachedProfilesCompanion Function({
      Value<String> ticker,
      Value<String> name,
      Value<String?> sectorKey,
      Value<String?> sectorLabel,
      Value<String?> industry,
      Value<int> rowid,
    });

class $$CachedProfilesTableFilterComposer
    extends Composer<_$CacheDatabase, $CachedProfilesTable> {
  $$CachedProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ticker => $composableBuilder(
    column: $table.ticker,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sectorKey => $composableBuilder(
    column: $table.sectorKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sectorLabel => $composableBuilder(
    column: $table.sectorLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get industry => $composableBuilder(
    column: $table.industry,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedProfilesTableOrderingComposer
    extends Composer<_$CacheDatabase, $CachedProfilesTable> {
  $$CachedProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ticker => $composableBuilder(
    column: $table.ticker,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sectorKey => $composableBuilder(
    column: $table.sectorKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sectorLabel => $composableBuilder(
    column: $table.sectorLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get industry => $composableBuilder(
    column: $table.industry,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedProfilesTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CachedProfilesTable> {
  $$CachedProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ticker =>
      $composableBuilder(column: $table.ticker, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get sectorKey =>
      $composableBuilder(column: $table.sectorKey, builder: (column) => column);

  GeneratedColumn<String> get sectorLabel => $composableBuilder(
    column: $table.sectorLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get industry =>
      $composableBuilder(column: $table.industry, builder: (column) => column);
}

class $$CachedProfilesTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CachedProfilesTable,
          CachedProfile,
          $$CachedProfilesTableFilterComposer,
          $$CachedProfilesTableOrderingComposer,
          $$CachedProfilesTableAnnotationComposer,
          $$CachedProfilesTableCreateCompanionBuilder,
          $$CachedProfilesTableUpdateCompanionBuilder,
          (
            CachedProfile,
            BaseReferences<
              _$CacheDatabase,
              $CachedProfilesTable,
              CachedProfile
            >,
          ),
          CachedProfile,
          PrefetchHooks Function()
        > {
  $$CachedProfilesTableTableManager(
    _$CacheDatabase db,
    $CachedProfilesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ticker = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> sectorKey = const Value.absent(),
                Value<String?> sectorLabel = const Value.absent(),
                Value<String?> industry = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedProfilesCompanion(
                ticker: ticker,
                name: name,
                sectorKey: sectorKey,
                sectorLabel: sectorLabel,
                industry: industry,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ticker,
                required String name,
                Value<String?> sectorKey = const Value.absent(),
                Value<String?> sectorLabel = const Value.absent(),
                Value<String?> industry = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedProfilesCompanion.insert(
                ticker: ticker,
                name: name,
                sectorKey: sectorKey,
                sectorLabel: sectorLabel,
                industry: industry,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CachedProfilesTable,
      CachedProfile,
      $$CachedProfilesTableFilterComposer,
      $$CachedProfilesTableOrderingComposer,
      $$CachedProfilesTableAnnotationComposer,
      $$CachedProfilesTableCreateCompanionBuilder,
      $$CachedProfilesTableUpdateCompanionBuilder,
      (
        CachedProfile,
        BaseReferences<_$CacheDatabase, $CachedProfilesTable, CachedProfile>,
      ),
      CachedProfile,
      PrefetchHooks Function()
    >;
typedef $$CachedMacroRatesTableCreateCompanionBuilder =
    CachedMacroRatesCompanion Function({
      required int seriesId,
      required String date,
      required double value,
      Value<int> rowid,
    });
typedef $$CachedMacroRatesTableUpdateCompanionBuilder =
    CachedMacroRatesCompanion Function({
      Value<int> seriesId,
      Value<String> date,
      Value<double> value,
      Value<int> rowid,
    });

class $$CachedMacroRatesTableFilterComposer
    extends Composer<_$CacheDatabase, $CachedMacroRatesTable> {
  $$CachedMacroRatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedMacroRatesTableOrderingComposer
    extends Composer<_$CacheDatabase, $CachedMacroRatesTable> {
  $$CachedMacroRatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedMacroRatesTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CachedMacroRatesTable> {
  $$CachedMacroRatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<double> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$CachedMacroRatesTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CachedMacroRatesTable,
          CachedMacroRate,
          $$CachedMacroRatesTableFilterComposer,
          $$CachedMacroRatesTableOrderingComposer,
          $$CachedMacroRatesTableAnnotationComposer,
          $$CachedMacroRatesTableCreateCompanionBuilder,
          $$CachedMacroRatesTableUpdateCompanionBuilder,
          (
            CachedMacroRate,
            BaseReferences<
              _$CacheDatabase,
              $CachedMacroRatesTable,
              CachedMacroRate
            >,
          ),
          CachedMacroRate,
          PrefetchHooks Function()
        > {
  $$CachedMacroRatesTableTableManager(
    _$CacheDatabase db,
    $CachedMacroRatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedMacroRatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedMacroRatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedMacroRatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> seriesId = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<double> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedMacroRatesCompanion(
                seriesId: seriesId,
                date: date,
                value: value,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int seriesId,
                required String date,
                required double value,
                Value<int> rowid = const Value.absent(),
              }) => CachedMacroRatesCompanion.insert(
                seriesId: seriesId,
                date: date,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedMacroRatesTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CachedMacroRatesTable,
      CachedMacroRate,
      $$CachedMacroRatesTableFilterComposer,
      $$CachedMacroRatesTableOrderingComposer,
      $$CachedMacroRatesTableAnnotationComposer,
      $$CachedMacroRatesTableCreateCompanionBuilder,
      $$CachedMacroRatesTableUpdateCompanionBuilder,
      (
        CachedMacroRate,
        BaseReferences<
          _$CacheDatabase,
          $CachedMacroRatesTable,
          CachedMacroRate
        >,
      ),
      CachedMacroRate,
      PrefetchHooks Function()
    >;
typedef $$CacheEntriesTableCreateCompanionBuilder =
    CacheEntriesCompanion Function({
      required String key,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$CacheEntriesTableUpdateCompanionBuilder =
    CacheEntriesCompanion Function({
      Value<String> key,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$CacheEntriesTableFilterComposer
    extends Composer<_$CacheDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CacheEntriesTableOrderingComposer
    extends Composer<_$CacheDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CacheEntriesTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$CacheEntriesTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CacheEntriesTable,
          CacheEntry,
          $$CacheEntriesTableFilterComposer,
          $$CacheEntriesTableOrderingComposer,
          $$CacheEntriesTableAnnotationComposer,
          $$CacheEntriesTableCreateCompanionBuilder,
          $$CacheEntriesTableUpdateCompanionBuilder,
          (
            CacheEntry,
            BaseReferences<_$CacheDatabase, $CacheEntriesTable, CacheEntry>,
          ),
          CacheEntry,
          PrefetchHooks Function()
        > {
  $$CacheEntriesTableTableManager(_$CacheDatabase db, $CacheEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CacheEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CacheEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CacheEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CacheEntriesCompanion(
                key: key,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => CacheEntriesCompanion.insert(
                key: key,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CacheEntriesTable,
      CacheEntry,
      $$CacheEntriesTableFilterComposer,
      $$CacheEntriesTableOrderingComposer,
      $$CacheEntriesTableAnnotationComposer,
      $$CacheEntriesTableCreateCompanionBuilder,
      $$CacheEntriesTableUpdateCompanionBuilder,
      (
        CacheEntry,
        BaseReferences<_$CacheDatabase, $CacheEntriesTable, CacheEntry>,
      ),
      CacheEntry,
      PrefetchHooks Function()
    >;

class $CacheDatabaseManager {
  final _$CacheDatabase _db;
  $CacheDatabaseManager(this._db);
  $$CachedPricesTableTableManager get cachedPrices =>
      $$CachedPricesTableTableManager(_db, _db.cachedPrices);
  $$CachedFundamentalsTableTableTableManager get cachedFundamentalsTable =>
      $$CachedFundamentalsTableTableTableManager(
        _db,
        _db.cachedFundamentalsTable,
      );
  $$CachedProfilesTableTableManager get cachedProfiles =>
      $$CachedProfilesTableTableManager(_db, _db.cachedProfiles);
  $$CachedMacroRatesTableTableManager get cachedMacroRates =>
      $$CachedMacroRatesTableTableManager(_db, _db.cachedMacroRates);
  $$CacheEntriesTableTableManager get cacheEntries =>
      $$CacheEntriesTableTableManager(_db, _db.cacheEntries);
}
