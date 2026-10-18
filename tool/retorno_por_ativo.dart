// O retorno por ativo mede o ativo, ou o cronograma de aportes?
//
// `BacktestOutcome` reporta três retornos para a **carteira** — TWR, XIRR e o
// CAGR derivado do TWR —, e um só para cada **ativo**:
//
//     totalReturn = (valor final + caixa − aportado) ÷ aportado
//
// que é razão de capital acumulado, sem dimensão de tempo. A lente `metodo`
// aponta que ele herda o calendário de aportes e não é comparável ao da
// carteira. A pergunta desta medição é se isso **desloca a ordenação** entre
// ativos, que é o que o usuário lê.
//
// Duas partes: um caso sintético que isola o mecanismo, e uma carteira real
// que mede o tamanho.
//
// Uso:
//   dart run tool/retorno_por_ativo.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

final _start = DateTime(2019, 9, 30);
final _end = DateTime(2026, 9, 4);

/// Retorno de preço do ativo no período — a medida que **não** depende do
/// cronograma de aportes.
double? _priceReturn(PriceSeries s, DateTime from, DateTime until) {
  double? p0, p1;
  for (final p in s.points) {
    if (p.date.isBefore(from)) continue;
    p0 ??= p.close;
    if (!p.date.isAfter(until)) p1 = p.close;
  }
  if (p0 == null || p1 == null || p0 <= 0) return null;
  return p1 / p0 - 1;
}

/// Empate em posto: dois retornos indistinguíveis dentro da tolerância.
///
/// A comparação é **relativa à magnitude**, e não `==`: dois retornos que
/// saem de somas diferentes de centavos podem diferir no último bit e
/// receberiam postos distintos, o que muda o Spearman sem que nada tenha
/// mudado no dado.
bool _tie(double a, double b) {
  final scale = a.abs() > b.abs() ? a.abs() : b.abs();
  return (a - b).abs() <= (scale > 1 ? scale : 1) * 1e-12;
}

List<double> _ranks(List<double> v) {
  final idx = List.generate(v.length, (i) => i)
    ..sort((x, y) => v[x].compareTo(v[y]));
  final r = List<double>.filled(v.length, 0);
  var i = 0;
  while (i < idx.length) {
    var j = i;
    while (j + 1 < idx.length && _tie(v[idx[j + 1]], v[idx[i]])) {
      j++;
    }
    final middle = (i + j) / 2 + 1;
    for (var k = i; k <= j; k++) {
      r[idx[k]] = middle;
    }
    i = j + 1;
  }
  return r;
}

double _spearman(List<double> a, List<double> b) {
  if (a.length < 2) return 0.0;
  final ranksA = _ranks(a), ranksB = _ranks(b);
  final meanA = ranksA.reduce((x, y) => x + y) / ranksA.length;
  final meanB = ranksB.reduce((x, y) => x + y) / ranksB.length;
  var num = 0.0, sumSqA = 0.0, sumSqB = 0.0;
  for (var i = 0; i < ranksA.length; i++) {
    num += (ranksA[i] - meanA) * (ranksB[i] - meanB);
    sumSqA += math.pow(ranksA[i] - meanA, 2);
    sumSqB += math.pow(ranksB[i] - meanB, 2);
  }
  return (sumSqA <= 0 || sumSqB <= 0) ? 0.0 : num / math.sqrt(sumSqA * sumSqB);
}

// ------------------------------------------------------- caso sintético --

void _synthetic() {
  stdout.writeln('== 1. O mecanismo, isolado ==');
  stdout.writeln('');
  stdout.writeln('Dois ativos que começam e terminam no MESMO preço — retorno');
  stdout.writeln('de preço zero para ambos. Um cai e volta; o outro sobe e');
  stdout.writeln('volta. Mesmo peso, mesmo aporte mensal, mesma janela.');
  stdout.writeln('');

  final days = <DateTime>[
    for (var i = 0; i < 84; i++) DateTime(2019, 1 + i, 1),
  ];

  // Vale e pico, simétricos: ambos partem de 100 e voltam a 100.
  double vale(int i) => 100 - 40 * math.sin(math.pi * i / (days.length - 1));
  double peak(int i) => 100 + 40 * math.sin(math.pi * i / (days.length - 1));

  PriceSeries series(String t, double Function(int) f) => PriceSeries(
        ticker: Ticker.parse(t),
        points: [
          for (var i = 0; i < days.length; i++)
            PricePoint(date: days[i], close: f(i)),
        ],
      );

  final fell = Ticker.parse('VALE4');
  final rose = Ticker.parse('PICO4');
  const sector = Sector(key: 's', label: 'S');
  final portfolio = Portfolio.equalWeighted(
    id: 'x',
    name: 'x',
    kind: PortfolioKind.principal,
    assets: [
      Asset(ticker: fell, name: 'Vale', sector: sector),
      Asset(ticker: rose, name: 'Pico', sector: sector),
    ],
  ).unwrap();

  final r = PortfolioBacktest.run(
    portfolio: portfolio,
    prices: {fell: series('VALE4', vale), rose: series('PICO4', peak)},
    plan: ContributionPlan(
      initial: Money.fromReais(1000),
      monthly: Money.fromReais(1000),
      contributionDay: 1,
    ),
    range: DateRange(days.first, days.last),
    // A demonstração é de TWR contra XIRR, e não de custo (item C4).
    costs: TransactionCosts.none,
  );
  if (r.isErr) {
    stdout.writeln('  falhou: ${r.failureOrNull?.message}');
    return;
  }
  final o = r.unwrap();
  stdout.writeln('  período efetivo: ${o.effectivePeriod}');
  for (final t in [fell, rose]) {
    final a = o.perAsset[t];
    if (a == null) continue;
    stdout.writeln('  ${t.value}: totalReturn = '
        '${(a.totalReturn * 100).toStringAsFixed(1)}%   '
        'retorno de preço = 0,0%   '
        'aportado ${(a.invested.cents / 100).toStringAsFixed(0)}   '
        'final ${(a.finalValue.cents / 100).toStringAsFixed(0)}');
  }
  final va = o.perAsset[fell]?.totalReturn;
  final nv = o.perAsset[rose]?.totalReturn;
  if (va != null && nv != null) {
    stdout.writeln('');
    stdout.writeln('  distância entre dois ativos de retorno de preço IGUAL '
        '(zero): ${((va - nv) * 100).toStringAsFixed(1)} p.p.');
    stdout.writeln('  O número não descreve o ativo: descreve o que o dinheiro');
    stdout.writeln('  do aporte mensal fez dentro dele. As duas leituras são');
    stdout.writeln('  verdadeiras, e respondem a perguntas diferentes.');
  }

  // E o canal que a lente teme — datas de listagem diferentes — é fechado
  // pelo próprio backtest: o período recua para o ativo mais novo.
  final newSecurity = Ticker.parse('NOVO3');
  final c2 = Portfolio.equalWeighted(
    id: 'y',
    name: 'y',
    kind: PortfolioKind.principal,
    assets: [
      Asset(ticker: fell, name: 'Vale', sector: sector),
      Asset(ticker: newSecurity, name: 'Novo', sector: sector),
    ],
  ).unwrap();
  final r2 = PortfolioBacktest.run(
    portfolio: c2,
    prices: {
      fell: series('VALE4', vale),
      newSecurity: PriceSeries(
        ticker: newSecurity,
        points: [
          for (var i = 60; i < days.length; i++)
            PricePoint(date: days[i], close: vale(i)),
        ],
      ),
    },
    plan: ContributionPlan(
      initial: Money.fromReais(1000),
      monthly: Money.fromReais(1000),
      contributionDay: 1,
    ),
    range: DateRange(days.first, days.last),
  );
  stdout.writeln('');
  if (r2.isOk) {
    final o2 = r2.unwrap();
    stdout.writeln('  com um ativo listado 60 meses depois, o período efetivo '
        'vira ${o2.effectivePeriod}');
    for (final w in o2.warnings) {
      stdout.writeln('    aviso: $w');
    }
    final a = o2.perAsset[fell]?.totalReturn;
    final b = o2.perAsset[newSecurity]?.totalReturn;
    if (a != null && b != null) {
      stdout.writeln('    VALE4 ${(a * 100).toStringAsFixed(1)}%  '
          'NOVO3 ${(b * 100).toStringAsFixed(1)}%  — medidos na mesma janela');
    }
  }
}

// --------------------------------------------------------- carteira real --

Future<void> _real(ValidationContext ctx) async {
  stdout.writeln('');
  stdout.writeln('');
  stdout.writeln('== 2. O tamanho, numa carteira real ==');
  stdout.writeln('');

  final universe = (await ctx.fundamentals.universe()).unwrap();
  final chosen = <Ticker>[];
  final series = <Ticker, PriceSeries>{};
  for (final t in universe) {
    if (chosen.length >= Portfolio.maxAssets) break;
    final r = await ctx.prices.daily(t, DateRange(_start, _end));
    if (r.isErr) continue;
    final s = r.unwrap();
    if (s.points.length < 1000) continue;
    chosen.add(t);
    series[t] = s;
  }
  if (chosen.length < 5) {
    stdout.writeln('  ativos insuficientes com histórico completo.');
    return;
  }

  final assets = <Asset>[];
  for (final t in chosen) {
    final p = await ctx.fundamentals.profile(t);
    assets.add(p.isOk
        ? p.unwrap()
        : Asset(
            ticker: t,
            name: t.value,
            sector: const Sector(key: 'x', label: 'X'),
          ));
  }
  final portfolio = Portfolio.equalWeighted(
    id: 'r',
    name: 'r',
    kind: PortfolioKind.principal,
    assets: assets,
  ).unwrap();

  final r = PortfolioBacktest.run(
    portfolio: portfolio,
    prices: series,
    plan: ContributionPlan(
      initial: Money.fromReais(10000),
      monthly: Money.fromReais(1000),
      contributionDay: 5,
    ),
    range: DateRange(_start, _end),
  );
  if (r.isErr) {
    stdout.writeln('  falhou: ${r.failureOrNull?.message}');
    return;
  }
  final o = r.unwrap();

  final rows = <Map<String, Object?>>[];
  for (final t in chosen) {
    final a = o.perAsset[t];
    if (a == null) continue;
    final price = _priceReturn(series[t]!, _start, _end);
    if (price == null) continue;
    rows.add({
      'ticker': t.value,
      'totalReturn': a.totalReturn,
      'retornoDePreco': price,
      'aportado': a.invested.cents / 100,
      'caixa': a.cash.cents / 100,
      'pregoes': series[t]!.points.length,
    });
  }
  rows.sort((a, b) =>
      (b['totalReturn']! as double).compareTo(a['totalReturn']! as double));

  final tr = [for (final l in rows) l['totalReturn']! as double];
  final priceReturns = [for (final l in rows) l['retornoDePreco']! as double];
  final priceOrder = List.generate(rows.length, (i) => i)
    ..sort((x, y) => priceReturns[y].compareTo(priceReturns[x]));
  final priceRank = <int, int>{};
  for (var i = 0; i < priceOrder.length; i++) {
    priceRank[priceOrder[i]] = i + 1;
  }

  stdout.writeln('  ticker    totalReturn   retorno de preço   posto tR   '
      'posto preço   pregões');
  var largestShift = 0;
  for (var i = 0; i < rows.length; i++) {
    final d = (priceRank[i]! - (i + 1)).abs();
    if (d > largestShift) largestShift = d;
    stdout.writeln('  ${(rows[i]['ticker']! as String).padRight(8)} '
        '${(tr[i] * 100).toStringAsFixed(1).padLeft(11)}%   '
        '${(priceReturns[i] * 100).toStringAsFixed(1).padLeft(15)}%   '
        '${(i + 1).toString().padLeft(8)}   '
        '${priceRank[i].toString().padLeft(11)}   '
        '${(rows[i]['pregoes']! as int).toString().padLeft(7)}');
  }
  stdout.writeln('');
  stdout.writeln('  Spearman entre as duas medidas: '
      '${_spearman(tr, priceReturns).toStringAsFixed(4)}');
  stdout.writeln('  maior deslocamento de posto: $largestShift '
      'de ${rows.length}');
  final xirr = o.metrics.moneyWeightedReturn;
  stdout.writeln('  TWR da carteira: '
      '${(o.metrics.timeWeightedReturn * 100).toStringAsFixed(1)}%   '
      'XIRR: ${xirr == null ? "—" : "${(xirr * 100).toStringAsFixed(1)}%"}');

  File('docs/validacao/retorno_por_ativo.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(rows),
  );
  stdout.writeln('');
  stdout.writeln('  gravado em docs/validacao/retorno_por_ativo.json');
}

Future<void> main(List<String> args) async {
  _synthetic();
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    await _real(ctx);
  } finally {
    await ctx.dispose();
  }
}
