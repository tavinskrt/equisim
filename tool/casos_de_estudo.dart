// Os casos da documentação de estudo (`docs/estudo/casos/`), com tudo o que o
// aplicativo calcula para cada ativo, sobre a entrada congelada do gabarito
// (14/09/2026): insumos, CAPM, curva, exercícios publicados, resultado,
// cenários, Monte Carlo, faixa calibrada, múltiplos, ressalvas, avisos e o
// rastro de auditoria inteiro — o mesmo do painel de logs.
//
// A entrada é congelada, então a saída só muda quando o motor muda. Os casos
// escritos citam estes números: depois de mudar o motor, rode de novo e
// confira os documentos.
//
// Uso:
//   dart run tool/casos_de_estudo.dart                     # os cinco casos
//   dart run tool/casos_de_estudo.dart <pasta> PETR4 ...   # outros ativos
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';

Future<void> main(List<String> args) async {
  final saida = args.isEmpty ? 'docs/estudo/casos/dados' : args.first;
  final alvos =
      (args.length > 1
              ? args.skip(1)
              : const ['WEGE3', 'ITUB4', 'VALE3', 'SAPR11', 'RENT3'])
          .map(Ticker.parse)
          .toList();
  final c = await Congelado.montar();
  Map<String, dynamic> ler(String p) =>
      jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;
  final pares = PeerMultipleCodec.decode(
    ler('assets/mercado/multiplos_setoriais.json'),
  );
  final faixas = CalibratedBandCodec.decode(
    ler('assets/validacao/banda_calibrada.json'),
  );
  Directory(saida).createSync(recursive: true);

  for (final t in alvos) {
    final prep = await c.preparar(t);
    if (prep.isErr) {
      stdout.writeln(
        '${t.value}: preparo falhou ${prep.failureOrNull?.message}',
      );
      continue;
    }
    final insumos = prep.unwrap().withPeerMultiples(pares[t.value]);
    AuditEvent? ev;
    AuditRecorder.attach((e) => ev = e);
    final r = ValuationCascade.evaluate(insumos);
    AuditRecorder.detach();
    Map<String, dynamic>? mc;
    if (r.isOk) {
      final m = ValuationCascade.evaluate(
        insumos,
        scenarioBuilder: StochasticScenarios.around,
      );
      final d = m.valueOrNull?.distribution;
      if (d != null && !d.isEmpty) {
        mc = {
          for (final p in [0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95])
            'p${(p * 100).round()}': d.percentile(p),
          'n': d.sortedValues.length,
        };
      }
    }
    final curva = insumos.riskFreeCurve;
    final ultimos = insumos.fundamentals
        .where((f) => PointInTimeView(insumos.asOf).isPublished(f))
        .toList();
    final res = r.valueOrNull;
    final json = <String, dynamic>{
      'ticker': t.value,
      'asOf': insumos.asOf.toIso8601String().substring(0, 10),
      'preco': insumos.marketPrice,
      'setor': insumos.sectorKey,
      'subsetor': insumos.industry,
      'capm': {
        'rf': insumos.capm.riskFreeRate,
        'beta': insumos.capm.beta,
        'origemBeta': insumos.capm.betaSource.name,
        'premio': insumos.capm.marketPremium,
        'ke': insumos.capm.costOfEquity,
        'betaDesalavancado': insumos.unleveredBeta,
      },
      'ancoras': {
        'inflacao': insumos.inflation,
        'tetoCrescimentoNominal': insumos.perpetualGrowthCap,
        'rfEstruturalDeclarada': insumos.declaredTerminalRiskFreeRate,
        'rfTerminal': insumos.terminalRiskFreeRate,
      },
      'curva': curva == null
          ? null
          : {
              'data': curva.referenceDate.toIso8601String().substring(0, 10),
              'forwards': curva.annualForwards(insumos.projectionYears),
              'terminal': curva.terminalRate(insumos.projectionYears),
              'vertices': [
                for (final v in curva.vertices) [v.years, v.rate],
              ],
            },
      'exercicios': [
        for (final f in ultimos)
          {
            'ano': f.fiscalPeriodEnd.year,
            'receita': f.totalRevenue,
            'ebit': f.ebit,
            'ebitda': f.ebitda,
            'lucroLiquido': f.netIncome,
            'lucroAntesIR': f.incomeBeforeTax,
            'imposto': f.incomeTaxExpense,
            'despesaFinanceira': f.interestExpense,
            'equivalencia': f.equityIncomeResult,
            'vpa': f.bookValuePerShare,
            'acoesExercicio': f.sharesOutstandingAsOf,
            'acoesCorrentes': f.sharesOutstanding,
            'pl': f.equityBookValue,
            'dividaBruta': f.totalDebt,
            'caixa': f.totalCash,
            'dividaLiquida': f.netDebt,
            'capitalInvestido': f.investedCapital,
            'minoritarios': f.minorityInterest,
            'valorDeMercado': f.marketCap,
            'aliquotaEfetiva': f.effectiveTaxRate,
            'cobertura': f.interestCoverage,
            'alavancagem': f.netDebtToEbitda,
            'kdObservado': f.costOfDebt,
            'nopatPublicado': f.nopat,
          },
      ],
      'recusa': r.isErr ? r.failureOrNull?.message : null,
      'resultado': res == null
          ? null
          : {
              'modelo': res.model.name,
              'justo': res.fairValue.reais,
              'preco': res.marketPrice.reais,
              'potencial': res.upside,
              'descontoAno1': res.discountRate,
              'cenarios': res.discreteScenarios?.map(
                (k, v) => MapEntry(k.name, v.reais),
              ),
              'monteCarlo': mc,
              'volatilidade': res.priceVolatility,
              'faixas': [
                for (final meses in const [12, 36])
                  for (final nominal in const [0.5, 0.8, 0.9])
                    if (CalibratedBand.select(
                          faixas,
                          months: meses,
                          nominal: nominal,
                        )
                        case final tab?)
                      {
                        'meses': meses,
                        'nominal': nominal,
                        'coberturaForaDaAmostra': tab.outOfSampleCoverage,
                        if (tab is VolatilityBandTable) ...{
                          'a': tab.a,
                          'b': tab.b,
                          'zInf': tab.zLower,
                          'zSup': tab.zUpper,
                        },
                        'faixa': switch (CalibratedBand.of(
                          res.fairValue,
                          tab,
                          marketPrice: res.marketPrice,
                          volatility: res.priceVolatility,
                        )) {
                          final b? => [b.low.reais, b.high.reais],
                          null => null,
                        },
                      },
              ],
              'ressalvas': [for (final x in res.caveats) x.name],
              'avisos': res.warnings,
              'triangulacao': res.triangulation == null
                  ? null
                  : {
                      'consolidado': res.triangulation!.consolidated,
                      'divergencia': res.triangulation!.divergence,
                      'leituras': [
                        for (final l in res.triangulation!.readings)
                          {
                            'tipo': l.kind.name,
                            'justo': l.fairValuePerShare,
                            'recusa': l.refusal?.name,
                            'mediana': l.peer?.median,
                            'pares': l.peer?.peers,
                            'grupo': l.peer?.group,
                          },
                      ],
                    },
            },
      'rastro': ev == null ? null : AuditJson.safe(ev!.toJson()),
    };
    File(
      '$saida/${t.value}.json',
    ).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(json));
    stdout.writeln(
      '${t.value}: ${res == null ? 'recusa' : 'justo ${res.fairValue} potencial ${res.upside.toStringAsFixed(3)}'}',
    );
  }
}
