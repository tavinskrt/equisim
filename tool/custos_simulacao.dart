// O efeito da tarifa da B3 sobre a simulação da carteira (item C4).
//
// A simulação do aplicativo passou a cobrar a tarifa de negociação e
// liquidação da B3 em cada compra (`TransactionCosts.b3`, 0,030%). Aqui se
// mede quanto isso move o que a tela mostra: patrimônio final, XIRR e o custo
// somado, em carteiras sorteadas do universo congelado do gabarito — semente
// fixa, a mesma entrada a cada execução.
//
// **O que não entra.** O spread de compra e venda: a simulação compra ao
// fechamento, e o meio spread de quem manda ordem a mercado foi medido nas
// coortes (`tool/custos_spread.py`), onde ele é o que pesa. Uma sensibilidade
// com 0,5% por compra — a ordem do meio spread do tercil médio de liquidez —
// fica ao lado, para dizer quanto ele pesaria aqui.
//
// Uso:
//   dart run tool/gabarito_cascata.dart        # a entrada congelada, se faltar
//   dart run tool/custos_simulacao.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';

const _portfolios = 50;
const _assetsPerPortfolio = 8;
const _seed = 20260922;

Future<void> main() async {
  final c = await Frozen.build();
  final window = DateRange(DateTime(2019, 1, 2), DateTime(2026, 8, 31));

  final series = <Ticker, PriceSeries>{};
  for (final t in c.universe) {
    final r = await c.ctx.prices.daily(t, window);
    final s = r.valueOrNull;
    // Só quem tem a janela inteira: série encurtada encurtaria a simulação de
    // todos os ativos da carteira sorteada.
    if (s == null || s.isEmpty) continue;
    if (s.firstDate.isAfter(DateTime(2019, 1, 31))) continue;
    series[t] = s;
  }
  stdout.writeln('== Custo de transação na simulação (item C4) ==');
  stdout.writeln('  ativos com a janela inteira: ${series.length}');

  final rnd = math.Random(_seed);
  final available = series.keys.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  final plan = ContributionPlan(
    initial: Money.fromReais(10000),
    monthly: Money.fromReais(1000),
    contributionDay: 5,
  );
  const scenarios = {
    'semCusto': TransactionCosts.none,
    'tarifaB3': TransactionCosts.b3,
    'tarifaEMeioSpread': TransactionCosts(feePartsPerMillion: 5300),
  };

  final rows = <Map<String, Object?>>[];
  for (var i = 0; i < _portfolios; i++) {
    final choice = [...available]..shuffle(rnd);
    final assets = choice.take(_assetsPerPortfolio).toList();
    final portfolio = Portfolio.equalWeighted(
      id: 'c$i',
      name: 'c$i',
      kind: PortfolioKind.principal,
      assets: [
        for (final t in assets)
          Asset(ticker: t, name: t.value, sector: Sector.unknown),
      ],
    ).unwrap();
    final byScenario = <String, BacktestOutcome>{};
    for (final e in scenarios.entries) {
      final r = PortfolioBacktest.run(
        portfolio: portfolio,
        prices: {for (final t in assets) t: series[t]!},
        plan: plan,
        range: window,
        costs: e.value,
      );
      if (r.isOk) byScenario[e.key] = r.unwrap();
    }
    if (byScenario.length != scenarios.length) continue;
    final base = byScenario['semCusto']!;
    rows.add({
      'ativos': [for (final t in assets) t.value],
      'aportado': base.totalContributed.reais,
      for (final e in byScenario.entries)
        e.key: {
          'patrimonioFinal': e.value.finalValue.reais,
          'xirr': e.value.metrics.moneyWeightedReturn,
          'custos': e.value.transactionCosts.reais,
        },
    });
  }

  double median(List<double> xs) {
    final s = [...xs]..sort();
    return s.isEmpty ? double.nan : s[s.length ~/ 2];
  }

  final summary = <String, Object?>{'carteiras': rows.length};
  for (final k in ['tarifaB3', 'tarifaEMeioSpread']) {
    final wealthLoss = <double>[];
    final xirrLoss = <double>[];
    final costOverContributed = <double>[];
    for (final l in rows) {
      final b = l['semCusto']! as Map<String, Object?>;
      final x = l[k]! as Map<String, Object?>;
      wealthLoss.add((x['patrimonioFinal']! as double) /
              (b['patrimonioFinal']! as double) -
          1);
      final baseXirr = b['xirr'] as double?, otherXirr = x['xirr'] as double?;
      if (baseXirr != null && otherXirr != null) xirrLoss.add(otherXirr - baseXirr);
      costOverContributed
          .add((x['custos']! as double) / (l['aportado']! as double));
    }
    summary[k] = {
      'variacaoDoPatrimonioFinalMediana': median(wealthLoss),
      'variacaoDoXirrMediana': median(xirrLoss),
      'piorVariacaoDoXirr': xirrLoss.isEmpty ? null : xirrLoss.reduce(math.min),
      'custoSobreAportadoMediano': median(costOverContributed),
    };
  }
  File('docs/validacao/custos_simulacao.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert({
      'semente': _seed,
      'janela': '${window.start.toIso8601String().substring(0, 10)} a '
          '${window.end.toIso8601String().substring(0, 10)}',
      'plano': 'R\$ 10.000 inicial e R\$ 1.000 por mês',
      'resumo': summary,
      'carteiras': rows,
    }),
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(summary));
  await c.ctx.dispose();
}
