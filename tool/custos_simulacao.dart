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

const _carteiras = 50;
const _ativosPorCarteira = 8;
const _semente = 20260922;

Future<void> main() async {
  final c = await Congelado.montar();
  final janela = DateRange(DateTime(2019, 1, 2), DateTime(2026, 8, 31));

  final series = <Ticker, PriceSeries>{};
  for (final t in c.universo) {
    final r = await c.ctx.prices.daily(t, janela);
    final s = r.valueOrNull;
    // Só quem tem a janela inteira: série encurtada encurtaria a simulação de
    // todos os ativos da carteira sorteada.
    if (s == null || s.isEmpty) continue;
    if (s.firstDate.isAfter(DateTime(2019, 1, 31))) continue;
    series[t] = s;
  }
  stdout.writeln('== Custo de transação na simulação (item C4) ==');
  stdout.writeln('  ativos com a janela inteira: ${series.length}');

  final rnd = math.Random(_semente);
  final disponiveis = series.keys.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  final plano = ContributionPlan(
    initial: Money.fromReais(10000),
    monthly: Money.fromReais(1000),
    contributionDay: 5,
  );
  const cenarios = {
    'semCusto': TransactionCosts.none,
    'tarifaB3': TransactionCosts.b3,
    'tarifaEMeioSpread': TransactionCosts(feePartsPerMillion: 5300),
  };

  final linhas = <Map<String, Object?>>[];
  for (var i = 0; i < _carteiras; i++) {
    final escolha = [...disponiveis]..shuffle(rnd);
    final ativos = escolha.take(_ativosPorCarteira).toList();
    final carteira = Portfolio.equalWeighted(
      id: 'c$i',
      name: 'c$i',
      kind: PortfolioKind.principal,
      assets: [
        for (final t in ativos)
          Asset(ticker: t, name: t.value, sector: Sector.unknown),
      ],
    ).unwrap();
    final porCenario = <String, BacktestOutcome>{};
    for (final e in cenarios.entries) {
      final r = PortfolioBacktest.run(
        portfolio: carteira,
        prices: {for (final t in ativos) t: series[t]!},
        plan: plano,
        range: janela,
        costs: e.value,
      );
      if (r.isOk) porCenario[e.key] = r.unwrap();
    }
    if (porCenario.length != cenarios.length) continue;
    final base = porCenario['semCusto']!;
    linhas.add({
      'ativos': [for (final t in ativos) t.value],
      'aportado': base.totalContributed.reais,
      for (final e in porCenario.entries)
        e.key: {
          'patrimonioFinal': e.value.finalValue.reais,
          'xirr': e.value.metrics.moneyWeightedReturn,
          'custos': e.value.transactionCosts.reais,
        },
    });
  }

  double mediana(List<double> xs) {
    final s = [...xs]..sort();
    return s.isEmpty ? double.nan : s[s.length ~/ 2];
  }

  final resumo = <String, Object?>{'carteiras': linhas.length};
  for (final k in ['tarifaB3', 'tarifaEMeioSpread']) {
    final perdaPatrimonio = <double>[];
    final perdaXirr = <double>[];
    final custoSobreAportado = <double>[];
    for (final l in linhas) {
      final b = l['semCusto']! as Map<String, Object?>;
      final x = l[k]! as Map<String, Object?>;
      perdaPatrimonio.add((x['patrimonioFinal']! as double) /
              (b['patrimonioFinal']! as double) -
          1);
      final xb = b['xirr'] as double?, xx = x['xirr'] as double?;
      if (xb != null && xx != null) perdaXirr.add(xx - xb);
      custoSobreAportado
          .add((x['custos']! as double) / (l['aportado']! as double));
    }
    resumo[k] = {
      'variacaoDoPatrimonioFinalMediana': mediana(perdaPatrimonio),
      'variacaoDoXirrMediana': mediana(perdaXirr),
      'piorVariacaoDoXirr': perdaXirr.isEmpty ? null : perdaXirr.reduce(math.min),
      'custoSobreAportadoMediano': mediana(custoSobreAportado),
    };
  }
  File('docs/validacao/custos_simulacao.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert({
      'semente': _semente,
      'janela': '${janela.start.toIso8601String().substring(0, 10)} a '
          '${janela.end.toIso8601String().substring(0, 10)}',
      'plano': 'R\$ 10.000 inicial e R\$ 1.000 por mês',
      'resumo': resumo,
      'carteiras': linhas,
    }),
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(resumo));
  await c.ctx.dispose();
}
