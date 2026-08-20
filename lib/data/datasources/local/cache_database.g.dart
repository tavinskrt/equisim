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
  @override
  List<GeneratedColumn> get $columns => [ticker, date, close, adjustedClose];
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
  const CachedPrice({
    required this.ticker,
    required this.date,
    required this.close,
    this.adjustedClose,
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
    };
  }

  CachedPrice copyWith({
    String? ticker,
    String? date,
    double? close,
    Value<double?> adjustedClose = const Value.absent(),
  }) => CachedPrice(
    ticker: ticker ?? this.ticker,
    date: date ?? this.date,
    close: close ?? this.close,
    adjustedClose: adjustedClose.present
        ? adjustedClose.value
        : this.adjustedClose,
  );
  CachedPrice copyWithCompanion(CachedPricesCompanion data) {
    return CachedPrice(
      ticker: data.ticker.present ? data.ticker.value : this.ticker,
      date: data.date.present ? data.date.value : this.date,
      close: data.close.present ? data.close.value : this.close,
      adjustedClose: data.adjustedClose.present
          ? data.adjustedClose.value
          : this.adjustedClose,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedPrice(')
          ..write('ticker: $ticker, ')
          ..write('date: $date, ')
          ..write('close: $close, ')
          ..write('adjustedClose: $adjustedClose')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ticker, date, close, adjustedClose);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedPrice &&
          other.ticker == this.ticker &&
          other.date == this.date &&
          other.close == this.close &&
          other.adjustedClose == this.adjustedClose);
}

class CachedPricesCompanion extends UpdateCompanion<CachedPrice> {
  final Value<String> ticker;
  final Value<String> date;
  final Value<double> close;
  final Value<double?> adjustedClose;
  final Value<int> rowid;
  const CachedPricesCompanion({
    this.ticker = const Value.absent(),
    this.date = const Value.absent(),
    this.close = const Value.absent(),
    this.adjustedClose = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedPricesCompanion.insert({
    required String ticker,
    required String date,
    required double close,
    this.adjustedClose = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ticker = Value(ticker),
       date = Value(date),
       close = Value(close);
  static Insertable<CachedPrice> custom({
    Expression<String>? ticker,
    Expression<String>? date,
    Expression<double>? close,
    Expression<double>? adjustedClose,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ticker != null) 'ticker': ticker,
      if (date != null) 'date': date,
      if (close != null) 'close': close,
      if (adjustedClose != null) 'adjusted_close': adjustedClose,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedPricesCompanion copyWith({
    Value<String>? ticker,
    Value<String>? date,
    Value<double>? close,
    Value<double?>? adjustedClose,
    Value<int>? rowid,
  }) {
    return CachedPricesCompanion(
      ticker: ticker ?? this.ticker,
      date: date ?? this.date,
      close: close ?? this.close,
      adjustedClose: adjustedClose ?? this.adjustedClose,
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
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedDividendsTable extends CachedDividends
    with TableInfo<$CachedDividendsTable, CachedDividend> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedDividendsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tickerMeta = const VerificationMeta('ticker');
  @override
  late final GeneratedColumn<String> ticker = GeneratedColumn<String>(
    'ticker',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exDateMeta = const VerificationMeta('exDate');
  @override
  late final GeneratedColumn<String> exDate = GeneratedColumn<String>(
    'ex_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paymentDateMeta = const VerificationMeta(
    'paymentDate',
  );
  @override
  late final GeneratedColumn<String> paymentDate = GeneratedColumn<String>(
    'payment_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paymentDateEstimatedMeta =
      const VerificationMeta('paymentDateEstimated');
  @override
  late final GeneratedColumn<bool> paymentDateEstimated = GeneratedColumn<bool>(
    'payment_date_estimated',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("payment_date_estimated" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _remarksMeta = const VerificationMeta(
    'remarks',
  );
  @override
  late final GeneratedColumn<String> remarks = GeneratedColumn<String>(
    'remarks',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ticker,
    exDate,
    paymentDate,
    amount,
    label,
    paymentDateEstimated,
    remarks,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_dividends';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedDividend> instance, {
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
    if (data.containsKey('ex_date')) {
      context.handle(
        _exDateMeta,
        exDate.isAcceptableOrUnknown(data['ex_date']!, _exDateMeta),
      );
    } else if (isInserting) {
      context.missing(_exDateMeta);
    }
    if (data.containsKey('payment_date')) {
      context.handle(
        _paymentDateMeta,
        paymentDate.isAcceptableOrUnknown(
          data['payment_date']!,
          _paymentDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_paymentDateMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('payment_date_estimated')) {
      context.handle(
        _paymentDateEstimatedMeta,
        paymentDateEstimated.isAcceptableOrUnknown(
          data['payment_date_estimated']!,
          _paymentDateEstimatedMeta,
        ),
      );
    }
    if (data.containsKey('remarks')) {
      context.handle(
        _remarksMeta,
        remarks.isAcceptableOrUnknown(data['remarks']!, _remarksMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    ticker,
    exDate,
    paymentDate,
    amount,
    label,
  };
  @override
  CachedDividend map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedDividend(
      ticker: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ticker'],
      )!,
      exDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ex_date'],
      )!,
      paymentDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_date'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      paymentDateEstimated: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}payment_date_estimated'],
      )!,
      remarks: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remarks'],
      ),
    );
  }

  @override
  $CachedDividendsTable createAlias(String alias) {
    return $CachedDividendsTable(attachedDatabase, alias);
  }
}

class CachedDividend extends DataClass implements Insertable<CachedDividend> {
  final String ticker;
  final String exDate;
  final String paymentDate;
  final double amount;
  final String label;
  final bool paymentDateEstimated;
  final String? remarks;
  const CachedDividend({
    required this.ticker,
    required this.exDate,
    required this.paymentDate,
    required this.amount,
    required this.label,
    required this.paymentDateEstimated,
    this.remarks,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ticker'] = Variable<String>(ticker);
    map['ex_date'] = Variable<String>(exDate);
    map['payment_date'] = Variable<String>(paymentDate);
    map['amount'] = Variable<double>(amount);
    map['label'] = Variable<String>(label);
    map['payment_date_estimated'] = Variable<bool>(paymentDateEstimated);
    if (!nullToAbsent || remarks != null) {
      map['remarks'] = Variable<String>(remarks);
    }
    return map;
  }

  CachedDividendsCompanion toCompanion(bool nullToAbsent) {
    return CachedDividendsCompanion(
      ticker: Value(ticker),
      exDate: Value(exDate),
      paymentDate: Value(paymentDate),
      amount: Value(amount),
      label: Value(label),
      paymentDateEstimated: Value(paymentDateEstimated),
      remarks: remarks == null && nullToAbsent
          ? const Value.absent()
          : Value(remarks),
    );
  }

  factory CachedDividend.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedDividend(
      ticker: serializer.fromJson<String>(json['ticker']),
      exDate: serializer.fromJson<String>(json['exDate']),
      paymentDate: serializer.fromJson<String>(json['paymentDate']),
      amount: serializer.fromJson<double>(json['amount']),
      label: serializer.fromJson<String>(json['label']),
      paymentDateEstimated: serializer.fromJson<bool>(
        json['paymentDateEstimated'],
      ),
      remarks: serializer.fromJson<String?>(json['remarks']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ticker': serializer.toJson<String>(ticker),
      'exDate': serializer.toJson<String>(exDate),
      'paymentDate': serializer.toJson<String>(paymentDate),
      'amount': serializer.toJson<double>(amount),
      'label': serializer.toJson<String>(label),
      'paymentDateEstimated': serializer.toJson<bool>(paymentDateEstimated),
      'remarks': serializer.toJson<String?>(remarks),
    };
  }

  CachedDividend copyWith({
    String? ticker,
    String? exDate,
    String? paymentDate,
    double? amount,
    String? label,
    bool? paymentDateEstimated,
    Value<String?> remarks = const Value.absent(),
  }) => CachedDividend(
    ticker: ticker ?? this.ticker,
    exDate: exDate ?? this.exDate,
    paymentDate: paymentDate ?? this.paymentDate,
    amount: amount ?? this.amount,
    label: label ?? this.label,
    paymentDateEstimated: paymentDateEstimated ?? this.paymentDateEstimated,
    remarks: remarks.present ? remarks.value : this.remarks,
  );
  CachedDividend copyWithCompanion(CachedDividendsCompanion data) {
    return CachedDividend(
      ticker: data.ticker.present ? data.ticker.value : this.ticker,
      exDate: data.exDate.present ? data.exDate.value : this.exDate,
      paymentDate: data.paymentDate.present
          ? data.paymentDate.value
          : this.paymentDate,
      amount: data.amount.present ? data.amount.value : this.amount,
      label: data.label.present ? data.label.value : this.label,
      paymentDateEstimated: data.paymentDateEstimated.present
          ? data.paymentDateEstimated.value
          : this.paymentDateEstimated,
      remarks: data.remarks.present ? data.remarks.value : this.remarks,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedDividend(')
          ..write('ticker: $ticker, ')
          ..write('exDate: $exDate, ')
          ..write('paymentDate: $paymentDate, ')
          ..write('amount: $amount, ')
          ..write('label: $label, ')
          ..write('paymentDateEstimated: $paymentDateEstimated, ')
          ..write('remarks: $remarks')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ticker,
    exDate,
    paymentDate,
    amount,
    label,
    paymentDateEstimated,
    remarks,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedDividend &&
          other.ticker == this.ticker &&
          other.exDate == this.exDate &&
          other.paymentDate == this.paymentDate &&
          other.amount == this.amount &&
          other.label == this.label &&
          other.paymentDateEstimated == this.paymentDateEstimated &&
          other.remarks == this.remarks);
}

class CachedDividendsCompanion extends UpdateCompanion<CachedDividend> {
  final Value<String> ticker;
  final Value<String> exDate;
  final Value<String> paymentDate;
  final Value<double> amount;
  final Value<String> label;
  final Value<bool> paymentDateEstimated;
  final Value<String?> remarks;
  final Value<int> rowid;
  const CachedDividendsCompanion({
    this.ticker = const Value.absent(),
    this.exDate = const Value.absent(),
    this.paymentDate = const Value.absent(),
    this.amount = const Value.absent(),
    this.label = const Value.absent(),
    this.paymentDateEstimated = const Value.absent(),
    this.remarks = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedDividendsCompanion.insert({
    required String ticker,
    required String exDate,
    required String paymentDate,
    required double amount,
    required String label,
    this.paymentDateEstimated = const Value.absent(),
    this.remarks = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ticker = Value(ticker),
       exDate = Value(exDate),
       paymentDate = Value(paymentDate),
       amount = Value(amount),
       label = Value(label);
  static Insertable<CachedDividend> custom({
    Expression<String>? ticker,
    Expression<String>? exDate,
    Expression<String>? paymentDate,
    Expression<double>? amount,
    Expression<String>? label,
    Expression<bool>? paymentDateEstimated,
    Expression<String>? remarks,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ticker != null) 'ticker': ticker,
      if (exDate != null) 'ex_date': exDate,
      if (paymentDate != null) 'payment_date': paymentDate,
      if (amount != null) 'amount': amount,
      if (label != null) 'label': label,
      if (paymentDateEstimated != null)
        'payment_date_estimated': paymentDateEstimated,
      if (remarks != null) 'remarks': remarks,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedDividendsCompanion copyWith({
    Value<String>? ticker,
    Value<String>? exDate,
    Value<String>? paymentDate,
    Value<double>? amount,
    Value<String>? label,
    Value<bool>? paymentDateEstimated,
    Value<String?>? remarks,
    Value<int>? rowid,
  }) {
    return CachedDividendsCompanion(
      ticker: ticker ?? this.ticker,
      exDate: exDate ?? this.exDate,
      paymentDate: paymentDate ?? this.paymentDate,
      amount: amount ?? this.amount,
      label: label ?? this.label,
      paymentDateEstimated: paymentDateEstimated ?? this.paymentDateEstimated,
      remarks: remarks ?? this.remarks,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ticker.present) {
      map['ticker'] = Variable<String>(ticker.value);
    }
    if (exDate.present) {
      map['ex_date'] = Variable<String>(exDate.value);
    }
    if (paymentDate.present) {
      map['payment_date'] = Variable<String>(paymentDate.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (paymentDateEstimated.present) {
      map['payment_date_estimated'] = Variable<bool>(
        paymentDateEstimated.value,
      );
    }
    if (remarks.present) {
      map['remarks'] = Variable<String>(remarks.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedDividendsCompanion(')
          ..write('ticker: $ticker, ')
          ..write('exDate: $exDate, ')
          ..write('paymentDate: $paymentDate, ')
          ..write('amount: $amount, ')
          ..write('label: $label, ')
          ..write('paymentDateEstimated: $paymentDateEstimated, ')
          ..write('remarks: $remarks, ')
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
    marketCap,
    enterpriseToEbitda,
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
      marketCap: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}market_cap'],
      ),
      enterpriseToEbitda: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}enterprise_to_ebitda'],
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
  final double? marketCap;
  final double? enterpriseToEbitda;
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
    this.marketCap,
    this.enterpriseToEbitda,
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
    if (!nullToAbsent || marketCap != null) {
      map['market_cap'] = Variable<double>(marketCap);
    }
    if (!nullToAbsent || enterpriseToEbitda != null) {
      map['enterprise_to_ebitda'] = Variable<double>(enterpriseToEbitda);
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
      marketCap: marketCap == null && nullToAbsent
          ? const Value.absent()
          : Value(marketCap),
      enterpriseToEbitda: enterpriseToEbitda == null && nullToAbsent
          ? const Value.absent()
          : Value(enterpriseToEbitda),
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
      marketCap: serializer.fromJson<double?>(json['marketCap']),
      enterpriseToEbitda: serializer.fromJson<double?>(
        json['enterpriseToEbitda'],
      ),
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
      'marketCap': serializer.toJson<double?>(marketCap),
      'enterpriseToEbitda': serializer.toJson<double?>(enterpriseToEbitda),
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
    Value<double?> marketCap = const Value.absent(),
    Value<double?> enterpriseToEbitda = const Value.absent(),
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
    marketCap: marketCap.present ? marketCap.value : this.marketCap,
    enterpriseToEbitda: enterpriseToEbitda.present
        ? enterpriseToEbitda.value
        : this.enterpriseToEbitda,
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
      marketCap: data.marketCap.present ? data.marketCap.value : this.marketCap,
      enterpriseToEbitda: data.enterpriseToEbitda.present
          ? data.enterpriseToEbitda.value
          : this.enterpriseToEbitda,
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
          ..write('marketCap: $marketCap, ')
          ..write('enterpriseToEbitda: $enterpriseToEbitda')
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
    marketCap,
    enterpriseToEbitda,
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
          other.marketCap == this.marketCap &&
          other.enterpriseToEbitda == this.enterpriseToEbitda);
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
  final Value<double?> marketCap;
  final Value<double?> enterpriseToEbitda;
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
    this.marketCap = const Value.absent(),
    this.enterpriseToEbitda = const Value.absent(),
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
    this.marketCap = const Value.absent(),
    this.enterpriseToEbitda = const Value.absent(),
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
    Expression<double>? marketCap,
    Expression<double>? enterpriseToEbitda,
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
      if (marketCap != null) 'market_cap': marketCap,
      if (enterpriseToEbitda != null)
        'enterprise_to_ebitda': enterpriseToEbitda,
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
    Value<double?>? marketCap,
    Value<double?>? enterpriseToEbitda,
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
      marketCap: marketCap ?? this.marketCap,
      enterpriseToEbitda: enterpriseToEbitda ?? this.enterpriseToEbitda,
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
    if (marketCap.present) {
      map['market_cap'] = Variable<double>(marketCap.value);
    }
    if (enterpriseToEbitda.present) {
      map['enterprise_to_ebitda'] = Variable<double>(enterpriseToEbitda.value);
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
          ..write('marketCap: $marketCap, ')
          ..write('enterpriseToEbitda: $enterpriseToEbitda, ')
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
  static const VerificationMeta _publishedDividendYieldMeta =
      const VerificationMeta('publishedDividendYield');
  @override
  late final GeneratedColumn<double> publishedDividendYield =
      GeneratedColumn<double>(
        'published_dividend_yield',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    ticker,
    name,
    sectorKey,
    sectorLabel,
    industry,
    publishedDividendYield,
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
    if (data.containsKey('published_dividend_yield')) {
      context.handle(
        _publishedDividendYieldMeta,
        publishedDividendYield.isAcceptableOrUnknown(
          data['published_dividend_yield']!,
          _publishedDividendYieldMeta,
        ),
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
      publishedDividendYield: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}published_dividend_yield'],
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

  /// Dividend yield 12m publicado pela fonte — insumo do portão de qualidade.
  final double? publishedDividendYield;
  const CachedProfile({
    required this.ticker,
    required this.name,
    this.sectorKey,
    this.sectorLabel,
    this.industry,
    this.publishedDividendYield,
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
    if (!nullToAbsent || publishedDividendYield != null) {
      map['published_dividend_yield'] = Variable<double>(
        publishedDividendYield,
      );
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
      publishedDividendYield: publishedDividendYield == null && nullToAbsent
          ? const Value.absent()
          : Value(publishedDividendYield),
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
      publishedDividendYield: serializer.fromJson<double?>(
        json['publishedDividendYield'],
      ),
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
      'publishedDividendYield': serializer.toJson<double?>(
        publishedDividendYield,
      ),
    };
  }

  CachedProfile copyWith({
    String? ticker,
    String? name,
    Value<String?> sectorKey = const Value.absent(),
    Value<String?> sectorLabel = const Value.absent(),
    Value<String?> industry = const Value.absent(),
    Value<double?> publishedDividendYield = const Value.absent(),
  }) => CachedProfile(
    ticker: ticker ?? this.ticker,
    name: name ?? this.name,
    sectorKey: sectorKey.present ? sectorKey.value : this.sectorKey,
    sectorLabel: sectorLabel.present ? sectorLabel.value : this.sectorLabel,
    industry: industry.present ? industry.value : this.industry,
    publishedDividendYield: publishedDividendYield.present
        ? publishedDividendYield.value
        : this.publishedDividendYield,
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
      publishedDividendYield: data.publishedDividendYield.present
          ? data.publishedDividendYield.value
          : this.publishedDividendYield,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedProfile(')
          ..write('ticker: $ticker, ')
          ..write('name: $name, ')
          ..write('sectorKey: $sectorKey, ')
          ..write('sectorLabel: $sectorLabel, ')
          ..write('industry: $industry, ')
          ..write('publishedDividendYield: $publishedDividendYield')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ticker,
    name,
    sectorKey,
    sectorLabel,
    industry,
    publishedDividendYield,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedProfile &&
          other.ticker == this.ticker &&
          other.name == this.name &&
          other.sectorKey == this.sectorKey &&
          other.sectorLabel == this.sectorLabel &&
          other.industry == this.industry &&
          other.publishedDividendYield == this.publishedDividendYield);
}

class CachedProfilesCompanion extends UpdateCompanion<CachedProfile> {
  final Value<String> ticker;
  final Value<String> name;
  final Value<String?> sectorKey;
  final Value<String?> sectorLabel;
  final Value<String?> industry;
  final Value<double?> publishedDividendYield;
  final Value<int> rowid;
  const CachedProfilesCompanion({
    this.ticker = const Value.absent(),
    this.name = const Value.absent(),
    this.sectorKey = const Value.absent(),
    this.sectorLabel = const Value.absent(),
    this.industry = const Value.absent(),
    this.publishedDividendYield = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedProfilesCompanion.insert({
    required String ticker,
    required String name,
    this.sectorKey = const Value.absent(),
    this.sectorLabel = const Value.absent(),
    this.industry = const Value.absent(),
    this.publishedDividendYield = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ticker = Value(ticker),
       name = Value(name);
  static Insertable<CachedProfile> custom({
    Expression<String>? ticker,
    Expression<String>? name,
    Expression<String>? sectorKey,
    Expression<String>? sectorLabel,
    Expression<String>? industry,
    Expression<double>? publishedDividendYield,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ticker != null) 'ticker': ticker,
      if (name != null) 'name': name,
      if (sectorKey != null) 'sector_key': sectorKey,
      if (sectorLabel != null) 'sector_label': sectorLabel,
      if (industry != null) 'industry': industry,
      if (publishedDividendYield != null)
        'published_dividend_yield': publishedDividendYield,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedProfilesCompanion copyWith({
    Value<String>? ticker,
    Value<String>? name,
    Value<String?>? sectorKey,
    Value<String?>? sectorLabel,
    Value<String?>? industry,
    Value<double?>? publishedDividendYield,
    Value<int>? rowid,
  }) {
    return CachedProfilesCompanion(
      ticker: ticker ?? this.ticker,
      name: name ?? this.name,
      sectorKey: sectorKey ?? this.sectorKey,
      sectorLabel: sectorLabel ?? this.sectorLabel,
      industry: industry ?? this.industry,
      publishedDividendYield:
          publishedDividendYield ?? this.publishedDividendYield,
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
    if (publishedDividendYield.present) {
      map['published_dividend_yield'] = Variable<double>(
        publishedDividendYield.value,
      );
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
          ..write('publishedDividendYield: $publishedDividendYield, ')
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
  late final $CachedDividendsTable cachedDividends = $CachedDividendsTable(
    this,
  );
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
    cachedDividends,
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
      Value<int> rowid,
    });
typedef $$CachedPricesTableUpdateCompanionBuilder =
    CachedPricesCompanion Function({
      Value<String> ticker,
      Value<String> date,
      Value<double> close,
      Value<double?> adjustedClose,
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
                Value<int> rowid = const Value.absent(),
              }) => CachedPricesCompanion(
                ticker: ticker,
                date: date,
                close: close,
                adjustedClose: adjustedClose,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ticker,
                required String date,
                required double close,
                Value<double?> adjustedClose = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedPricesCompanion.insert(
                ticker: ticker,
                date: date,
                close: close,
                adjustedClose: adjustedClose,
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
typedef $$CachedDividendsTableCreateCompanionBuilder =
    CachedDividendsCompanion Function({
      required String ticker,
      required String exDate,
      required String paymentDate,
      required double amount,
      required String label,
      Value<bool> paymentDateEstimated,
      Value<String?> remarks,
      Value<int> rowid,
    });
typedef $$CachedDividendsTableUpdateCompanionBuilder =
    CachedDividendsCompanion Function({
      Value<String> ticker,
      Value<String> exDate,
      Value<String> paymentDate,
      Value<double> amount,
      Value<String> label,
      Value<bool> paymentDateEstimated,
      Value<String?> remarks,
      Value<int> rowid,
    });

class $$CachedDividendsTableFilterComposer
    extends Composer<_$CacheDatabase, $CachedDividendsTable> {
  $$CachedDividendsTableFilterComposer({
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

  ColumnFilters<String> get exDate => $composableBuilder(
    column: $table.exDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentDate => $composableBuilder(
    column: $table.paymentDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get paymentDateEstimated => $composableBuilder(
    column: $table.paymentDateEstimated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remarks => $composableBuilder(
    column: $table.remarks,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedDividendsTableOrderingComposer
    extends Composer<_$CacheDatabase, $CachedDividendsTable> {
  $$CachedDividendsTableOrderingComposer({
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

  ColumnOrderings<String> get exDate => $composableBuilder(
    column: $table.exDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentDate => $composableBuilder(
    column: $table.paymentDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get paymentDateEstimated => $composableBuilder(
    column: $table.paymentDateEstimated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remarks => $composableBuilder(
    column: $table.remarks,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedDividendsTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CachedDividendsTable> {
  $$CachedDividendsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ticker =>
      $composableBuilder(column: $table.ticker, builder: (column) => column);

  GeneratedColumn<String> get exDate =>
      $composableBuilder(column: $table.exDate, builder: (column) => column);

  GeneratedColumn<String> get paymentDate => $composableBuilder(
    column: $table.paymentDate,
    builder: (column) => column,
  );

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<bool> get paymentDateEstimated => $composableBuilder(
    column: $table.paymentDateEstimated,
    builder: (column) => column,
  );

  GeneratedColumn<String> get remarks =>
      $composableBuilder(column: $table.remarks, builder: (column) => column);
}

class $$CachedDividendsTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CachedDividendsTable,
          CachedDividend,
          $$CachedDividendsTableFilterComposer,
          $$CachedDividendsTableOrderingComposer,
          $$CachedDividendsTableAnnotationComposer,
          $$CachedDividendsTableCreateCompanionBuilder,
          $$CachedDividendsTableUpdateCompanionBuilder,
          (
            CachedDividend,
            BaseReferences<
              _$CacheDatabase,
              $CachedDividendsTable,
              CachedDividend
            >,
          ),
          CachedDividend,
          PrefetchHooks Function()
        > {
  $$CachedDividendsTableTableManager(
    _$CacheDatabase db,
    $CachedDividendsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedDividendsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedDividendsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedDividendsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ticker = const Value.absent(),
                Value<String> exDate = const Value.absent(),
                Value<String> paymentDate = const Value.absent(),
                Value<double> amount = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<bool> paymentDateEstimated = const Value.absent(),
                Value<String?> remarks = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedDividendsCompanion(
                ticker: ticker,
                exDate: exDate,
                paymentDate: paymentDate,
                amount: amount,
                label: label,
                paymentDateEstimated: paymentDateEstimated,
                remarks: remarks,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ticker,
                required String exDate,
                required String paymentDate,
                required double amount,
                required String label,
                Value<bool> paymentDateEstimated = const Value.absent(),
                Value<String?> remarks = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedDividendsCompanion.insert(
                ticker: ticker,
                exDate: exDate,
                paymentDate: paymentDate,
                amount: amount,
                label: label,
                paymentDateEstimated: paymentDateEstimated,
                remarks: remarks,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedDividendsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CachedDividendsTable,
      CachedDividend,
      $$CachedDividendsTableFilterComposer,
      $$CachedDividendsTableOrderingComposer,
      $$CachedDividendsTableAnnotationComposer,
      $$CachedDividendsTableCreateCompanionBuilder,
      $$CachedDividendsTableUpdateCompanionBuilder,
      (
        CachedDividend,
        BaseReferences<_$CacheDatabase, $CachedDividendsTable, CachedDividend>,
      ),
      CachedDividend,
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
      Value<double?> marketCap,
      Value<double?> enterpriseToEbitda,
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
      Value<double?> marketCap,
      Value<double?> enterpriseToEbitda,
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

  ColumnFilters<double> get marketCap => $composableBuilder(
    column: $table.marketCap,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get enterpriseToEbitda => $composableBuilder(
    column: $table.enterpriseToEbitda,
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

  ColumnOrderings<double> get marketCap => $composableBuilder(
    column: $table.marketCap,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get enterpriseToEbitda => $composableBuilder(
    column: $table.enterpriseToEbitda,
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

  GeneratedColumn<double> get marketCap =>
      $composableBuilder(column: $table.marketCap, builder: (column) => column);

  GeneratedColumn<double> get enterpriseToEbitda => $composableBuilder(
    column: $table.enterpriseToEbitda,
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
                Value<double?> marketCap = const Value.absent(),
                Value<double?> enterpriseToEbitda = const Value.absent(),
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
                marketCap: marketCap,
                enterpriseToEbitda: enterpriseToEbitda,
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
                Value<double?> marketCap = const Value.absent(),
                Value<double?> enterpriseToEbitda = const Value.absent(),
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
                marketCap: marketCap,
                enterpriseToEbitda: enterpriseToEbitda,
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
      Value<double?> publishedDividendYield,
      Value<int> rowid,
    });
typedef $$CachedProfilesTableUpdateCompanionBuilder =
    CachedProfilesCompanion Function({
      Value<String> ticker,
      Value<String> name,
      Value<String?> sectorKey,
      Value<String?> sectorLabel,
      Value<String?> industry,
      Value<double?> publishedDividendYield,
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

  ColumnFilters<double> get publishedDividendYield => $composableBuilder(
    column: $table.publishedDividendYield,
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

  ColumnOrderings<double> get publishedDividendYield => $composableBuilder(
    column: $table.publishedDividendYield,
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

  GeneratedColumn<double> get publishedDividendYield => $composableBuilder(
    column: $table.publishedDividendYield,
    builder: (column) => column,
  );
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
                Value<double?> publishedDividendYield = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedProfilesCompanion(
                ticker: ticker,
                name: name,
                sectorKey: sectorKey,
                sectorLabel: sectorLabel,
                industry: industry,
                publishedDividendYield: publishedDividendYield,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ticker,
                required String name,
                Value<String?> sectorKey = const Value.absent(),
                Value<String?> sectorLabel = const Value.absent(),
                Value<String?> industry = const Value.absent(),
                Value<double?> publishedDividendYield = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedProfilesCompanion.insert(
                ticker: ticker,
                name: name,
                sectorKey: sectorKey,
                sectorLabel: sectorLabel,
                industry: industry,
                publishedDividendYield: publishedDividendYield,
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
  $$CachedDividendsTableTableManager get cachedDividends =>
      $$CachedDividendsTableTableManager(_db, _db.cachedDividends);
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
