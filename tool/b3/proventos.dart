// Leitores compartilhados dos itens A4 e A3.4: proventos da B3 e fechamento
// bruto do COTAHIST, para `proventos_conferir.dart`, `backtest_valuation.dart`
// e `b3_deslistadas_contagem.dart`.
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

/// Proventos por emissor de quatro letras, de `data/b3/complemento/`.
Map<String, List<CashDividend>> lerProventos({String dir = 'data/b3/complemento'}) {
  final pasta = Directory(dir);
  if (!pasta.existsSync()) {
    stderr.writeln('sem $dir — rode: python tool/b3_complemento_baixar.py');
    exit(2);
  }
  final out = <String, List<CashDividend>>{};
  for (final f in pasta.listSync().whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    final bruto = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final emissor = f.uri.pathSegments.last.replaceAll('.json', '');
    out[emissor] = B3CashDividends.parse(
        (bruto['proventos'] as List?)?.cast<Object?>() ?? const []);
  }
  return out;
}

/// Os proventos da classe de [ticker], ou lista vazia.
List<CashDividend> proventosDo(
    Map<String, List<CashDividend>> proventos, String ticker) {
  return CashDividendsCodec.forTicker(proventos, ticker);
}

/// Um pregão do COTAHIST: fechamento bruto por ação e número de distribuição.
class Pregao {
  final DateTime date;
  final double close;
  final int distribuicao;

  /// Volume financeiro do dia, em reais. `null` quando o arquivo não o traz.
  final double? financeiro;
  const Pregao(this.date, this.close, this.distribuicao, [this.financeiro]);

  RawQuote get raw => RawQuote(date, close, distribuicao);
}

/// Fechamento **bruto por ação** do COTAHIST, por ticker, em ordem de data.
///
/// O CSV compacto guarda o fechamento em centavos por lote de `fatorCotacao`
/// ações, e o volume financeiro em centavos; aqui saem em reais.
///
/// - [isins]: quando dado, só entra o pregão do ISIN do ticker. Um ticker pode
///   ter sido de mais de um papel ao longo dos anos.
Map<String, List<Pregao>> lerCotahistBruto(Set<String> tickers,
    {Map<String, String>? isins}) {
  final out = <String, List<Pregao>>{};
  final arquivos = Directory('data/b3')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'avista_\d{4}\.csv$').hasMatch(f.path))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in arquivos) {
    var cabecalho = true;
    for (final linha in f.readAsLinesSync()) {
      if (cabecalho) {
        cabecalho = false;
        continue;
      }
      final c = linha.split(';');
      if (c.length < 8 || !tickers.contains(c[1])) continue;
      final isin = isins?[c[1]];
      if (isin != null && c[2] != isin) continue;
      final data = DateTime.tryParse('${c[0]}T00:00:00Z');
      final centavos = double.tryParse(c[5]);
      final fator = double.tryParse(c[6]);
      final distribuicao = int.tryParse(c[7]) ?? 0;
      if (data == null || centavos == null || fator == null || fator <= 0) {
        continue;
      }
      final volume = c.length > 8 ? double.tryParse(c[8]) : null;
      (out[c[1]] ??= []).add(Pregao(data, centavos / 100 / fator, distribuicao,
          volume == null ? null : volume / 100));
    }
  }
  for (final s in out.values) {
    s.sort((a, b) => a.date.compareTo(b.date));
  }
  return out;
}

/// Primeiro pregão em ou depois de [data], até [folgaDias] dias corridos.
Pregao? pregaoApartir(List<Pregao> serie, DateTime dia,
    {int folgaDias = 10}) {
  // O COTAHIST é lido em UTC; uma data local à meia-noite cairia três horas
  // depois do pregão do mesmo dia e o pularia.
  final data = DateTime.utc(dia.year, dia.month, dia.day);
  var lo = 0, hi = serie.length;
  while (lo < hi) {
    final m = (lo + hi) ~/ 2;
    if (serie[m].date.isBefore(data)) {
      lo = m + 1;
    } else {
      hi = m;
    }
  }
  if (lo >= serie.length) return null;
  final p = serie[lo];
  return p.date.difference(data).inDays <= folgaDias ? p : null;
}

/// Último pregão em ou antes de [data], até [folgaDias] dias corridos.
Pregao? pregaoAte(List<Pregao> serie, DateTime dia,
    {int folgaDias = 10}) {
  final data = DateTime.utc(dia.year, dia.month, dia.day);
  var lo = 0, hi = serie.length;
  while (lo < hi) {
    final m = (lo + hi) ~/ 2;
    if (serie[m].date.isAfter(data)) {
      hi = m;
    } else {
      lo = m + 1;
    }
  }
  if (lo == 0) return null;
  final p = serie[lo - 1];
  return data.difference(p.date).inDays <= folgaDias ? p : null;
}
