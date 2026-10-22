// As companhias deslistadas, prontas para entrar nas coortes (item C1b).
//
// Tudo o que o A3.4 deixou em `data/b3/deslistadas_contagem.json` — contagem de
// ações por data, eventos localizados no preço, eventos não localizados e
// proventos —, mais o fechamento e o volume do COTAHIST filtrados pelo ISIN do
// papel, os documentos da CVM pelo CNPJ e o setor: o da B3, quando o portal
// responde para a companhia, e o representante do setor de atividade da FCA
// (`setor_cvm.dart`) quando não responde.
//
// **Uma coorte vê só o que existia na data dela.** O preço é ajustado pelos
// eventos com data ex até o fim da janela pedida, e não pelos posteriores; a
// contagem é a vigente na data; a CVM é a recebida até ali.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import '../b3/proventos.dart';
import '../cvm/documentos.dart';
import '../cvm/setor_cvm.dart';
import 'base_da_data.dart';
import 'contagem_conferida.dart';

/// Um papel de companhia deslistada.
class DelistedSecurity {
  final Ticker ticker;
  final String cnpj;
  final String name;

  /// Pregões brutos do COTAHIST, com volume financeiro.
  final List<TradingDay> tradingDays;

  /// Eventos localizados no preço e inferidos, um por data ex.
  final List<ShareEvent> events;

  /// Aprovações de evento declarado com pregão e sem data ex no preço.
  final List<DateTime> notLocated;

  /// Contagem total de ações, em ordem de vigência.
  final List<({DateTime since, double shares})> count;

  /// Proventos da classe do papel.
  final List<CashDividend> dividends;

  final B3Classification? classification;

  /// `b3`, `cvm` ou `nenhuma`.
  final String sectorOrigin;

  /// Divisão do capital entre ordinárias e preferenciais (item C3).
  final CapitalClasses classes;

  DelistedSecurity({
    required this.ticker,
    required this.cnpj,
    required this.name,
    required this.tradingDays,
    required this.events,
    required this.notLocated,
    required this.count,
    required this.dividends,
    required this.classification,
    required this.sectorOrigin,
    required this.classes,
  });

  /// Contagem vigente em [date], ou `null` antes do primeiro ponto.
  double? sharesAt(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    double? last;
    for (final p in count) {
      if (p.since.isAfter(day)) break;
      last = p.shares;
    }
    return last;
  }

  /// Série de preço na base de [until]: eventos com data ex depois dele não
  /// ajustam, porque não tinham acontecido. O volume vira ações, para que
  /// `fechamento × volume` continue sendo o financeiro do dia.
  PriceSeries series(DateRange window, {required DateTime until}) {
    final end = DateTime.utc(until.year, until.month, until.day);
    final eventsUntil = [
      for (final e in events)
        if (!e.exDate.isAfter(end)) e,
    ];
    final points = <PricePoint>[];
    for (final p in tradingDays) {
      if (!window.contains(p.date)) continue;
      var c = p.close;
      for (final e in eventsUntil) {
        if (p.date.isBefore(e.exDate)) c /= e.factor;
      }
      final fin = p.tradedValue;
      points.add(
        PricePoint(
          date: p.date,
          close: c,
          volume: (fin == null || c <= 0) ? null : fin / c,
        ),
      );
    }
    return PriceSeries(ticker: ticker, points: points);
  }

  /// Maior razão entre pregões vizinhos que a série ajustada ainda pode ter
  /// sem ser tratada como evento que escapou.
  static const double maxJump = 3.0;

  /// Distância máxima, em dias corridos, entre os dois pregões do salto: além
  /// disso é suspensão, e o preço de volta é o que o papel passou a valer.
  static const int jumpDays = 90;

  /// Pregões em que a série **já ajustada** muda mais de [maxJump] vezes
  /// em relação ao pregão anterior, a até [jumpDays] dias dele.
  ///
  /// São os eventos que o FRE não declarou e o preço não permitiu inferir —
  /// o grupamento de 2024 da KRSA3 e da NGRD3, a TOYB3 dividida por 270 mil
  /// em 2015 —, e a série não está ajustada por eles. O ajuste divide todos os
  /// pregões antes da data ex pelo mesmo fator, então a razão entre vizinhos
  /// não depende da base: a lista vale para qualquer data de coorte.
  late final List<DateTime> jumps = () {
    final s = series(
      DateRange(DateTime.utc(1990), DateTime.utc(2100)),
      until: DateTime.utc(2100),
    ).points;
    return [
      for (var i = 1; i < s.length; i++)
        if (s[i - 1].close > 0 &&
            s[i].close > 0 &&
            s[i].date.difference(s[i - 1].date).inDays <= jumpDays &&
            (math.log(s[i].close / s[i - 1].close)).abs() >
                math.log(maxJump))
          s[i].date,
    ];
  }();

  /// `true` quando algum evento não localizado cai em `[de, ate]`.
  bool eventNotLocatedBetween(DateTime from, DateTime until) =>
      notLocated.any((d) => !d.isBefore(from) && !d.isAfter(until));

  /// `true` quando `(de, ate]` atravessa evento não localizado ou salto: a
  /// série não estaria ajustada por ele, e a janela sai.
  bool suspiciousWindow(DateTime from, DateTime until) =>
      eventNotLocatedBetween(from, until) ||
      jumps.any((d) => d.isAfter(from) && !d.isAfter(until));
}

class Delisted {
  Delisted._(
    this.securities,
    this.documents,
    this.cvmSector,
    this.discardedCounts,
  );

  /// Entradas da contagem descartadas pela conferência contra o salto do preço
  /// (item B43), somadas nas companhias.
  final int discardedCounts;

  final Map<String, DelistedSecurity> securities;

  /// Papéis de cada companhia, para o valor de mercado espécie a espécie.
  late final Map<String, List<DelistedSecurity>> byCnpj = () {
    final out = <String, List<DelistedSecurity>>{};
    for (final p in securities.values) {
      (out[p.cnpj] ??= []).add(p);
    }
    return out;
  }();

  /// Valor de mercado da companhia de [security] em [date], com os papéis dela e a
  /// contagem da data (item C3). `null` sem contagem ou sem papel de espécie
  /// negociando.
  MarketValue? marketValueOf(DelistedSecurity security, DateTime date) {
    final shares = security.sharesAt(date);
    if (shares == null) return null;
    return MarketValue.atDate(
      shares: shares,
      commonFraction: security.classes.at(date),
      securities: {
        for (final p in byCnpj[security.cnpj] ?? [security])
          p.ticker.value: p.tradingDays,
      },
      date: date,
    );
  }

  /// Documentos da CVM por ticker de deslistada.
  final Map<String, List<CvmPeriodDocument>> documents;

  final CvmSector? cvmSector;

  static DateTime _day(String s) =>
      DateTime.parse('${s.substring(0, 10)}T00:00:00Z');

  /// Lê as deslistadas. `null` sem os arquivos do A3.4.
  ///
  /// - [listedClassification]: CNPJ da listada → classificação da B3, para
  ///   medir o setor da CVM.
  ///
  /// - [until]: a data de corte da conferência da contagem (item B43) — a âncora
  ///   é a contagem mais recente até ela.
  static Delisted? read(
    Map<String, B3Classification> listedClassification, {
    required DateTime until,
  }) {
    final bridgeFile = File('data/b3/ponte_deslistadas.json');
    final countFile = File('data/b3/deslistadas_contagem.json');
    if (!bridgeFile.existsSync() || !countFile.existsSync()) return null;
    final bridge =
        (jsonDecode(bridgeFile.readAsStringSync()) as Map<String, dynamic>)
            .cast<String, Map<String, dynamic>>();
    final a34 =
        (jsonDecode(countFile.readAsStringSync()) as Map<String, dynamic>)
            .cast<String, Map<String, dynamic>>();
    final cvmSector = CvmSector.read(listedClassification);

    final isins = <String, String>{};
    final tickersByCnpj = <String, List<String>>{};
    for (final e in bridge.entries) {
      final securities = (e.value['papeis'] as Map<String, dynamic>);
      for (final p in securities.entries) {
        if (Ticker.tryParse(p.key) == null) continue;
        isins[p.key] = (p.value as Map<String, dynamic>)['isin'] as String;
        (tickersByCnpj[e.key] ??= []).add(p.key);
      }
    }
    final cotahist = readRawCotahist(isins.keys.toSet(), isins: isins);
    final documents = loadDocuments(
      'data/cvm_exercicios.json',
      onlyTickers: isins.keys.toSet(),
      tickersByCnpj: tickersByCnpj,
      withOldVersions: true,
    );

    final securities = <String, DelistedSecurity>{};
    var discarded = 0;
    for (final e in tickersByCnpj.entries) {
      final cnpj = e.key;
      final registry = a34[cnpj];
      if (registry == null) continue;
      // A contagem do formulário conferida contra o salto do preço dos papéis
      // da companhia (item B43, decisão 143): a correção que repete a contagem
      // de antes de um grupamento sai.
      final checked = checkCount(
        [
          for (final p
              in (registry['contagem'] as List).cast<Map<String, dynamic>>())
            (
              since: _day(p['desde'] as String),
              shares: (p['acoes'] as num).toDouble(),
              source: p['fonte'] as String?,
            ),
        ],
        [
          for (final t in e.value)
            if (cotahist[t] case final s? when s.length > 1) s,
        ],
        until: until,
      );
      discarded += checked.discarded.length;
      final count = checked.accepted;
      if (count.isEmpty) continue;

      final file = File(
        'data/b3/complemento_deslistadas/'
        '${cnpj.replaceAll(RegExp(r'[./-]'), '')}.json',
      );
      final supplement = file.existsSync()
          ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
          : const <String, dynamic>{};
      final fromB3 = B3Classification.parse(
        (supplement['detalhe']
            as Map<String, dynamic>?)?['industryClassification'],
      );
      final fromCvm = fromB3 == null ? cvmSector?.classificationOf(cnpj) : null;

      for (final t in e.value) {
        final data =
            (registry['papeis'] as Map<String, dynamic>)[t]
                as Map<String, dynamic>?;
        final tradingDays = cotahist[t];
        if (data == null || tradingDays == null || tradingDays.length < 2) continue;

        // Eventos de mesma data ex: fica o que o preço observado explica.
        final byDate = <DateTime, List<double>>{};
        for (final ev
            in (data['eventos'] as List).cast<Map<String, dynamic>>()) {
          (byDate[_day(ev['dataEx'] as String)] ??= []).add(
            (ev['fator'] as num).toDouble(),
          );
        }
        final events = <ShareEvent>[];
        for (final d in byDate.entries) {
          final observed = _ratioAtDate(tradingDays, d.key);
          var best = d.value.first;
          if (d.value.length > 1 && observed != null) {
            for (final f in d.value) {
              if ((math.log(f) - math.log(observed)).abs() <
                  (math.log(best) - math.log(observed)).abs()) {
                best = f;
              }
            }
          }
          events.add(
            ShareEvent(
              exDate: d.key,
              factor: best,
              observedRatio: observed ?? best,
            ),
          );
        }
        events.sort((a, b) => a.exDate.compareTo(b.exDate));

        final shareClass = B3CashDividends.shareClassOf(t);
        final dividends = <CashDividend>[
          for (final p
              in (data['proventos'] as List).cast<Map<String, dynamic>>())
            if (shareClass != null)
              CashDividend(
                shareClass: shareClass,
                kind: CashDividendKind.fromKey(p['tipo'] as String),
                // A data com é o pregão anterior à ex; a conta do retorno total
                // só usa a data ex e o preço com direito.
                lastDateWithRights: _day(
                  p['dataEx'] as String,
                ).subtract(const Duration(days: 1)),
                exDate: _day(p['dataEx'] as String),
                amount: (p['valor'] as num).toDouble(),
                closeWithRights: (p['precoComDireito'] as num?)?.toDouble(),
              ),
        ];

        securities[t] = DelistedSecurity(
          ticker: Ticker.parse(t),
          cnpj: cnpj,
          name: (bridge[cnpj]?['nome'] as String?) ?? t,
          tradingDays: tradingDays,
          events: events,
          notLocated: [
            for (final d
                in (data['eventosNaoLocalizados'] as List).cast<String>())
              _day(d),
          ],
          count: count,
          dividends: dividends,
          classification: fromB3 ?? fromCvm,
          sectorOrigin: fromB3 != null
              ? 'b3'
              : (fromCvm != null ? 'cvm' : 'nenhuma'),
          classes: CapitalClasses.fromJson(registry['classes'] as List?),
        );
      }
    }
    return Delisted._(securities, documents, cvmSector, discarded);
  }

  /// `P_anterior / P_ex` na data ex: o fator que o preço observou.
  static double? _ratioAtDate(List<TradingDay> s, DateTime ex) {
    for (var i = 1; i < s.length; i++) {
      if (s[i].date.isAtSameMomentAs(ex)) {
        final a = s[i - 1].close, b = s[i].close;
        return (a > 0 && b > 0) ? a / b : null;
      }
    }
    return null;
  }
}

/// Fundamentos de uma deslistada numa data de coorte.
///
/// A CVM dá as demonstrações; o que ela não dá — valor de mercado e contagem,
/// que a decisão 70 manda nunca tirar dela — vem de exercícios de mercado
/// sintéticos, um por DFP recebida até a data: a contagem do FRE no fim do
/// exercício, a contagem vigente na data e o valor de mercado da companhia na
/// data. É a mesma reconstrução que a coorte faz com as listadas, cuja fonte
/// repete o valor de mercado de hoje em todo exercício.
///
/// **O valor de mercado é o da companhia, espécie a espécie** (item C3), e não
/// `contagem × preço do papel`, que dava razão de unidade 1 por construção. Sem
/// ele, recua para o produto.
class DelistedFundamentals implements FundamentalsRepository {
  DelistedFundamentals(
    this.security,
    this.documents,
    this.date,
    this.price, {
    this.marketValueOf,
    this.anchored = false,
  });

  final DelistedSecurity security;
  final List<CvmPeriodDocument> documents;
  final DateTime date;

  /// Fechamento bruto do papel na data.
  final double price;

  /// Valor de mercado da companhia na data, de [Delisted.marketValueOf].
  final double? marketValueOf;

  /// Série de doze meses ancorada no trimestre (item C1c), ou a de DFPs.
  final bool anchored;

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async {
    final published = PointInTimeView(date).isPublished;
    final today = security.sharesAt(date);
    if (today == null || today <= 0) {
      return Err(
        InsufficientData(
          'sem contagem de ${t.value} na data',
          subject: t.value,
        ),
      );
    }
    final market = <FundamentalsSnapshot>[
      for (final d in CvmSeries.inForceAt(documents, published))
        if (d.kind == CvmDocumentKind.dfp)
          FundamentalsSnapshot(
            ticker: t,
            fiscalPeriodEnd: d.periodEnd,
            sharesOutstanding: today,
            sharesOutstandingAsOf: security.sharesAt(d.periodEnd),
            marketCap: marketValueOf ?? today * price,
          ),
    ];
    return Ok(
      CvmSeries.build(
        documents: documents,
        market: market,
        published: published,
        anchored: anchored,
      ).series,
    );
  }

  @override
  Future<Result<Asset>> profile(Ticker t) async {
    final c = security.classification;
    return Ok(
      Asset(
        ticker: t,
        name: security.name,
        sector: c == null
            ? Sector.fromKey('', label: '')
            : Sector(key: c.sectorKey, label: c.sector),
        industry: (c == null || c.industry.isEmpty) ? null : c.industry,
      ),
    );
  }

  @override
  Future<Result<List<Ticker>>> universe() async => const Ok([]);
}

/// Preços de uma deslistada, na base da data da coorte.
class DelistedPrices implements PriceRepository {
  DelistedPrices(this.security, this.until);

  final DelistedSecurity security;
  final DateTime until;

  @override
  Future<Result<PriceSeries>> daily(Ticker t, DateRange range) async =>
      Ok(security.series(range, until: until));

  @override
  Future<Result<Map<Ticker, PriceSeries>>> dailyBatch(
    List<Ticker> tickers,
    DateRange range,
  ) async => Ok({for (final t in tickers) t: security.series(range, until: until)});

  @override
  Future<Result<PriceSeries>> adjustedCloseRaw(Ticker t, DateRange range) =>
      daily(t, range);
}
