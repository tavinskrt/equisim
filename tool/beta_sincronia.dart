// O beta e a negociação não síncrona.
//
// **O defeito apontado.** O beta sai de regressão de retorno **diário** contra
// o Ibovespa. Ativo que não negocia todo dia responde ao mercado com atraso: o
// retorno dele hoje carrega parte da informação de ontem, e a covariância
// contemporânea perde essa parte. O viés é conhecido e tem direção — **para
// baixo** —, e a correção clássica é a de Dimson: somar as inclinações contra
// o mercado defasado, contemporâneo e adiantado.
//
// **A outra metade do apontamento está bloqueada por dado.** Retorno sobre
// cotação "suja" — não ajustada por provento — só se corrige com a série de
// retorno total da fonte, e a [limitação 1.2](../docs/validacao/limitacoes.md)
// mediu que ela é inutilizável: desvio mediano de 9,1% contra o fluxo de
// proventos publicado, máximo de 38,5%.
//
// **O que isto mede.** Três estimadores no mesmo ativo, na mesma janela:
// diário contemporâneo (o de produção), semanal, e Dimson com uma defasagem e
// uma antecipação.
//
// Uso:
//   dart run tool/beta_sincronia.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';
import 'validation/regression.dart';

final _hoje = DateTime(2026, 9, 4);

double? _mediana(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

String _pc(double v) => '${(v * 100).toStringAsFixed(1)}%';

/// Reduz a série ao **último pregão de cada semana**.
///
/// Semana pela data ISO — segunda a domingo —, de modo que feriado no meio não
/// desloca a contagem. O que interessa é ter um ponto por semana com o mesmo
/// corte nos dois lados da regressão.
List<({DateTime date, double close})> _semanal(
  List<DateTime> datas,
  List<double> fechamentos,
) {
  final porSemana = <int, ({DateTime date, double close})>{};
  for (var i = 0; i < datas.length; i++) {
    final d = datas[i];
    // Chave da semana: dias desde a época, divididos por sete, alinhados à
    // segunda-feira. Em UTC, para não depender de horário de verão.
    final dias = DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
    final semana = (dias + 3) ~/ 7; // 1970-01-01 foi quinta
    final atual = porSemana[semana];
    if (atual == null || d.isAfter(atual.date)) {
      porSemana[semana] = (date: d, close: fechamentos[i]);
    }
  }
  final chaves = porSemana.keys.toList()..sort();
  return [for (final k in chaves) porSemana[k]!];
}

Future<void> main(List<String> args) async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final universe = (await ctx.fundamentals.universe()).unwrap();
    final janela = DateRange(
      DateTime(_hoje.year - PrepareValuationInputs.betaWindowYears, _hoje.month,
          _hoje.day),
      _hoje,
    );
    final indiceRes = await ctx.benchmark.ibovespa(janela);
    if (indiceRes.isErr) {
      stderr.writeln('sem índice: ${indiceRes.failureOrNull?.message}');
      return;
    }
    final indice = indiceRes.unwrap();

    // **Só os que o motor avalia.** O universo cru tem ativo que negocia vinte
    // pregões por ano, e neles o beta diário não é estimador ruim — é ruído.
    // A Porta 0 já os barra, e medir o viés fora dela mede outra coisa.
    final avaliaveis = <String>{};
    final relatorio = File('docs/validacao/fluxo_explicito.json');
    if (relatorio.existsSync()) {
      for (final e in jsonDecode(relatorio.readAsStringSync()) as List) {
        avaliaveis.add((e as Map<String, dynamic>)['ticker'] as String);
      }
    }
    stderr.writeln('avaliáveis: ${avaliaveis.length}');

    final saida = <Map<String, dynamic>>[];
    var i = 0;
    for (final ticker in universe) {
      if (avaliaveis.isNotEmpty && !avaliaveis.contains(ticker.value)) continue;
      i++;
      if (i % 25 == 0) stderr.write('  $i/${universe.length}   \r');
      final serieRes = await ctx.prices.daily(ticker, janela);
      if (serieRes.isErr) continue;
      final pontos = serieRes
          .unwrap()
          .points
          .where((p) => janela.contains(p.date))
          .toList();
      if (pontos.length < 60) continue;

      // --- Diário contemporâneo: o estimador de produção -------------------
      final par = BetaCalculator.alignReturns(
        assetDates: [for (final p in pontos) p.date],
        assetIndex: [for (final p in pontos) p.close],
        marketDates: indice.dates,
        marketIndex: indice.points.map((p) => p.close).toList(),
      );
      final diario = BetaCalculator.estimate(returns: par);
      if (diario.isErr) continue;

      // --- Semanal ---------------------------------------------------------
      final semAtivo = _semanal(
        [for (final p in pontos) p.date],
        [for (final p in pontos) p.close],
      );
      final semMercado = _semanal(
        indice.dates,
        indice.points.map((p) => p.close).toList(),
      );
      final parSemanal = BetaCalculator.alignReturns(
        assetDates: [for (final p in semAtivo) p.date],
        assetIndex: [for (final p in semAtivo) p.close],
        marketDates: [for (final p in semMercado) p.date],
        marketIndex: [for (final p in semMercado) p.close],
      );
      final semanal = BetaCalculator.estimate(returns: parSemanal);

      // --- Dimson: defasado, contemporâneo e adiantado ---------------------
      //
      // `β = β₋₁ + β₀ + β₊₁`, das inclinações de uma regressão múltipla. É a
      // correção clássica para negociação não síncrona.
      double? dimson;
      double? dimsonSe;
      final ra = par.asset;
      final rm = par.market;
      if (ra.length >= 40) {
        final n = ra.length;
        final y = <double>[];
        final x0 = <double>[];
        final xMenos = <double>[];
        final xMais = <double>[];
        for (var t = 1; t < n - 1; t++) {
          y.add(ra[t]);
          x0.add(rm[t]);
          xMenos.add(rm[t - 1]);
          xMais.add(rm[t + 1]);
        }
        final ols = Regression.ols([xMenos, x0, xMais], y);
        if (ols != null) {
          dimson = ols.coefficients[1] + ols.coefficients[2] + ols.coefficients[3];
          // Erro-padrão da soma, ignorando a covariância entre coeficientes:
          // é cota inferior, e serve para ordem de grandeza.
          dimsonSe = 0.0;
          for (var k = 1; k <= 3; k++) {
            dimsonSe = dimsonSe! + ols.stdErrors[k] * ols.stdErrors[k];
          }
          dimsonSe = dimsonSe == null ? null : _raiz(dimsonSe);
        }
      }

      final d = diario.unwrap();
      saida.add({
        'ticker': ticker.value,
        'pregoes': pontos.length,
        'pregoesPorAno': pontos.length / PrepareValuationInputs.betaWindowYears,
        'betaDiario': d.beta,
        'seDiario': d.standardError,
        'betaSemanal': semanal.isOk ? semanal.unwrap().beta : null,
        'seSemanal': semanal.isOk ? semanal.unwrap().standardError : null,
        'obsSemanal': parSemanal.asset.length,
        'betaDimson': dimson,
        'seDimson': dimsonSe,
      });
    }
    stderr.writeln('');

    File('docs/validacao/beta_sincronia.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(saida),
    );
    _imprimir(saida);
    stderr.writeln('\nescrito docs/validacao/beta_sincronia.json '
        '(${saida.length})');
  } finally {
    await ctx.dispose();
  }
}

double _raiz(double x) {
  if (x <= 0) return 0;
  var r = x;
  for (var i = 0; i < 60; i++) {
    r = 0.5 * (r + x / r);
  }
  return r;
}

void _imprimir(List<Map<String, dynamic>> l) {
  stdout.writeln('\n=== BETA E NEGOCIAÇÃO NÃO SÍNCRONA — ${l.length} ===\n');

  List<double> col(String k) => [
        for (final e in l)
          if (e[k] != null && (e[k] as num).toDouble().isFinite)
            (e[k] as num).toDouble()
      ];

  for (final par in [
    ('semanal ÷ diário', 'betaSemanal'),
    ('Dimson ÷ diário', 'betaDimson'),
  ]) {
    final razoes = <double>[];
    for (final e in l) {
      final a = (e['betaDiario'] as num?)?.toDouble();
      final b = (e[par.$2] as num?)?.toDouble();
      if (a == null || b == null || a.abs() < 1e-9) continue;
      razoes.add(b / a);
    }
    if (razoes.isEmpty) continue;
    razoes.sort();
    stdout.writeln('-- ${par.$1} --');
    stdout.writeln('  p10=${razoes[(razoes.length * 0.1).floor()]
        .toStringAsFixed(3)}  '
        'mediana=${_mediana(razoes)!.toStringAsFixed(3)}  '
        'p90=${razoes[(razoes.length * 0.9).floor()].toStringAsFixed(3)}');
    stdout.writeln('  maior que o diário em '
        '${razoes.where((x) => x > 1).length} de ${razoes.length}  '
        '(acima de 1,10: ${razoes.where((x) => x > 1.10).length})');
  }

  final seD = col('seDiario');
  final seS = col('seSemanal');
  final seDim = col('seDimson');
  stdout.writeln('\n-- erro-padrão de cada estimador --');
  if (seD.isNotEmpty) {
    stdout.writeln('  diário:  mediana=${_mediana(seD)!.toStringAsFixed(4)}');
  }
  if (seS.isNotEmpty) {
    stdout.writeln('  semanal: mediana=${_mediana(seS)!.toStringAsFixed(4)}');
  }
  if (seDim.isNotEmpty) {
    stdout.writeln('  Dimson:  mediana=${_mediana(seDim)!.toStringAsFixed(4)}');
  }

  // A hipótese: o viés é dos que negociam menos.
  final porLiquidez = [...l]
    ..sort((a, b) => (a['pregoesPorAno'] as num)
        .compareTo(b['pregoesPorAno'] as num));
  stdout.writeln('\n-- o viés é dos que negociam menos? --');
  final metade = porLiquidez.length ~/ 2;
  for (final grupo in [
    ('menos pregões', porLiquidez.take(metade).toList()),
    ('mais pregões', porLiquidez.skip(metade).toList()),
  ]) {
    final razoes = <double>[];
    for (final e in grupo.$2) {
      final a = (e['betaDiario'] as num?)?.toDouble();
      final b = (e['betaDimson'] as num?)?.toDouble();
      if (a == null || b == null || a.abs() < 1e-9) continue;
      razoes.add(b / a);
    }
    if (razoes.isEmpty) continue;
    final pregoes = [
      for (final e in grupo.$2) (e['pregoesPorAno'] as num).toDouble()
    ];
    stdout.writeln('  ${grupo.$1.padRight(16)} '
        'pregões/ano mediano=${_mediana(pregoes)!.toStringAsFixed(0)}  '
        'Dimson÷diário mediano=${_mediana(razoes)!.toStringAsFixed(3)}');
  }

  final ord = [...l]..sort((a, b) {
      final x = (a['betaDimson'] as num?)?.toDouble();
      final y = (b['betaDimson'] as num?)?.toDouble();
      final ax = (a['betaDiario'] as num?)?.toDouble() ?? 1;
      final by = (b['betaDiario'] as num?)?.toDouble() ?? 1;
      return ((y ?? 0) / by).compareTo((x ?? 0) / ax);
    });
  stdout.writeln('\n-- onde Dimson mais eleva o beta --');
  stdout.writeln('  ${"ativo".padRight(8)}${"diário".padLeft(9)}'
      '${"semanal".padLeft(9)}${"Dimson".padLeft(9)}${"pregões".padLeft(9)}');
  for (final e in ord.take(8)) {
    String f(String k) {
      final v = (e[k] as num?)?.toDouble();
      return v == null ? '—' : v.toStringAsFixed(3);
    }

    stdout.writeln('  ${(e['ticker'] as String).padRight(8)}'
        '${f('betaDiario').padLeft(9)}${f('betaSemanal').padLeft(9)}'
        '${f('betaDimson').padLeft(9)}'
        '${(e['pregoesPorAno'] as num).toStringAsFixed(0).padLeft(9)}');
  }
  stdout.writeln('\n  (a metade "cotação suja" do apontamento está bloqueada '
      'pela limitação 1.2: ${_pc(0.091)} de desvio mediano na série de retorno '
      'total da fonte)');
}
