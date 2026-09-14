// A4 — os proventos da B3 conferidos, e o retorno total nas coortes.
//
// Quatro perguntas, sobre os 297 emissores do universo:
//
//   1. unidade e data  o fechamento com direito que a B3 publica bate com o
//                      COTAHIST no mesmo dia?
//   2. data ex         o preço cai na data ex, e cai na ordem do provento?
//   3. adjustedClose   o ajuste da fonte de preços corresponde aos proventos da
//                      B3? É a medição da §1.2 das limitações — desvio de 9,1%
//                      em 2026-08 contra o fluxo da própria fonte —, agora com
//                      fonte independente.
//   4. coortes         quanto o retorno total difere do de preço nas coortes de
//                      `backtest_valuation.json`, e o que muda na habilidade.
//
// Grava `docs/validacao/proventos.json` e, para a regressão condicional, uma
// cópia das coortes com `ret12tot` e `ret36tot` em
// `docs/validacao/backtest_valuation_total.json`.
//
// Uso:
//   python tool/b3_complemento_baixar.py
//   dart run tool/proventos_conferir.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'b3/proventos.dart';
import 'validation/context.dart';

double? _mediana(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double? _quantil(List<double> v, double q) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  return s[((s.length - 1) * q).round()];
}

String _pc(double? v, [int casas = 1]) =>
    v == null ? '—' : '${(v * 100).toStringAsFixed(casas)}%';

Future<void> main() async {
  final proventos = lerProventos();
  final universo = (jsonDecode(File('docs/validacao/universo.json')
          .readAsStringSync()) as List)
      .cast<Map<String, dynamic>>()
      .map((e) => e['ticker'] as String)
      .toSet();
  final bruto = lerCotahistBruto(universo);
  stderr.writeln('proventos de ${proventos.length} emissores; COTAHIST de '
      '${bruto.length} tickers');

  // ---- 1 e 2: unidade, data-com e queda na data ex ----------------------
  var comPreco = 0, precoBate = 0, comPregaoEx = 0;
  final quedas = <double>[];
  final desviosPreco = <double>[];
  for (final t in universo) {
    final serie = bruto[t];
    if (serie == null) continue;
    for (final p in proventosDo(proventos, t)) {
      if (p.exDate.year < 2010) continue;
      final com = pregaoAte(serie, p.lastDateWithRights, folgaDias: 0);
      final ex = pregaoApartir(serie, p.exDate, folgaDias: 5);
      if (p.closeWithRights != null && com != null) {
        comPreco++;
        final d = (p.closeWithRights! / com.close - 1).abs();
        desviosPreco.add(d);
        if (d <= 0.01) precoBate++;
      }
      if (com != null && ex != null) {
        comPregaoEx++;
        // Só provento que pesa: abaixo de 0,5% do preço, o ruído do dia manda.
        if (p.amount / com.close >= 0.005) {
          quedas.add((com.close - ex.close) / p.amount);
        }
      }
    }
  }

  // ---- 3: adjustedClose da fonte contra os proventos da B3 ---------------
  final fim = DateTime(2026, 9, 14);
  final inicio = DateTime(2016, 9, 14);
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  final ajustes = <Map<String, Object?>>[];
  try {
    for (final t in universo.toList()..sort()) {
      final lista = proventosDo(proventos, t);
      final serie = bruto[t];
      if (lista.isEmpty || serie == null) continue;
      final r = await ctx.prices.daily(Ticker.parse(t), DateRange(inicio, fim));
      if (r.isErr) continue;
      final pontos = [
        for (final p in r.unwrap().points)
          if (p.adjustedClose != null && p.adjustedClose! > 0 && p.close > 0) p,
      ];
      if (pontos.length < 500) continue;
      final a = pontos.first, b = pontos.last;
      // Convenção de ajuste para trás: cada provento multiplica os preços
      // anteriores por `1 − D/P_com`. A razão ajustado ÷ bruto entre as pontas
      // é o produto desses fatores.
      final observado =
          (a.adjustedClose! / a.close) / (b.adjustedClose! / b.close);
      var implicito = 1.0;
      var usados = 0, semPreco = 0;
      for (final p in lista) {
        if (!p.exDate.isAfter(a.date) || p.exDate.isAfter(b.date)) continue;
        final com = pregaoAte(serie, p.lastDateWithRights, folgaDias: 5);
        final preco = p.closeWithRights ?? com?.close;
        if (preco == null || preco <= p.amount) {
          semPreco++;
          continue;
        }
        implicito *= 1 - p.amount / preco;
        usados++;
      }
      if (usados == 0) continue;
      ajustes.add({
        'ticker': t,
        'proventos': usados,
        'semPreco': semPreco,
        'observado': observado,
        'implicitoB3': implicito,
        'desvio': (observado / implicito - 1).abs(),
      });
    }
  } finally {
    await ctx.dispose();
  }
  final desvios = [for (final x in ajustes) x['desvio']! as double];

  // ---- 4: retorno total nas coortes -------------------------------------
  final arquivoCoortes = File('docs/validacao/backtest_valuation.json');
  final coortes = arquivoCoortes.existsSync()
      ? (jsonDecode(arquivoCoortes.readAsStringSync()) as List)
          .cast<Map<String, dynamic>>()
      : <Map<String, dynamic>>[];
  final porCoorte = <int, List<double>>{};
  var semPrecoCoortes = 0, aproximadosCoortes = 0;
  for (final l in coortes) {
    final t = l['ticker'] as String;
    final ano = l['coorte'] as int;
    final base = DateTime.utc(ano, 9, 30);
    final serie = bruto[t];
    final lista = proventosDo(proventos, t);
    for (final (meses, campo) in [(12, 'ret12'), (36, 'ret36')]) {
      final preco = (l[campo] as num?)?.toDouble();
      if (preco == null) continue;
      if (serie == null) {
        l['${campo}tot'] = null;
        continue;
      }
      final r = TotalReturn.factor(
        dividends: lista,
        de: base,
        ate: DateTime.utc(ano + meses ~/ 12, 9, 30),
        closeOnExDate: (d) => pregaoApartir(serie, d, folgaDias: 5)?.close,
      );
      semPrecoCoortes += r.withoutPrice;
      aproximadosCoortes += r.approximated;
      final total = (1 + preco) * r.factor - 1;
      l['${campo}tot'] = total;
      if (meses == 36) (porCoorte[ano] ??= []).add(total - preco);
    }
  }
  if (coortes.isNotEmpty) {
    File('docs/validacao/backtest_valuation_total.json').writeAsStringSync(
        const JsonEncoder.withIndent(' ').convert(coortes));
  }

  final resultado = {
    'medidoEm': '2026-09-14',
    'dataCom': {
      'comPrecoDaB3': comPreco,
      'batemA1pct': precoBate,
      'desvioMediano': _mediana(desviosPreco),
    },
    'dataEx': {
      'comPregaoNasDuasDatas': comPregaoEx,
      'quedaSobreProventoMediana': _mediana(quedas),
      'quedaSobreProventoP25': _quantil(quedas, 0.25),
      'quedaSobreProventoP75': _quantil(quedas, 0.75),
      'n': quedas.length,
    },
    'adjustedClose': {
      'ativos': ajustes.length,
      'desvioMediano': _mediana(desvios),
      'desvioP90': _quantil(desvios, 0.9),
      'acimaDe5pct': desvios.where((d) => d > 0.05).length,
      'porAtivo': ajustes,
    },
    'coortes': {
      'linhas': coortes.length,
      'proventosSemPreco': semPrecoCoortes,
      'proventosPeloPrecoComDireito': aproximadosCoortes,
      'totalMenosPreco36m': {
        for (final e in porCoorte.entries) '${e.key}': _mediana(e.value),
      },
    },
  };
  File('docs/validacao/proventos.json')
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(resultado));

  stdout.writeln('== 1. Fechamento com direito: B3 contra COTAHIST ==');
  stdout.writeln('  $precoBate de $comPreco a 1% '
      '(${_pc(comPreco == 0 ? null : precoBate / comPreco)}); desvio mediano '
      '${_pc(_mediana(desviosPreco), 2)}');
  stdout.writeln('\n== 2. Queda na data ex ÷ provento ==');
  stdout.writeln('  mediana ${_mediana(quedas)?.toStringAsFixed(3)}  '
      'p25 ${_quantil(quedas, 0.25)?.toStringAsFixed(3)}  '
      'p75 ${_quantil(quedas, 0.75)?.toStringAsFixed(3)}  (n = ${quedas.length})');
  stdout.writeln('\n== 3. adjustedClose da fonte contra os proventos da B3, '
      '2016-09 a 2026-09 ==');
  stdout.writeln('  ativos: ${ajustes.length}  desvio mediano '
      '${_pc(_mediana(desvios))}  p90 ${_pc(_quantil(desvios, 0.9))}  '
      'acima de 5%: ${desvios.where((d) => d > 0.05).length}');
  ajustes.sort((a, b) =>
      (b['desvio']! as double).compareTo(a['desvio']! as double));
  for (final x in ajustes.take(10)) {
    stdout.writeln('    ${(x['ticker']! as String).padRight(7)} '
        'desvio ${_pc(x['desvio'] as double?)}  '
        '${x['proventos']} proventos');
  }
  stdout.writeln('\n== 4. Coortes: retorno total − de preço, 36 meses, '
      'mediana por coorte ==');
  for (final e in porCoorte.entries) {
    stdout.writeln('  ${e.key}: ${_pc(_mediana(e.value))}  (n = ${e.value.length})');
  }
  stdout.writeln('  proventos pelo preço com direito da B3, sem pregão no '
      'COTAHIST: $aproximadosCoortes; sem preço nenhum: $semPrecoCoortes');
  stdout.writeln('\n  gravado docs/validacao/proventos.json e '
      'docs/validacao/backtest_valuation_total.json');
}
