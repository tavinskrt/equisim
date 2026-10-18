// Leitores compartilhados dos itens A4 e A3.4: proventos da B3 e fechamento
// bruto do COTAHIST, para `proventos_conferir.dart`, `backtest_valuation.dart`
// e `b3_deslistadas_contagem.dart`.
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

/// Proventos por emissor de quatro letras, de `data/b3/complemento/`.
Map<String, List<CashDividend>> readDividends({String dir = 'data/b3/complemento'}) {
  final folder = Directory(dir);
  if (!folder.existsSync()) {
    stderr.writeln('sem $dir — rode: python tool/b3_complemento_baixar.py');
    exit(2);
  }
  final out = <String, List<CashDividend>>{};
  for (final f in folder.listSync().whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final issuer = f.uri.pathSegments.last.replaceAll('.json', '');
    out[issuer] = B3CashDividends.parse(
        (raw['proventos'] as List?)?.cast<Object?>() ?? const []);
  }
  return out;
}

/// Os proventos da classe de [ticker], ou lista vazia.
List<CashDividend> dividendsOf(
    Map<String, List<CashDividend>> dividends, String ticker) {
  return CashDividendsCodec.forTicker(dividends, ticker);
}

/// Um pregão do COTAHIST: fechamento bruto por ação e número de distribuição.
class TradingDay {
  final DateTime date;
  final double close;
  final int distribution;

  /// Volume financeiro do dia, em reais. `null` quando o arquivo não o traz.
  final double? tradedValue;
  const TradingDay(this.date, this.close, this.distribution, [this.tradedValue]);

  RawQuote get raw => RawQuote(date, close, distribution);
}

/// Fechamento **bruto por ação** do COTAHIST, por ticker, em ordem de data.
///
/// O CSV compacto guarda o fechamento em centavos por lote de `fatorCotacao`
/// ações, e o volume financeiro em centavos; aqui saem em reais.
///
/// - [isins]: quando dado, só entra o pregão do ISIN do ticker. Um ticker pode
///   ter sido de mais de um papel ao longo dos anos.
Map<String, List<TradingDay>> readRawCotahist(Set<String> tickers,
    {Map<String, String>? isins}) {
  final out = <String, List<TradingDay>>{};
  final files = Directory('data/b3')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'avista_\d{4}\.csv$').hasMatch(f.path))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    var header = true;
    for (final row in f.readAsLinesSync()) {
      if (header) {
        header = false;
        continue;
      }
      final c = row.split(';');
      if (c.length < 8 || !tickers.contains(c[1])) continue;
      final isin = isins?[c[1]];
      if (isin != null && c[2] != isin) continue;
      final date = DateTime.tryParse('${c[0]}T00:00:00Z');
      final cents = double.tryParse(c[5]);
      final factor = double.tryParse(c[6]);
      final distribution = int.tryParse(c[7]) ?? 0;
      if (date == null || cents == null || factor == null || factor <= 0) {
        continue;
      }
      final volume = c.length > 8 ? double.tryParse(c[8]) : null;
      (out[c[1]] ??= []).add(TradingDay(date, cents / 100 / factor, distribution,
          volume == null ? null : volume / 100));
    }
  }
  for (final s in out.values) {
    s.sort((a, b) => a.date.compareTo(b.date));
  }
  return out;
}

/// Primeiro pregão em ou depois de [data], até [marginDays] dias corridos.
TradingDay? tradingDayFrom(List<TradingDay> series, DateTime day,
    {int marginDays = 10}) {
  // O COTAHIST é lido em UTC; uma data local à meia-noite cairia três horas
  // depois do pregão do mesmo dia e o pularia.
  final date = DateTime.utc(day.year, day.month, day.day);
  var lo = 0, hi = series.length;
  while (lo < hi) {
    final m = (lo + hi) ~/ 2;
    if (series[m].date.isBefore(date)) {
      lo = m + 1;
    } else {
      hi = m;
    }
  }
  if (lo >= series.length) return null;
  final p = series[lo];
  return p.date.difference(date).inDays <= marginDays ? p : null;
}

/// Último pregão em ou antes de [data], até [marginDays] dias corridos.
TradingDay? tradingDayUntil(List<TradingDay> series, DateTime day,
    {int marginDays = 10}) {
  final date = DateTime.utc(day.year, day.month, day.day);
  var lo = 0, hi = series.length;
  while (lo < hi) {
    final m = (lo + hi) ~/ 2;
    if (series[m].date.isAfter(date)) {
      hi = m;
    } else {
      lo = m + 1;
    }
  }
  if (lo == 0) return null;
  final p = series[lo - 1];
  return date.difference(p.date).inDays <= marginDays ? p : null;
}
