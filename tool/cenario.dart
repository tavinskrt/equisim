// Item B20 — a tradução do cenário de desconto para o `Ke` da rota derivada.
//
// **A pergunta.** O cenário perturba `DcfAssumptions.discountRate`. Na via do
// acionista esse campo **é** o `Ke`, e o deslocamento é um a um por construção.
// Na via da firma ele é o WACC, e a rota derivada desconta ao `Ke`: traduzir
// exige escolher o que o cenário está perturbando, e ele não diz.
//
// **As três leituras, e o fator de cada uma:**
//
//   um a um          `ΔK_e = ΔWACC`                 — a taxa aplicada ao fluxo
//   estrutura fixa   `ΔK_e = ΔWACC ÷ w_E`           — o custo de capital da firma
//   taxa livre       `ΔK_e = ΔWACC ÷ (1 − w_D·t)`   — o `R_f`, movendo os dois
//
// **O que esta ferramenta mede** é a largura da faixa de sensibilidade sob cada
// uma, no universo, e se o preço justo do cenário **base** volta ao preço justo
// — que é a pós-condição que a decisão 105 fixou e que nenhuma tradução pode
// quebrar.
//
//   dart run tool/gabarito_cascata.dart   # congela a entrada
//   dart run tool/cenario.dart            # grava cenario.json
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';

const _output = 'docs/validacao/cenario.json';

double _q(List<double> v, double p) {
  if (v.isEmpty) return double.nan;
  final o = [...v]..sort();
  return o[(o.length * p).floor().clamp(0, o.length - 1)];
}

double _median(List<double> v) => _q(v, 0.5);

class _Reading {
  final Map<String, int> fairValueCents = {};
  final Map<String, double> width = {};
  final Map<String, double> asymmetry = {};
  int baseOutsideFair = 0;
}

Future<void> main(List<String> args) async {
  final c = await Frozen.build();
  try {
    final readings = {
      for (final t in ScenarioTranslation.values) t: _Reading(),
    };
    final evaluated = <Ticker, ValuationResult?>{};
    final onFirmLane = <String>{};

    var i = 0;
    for (final t in c.universe) {
      i++;
      if (i % 50 == 0) stderr.write('  $i/${c.universe.length}   \r');
      final prep = await c.prepare(t);
      if (prep.isErr) continue;
      final b = prep.unwrap();

      for (final reading in ScenarioTranslation.values) {
        final r = ValuationCascade.evaluate(_withInput(b, reading));
        if (reading == ScenarioTranslation.oneToOne) {
          evaluated[t] = r.valueOrNull;
        }
        if (r.isErr) continue;
        final v = r.unwrap();
        final l = readings[reading]!;
        l.fairValueCents[t.value] = v.fairValue.cents;
        if (reading == ScenarioTranslation.oneToOne &&
            v.model == ValuationModel.dcfFcff) {
          onFirmLane.add(t.value);
        }

        final scenarios = v.discreteScenarios;
        final fairValue = v.fairValue.cents;
        if (scenarios == null || fairValue <= 0) continue;
        final bear = scenarios[ScenarioBand.bear]?.cents;
        final baseC = scenarios[ScenarioBand.base]?.cents;
        final bull = scenarios[ScenarioBand.bull]?.cents;
        if (bear == null || baseC == null || bull == null) continue;
        // **A pós-condição da decisão 105**: o cenário base é o preço justo.
        // Nenhuma tradução pode quebrá-la — se quebrar, a faixa cerca outro
        // número, e a medição de largura não quer dizer nada.
        if (baseC != fairValue) l.baseOutsideFair++;
        l.width[t.value] = (bull - bear) / fairValue;
        // Quanto da faixa fica de cada lado do preço justo. Tradução que só
        // multiplica o deslocamento não pode mover isto muito — se mover, o
        // efeito não é de escala.
        //
        // **Faixa de um lado só não tem assimetria a medir**: com o cenário
        // pessimista no próprio preço justo o denominador é zero, e a divisão
        // devolveria `Infinity`, que o `JsonEncoder` recusa e a mediana
        // contamina. O ativo sai da conta em vez de entrar com um número
        // inventado.
        final below = fairValue - bear;
        if (below > 0) {
          l.asymmetry[t.value] = (bull - fairValue) / below;
        }
      }
    }
    stderr.write('                              \r');

    final div = await c.checkAgainstAnswerKey(evaluated);
    if (div == null) {
      stderr.writeln('AVISO: gabarito ausente; montagem não conferida.');
    } else if (div.isNotEmpty) {
      stderr.writeln(
        'ERRO: a leitura de hoje diverge do gabarito em '
        '${div.length}: ${div.take(8).join(", ")}',
      );
      exitCode = 1;
      return;
    } else {
      stdout.writeln(
        'leitura de hoje conferida contra o gabarito: zero '
        'divergências.',
      );
    }

    final base = readings[ScenarioTranslation.oneToOne]!;
    final rows = <Map<String, Object?>>[];

    stdout.writeln('');
    stdout.writeln('-- a largura da faixa sob cada leitura --');
    stdout.writeln(
      '  leitura             com faixa   largura (p25/med/p75)      '
      '  vs um a um   base ≠ justo   preço justo muda',
    );

    for (final reading in ScenarioTranslation.values) {
      final l = readings[reading]!;
      // **Só a via da firma importa**: na do acionista o campo perturbado já é
      // o `Ke`, e as três leituras devolvem o mesmo número.
      final keys = l.width.keys.where(onFirmLane.contains).toList()
        ..sort();
      final widths = [for (final k in keys) l.width[k]!];
      final ratio = <double>[
        for (final k in keys)
          if (base.width[k] != null && base.width[k]! > 0)
            l.width[k]! / base.width[k]!,
      ];
      final changing = keys
          .where(
            (k) =>
                base.fairValueCents[k] != null &&
                l.fairValueCents[k] != base.fairValueCents[k],
          )
          .length;

      final vsOneToOne = ratio.isEmpty
          ? '   —  '
          : '${_median(ratio).toStringAsFixed(3)}×';
      stdout.writeln(
        '  ${reading.key.padRight(18)}  '
        '${keys.length.toString().padLeft(9)}   '
        '${_pct(_q(widths, 0.25))} / ${_pct(_median(widths))} / '
        '${_pct(_q(widths, 0.75))}   '
        '${vsOneToOne.padLeft(12)}   '
        '${l.baseOutsideFair.toString().padLeft(12)}   '
        '${changing.toString().padLeft(16)}',
      );

      // `_q` devolve `NaN` sobre lista vazia, e `NaN` não é JSON: onde não há
      // largura a declarar, o campo é `null`.
      double? orNull(double v) => v.isFinite ? v : null;

      rows.add({
        'leitura': reading.key,
        'comFaixa': keys.length,
        'larguraP25': orNull(_q(widths, 0.25)),
        'larguraMediana': orNull(_median(widths)),
        'larguraP75': orNull(_q(widths, 0.75)),
        'razaoMedianaContraUmPorUm': ratio.isEmpty ? null : _median(ratio),
        'baseForaDoJusto': l.baseOutsideFair,
        'precoJustoMuda': changing,
        // Só quem tem assimetria medida entra na mediana dela — e o `null`
        // diz que nenhum tinha, em vez de um `NaN` que o JSON não carrega.
        'assimetriaMediana': () {
          final v = <double>[
            for (final k in keys)
              if (l.asymmetry[k] != null) l.asymmetry[k]!,
          ];
          return v.isEmpty ? null : _median(v);
        }(),
        // Quem tinha faixa no um a um e perde com esta leitura: amplificar o
        // deslocamento empurra o cenário otimista para uma perpetuidade que
        // diverge, e o ativo fica sem faixa.
        'perdemAFaixa':
            (onFirmLane
                .where(base.width.containsKey)
                .where((k) => !l.width.containsKey(k))
                .toList()
              ..sort()),
      });
    }

    File(_output).writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'naViaDaFirma': onFirmLane.length, 'leituras': rows}),
    );
    stdout.writeln('');
    stdout.writeln('escrito $_output');
  } finally {
    await c.ctx.dispose();
  }
}

ValuationInputs _withInput(ValuationInputs b, ScenarioTranslation reading) =>
    ValuationInputs(
      ticker: b.ticker,
      asOf: b.asOf,
      fundamentals: b.fundamentals,
      marketPrice: b.marketPrice,
      capm: b.capm,
      marginOfSafety: b.marginOfSafety,
      projectionYears: b.projectionYears,
      perpetualGrowthCap: b.perpetualGrowthCap,
      sectorKey: b.sectorKey,
      industry: b.industry,
      inflation: b.inflation,
      declaredTerminalRiskFreeRate: b.declaredTerminalRiskFreeRate,
      riskFreeCurve: b.riskFreeCurve,
      officialShares: b.officialShares,
      prices: b.prices,
      isDistressed: b.isDistressed,
      unleveredBeta: b.unleveredBeta,
      concessionEnd: b.concessionEnd,
      dividendsInBeta: b.dividendsInBeta,
      creditReferenceRiskFree: b.creditReferenceRiskFree,
      declaredSharesPerUnit: b.declaredSharesPerUnit,
      betaWindowYears: b.betaWindowYears,
      scenarioTranslation: reading,
    );

String _pct(double v) =>
    v.isNaN ? '   —  ' : '${(v * 100).toStringAsFixed(1).padLeft(6)}%';
