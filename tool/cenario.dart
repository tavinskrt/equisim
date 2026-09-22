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

const _saida = 'docs/validacao/cenario.json';

double _q(List<double> v, double p) {
  if (v.isEmpty) return double.nan;
  final o = [...v]..sort();
  return o[(o.length * p).floor().clamp(0, o.length - 1)];
}

double _mediana(List<double> v) => _q(v, 0.5);

class _Leitura {
  final Map<String, int> justoCentavos = {};
  final Map<String, double> largura = {};
  final Map<String, double> assimetria = {};
  int baseForaDoJusto = 0;
}

Future<void> main(List<String> args) async {
  final c = await Congelado.montar();
  try {
    final leituras = {
      for (final t in ScenarioTranslation.values) t: _Leitura(),
    };
    final avaliadas = <Ticker, ValuationResult?>{};
    final naViaDaFirma = <String>{};

    var i = 0;
    for (final t in c.universo) {
      i++;
      if (i % 50 == 0) stderr.write('  $i/${c.universo.length}   \r');
      final prep = await c.preparar(t);
      if (prep.isErr) continue;
      final b = prep.unwrap();

      for (final leitura in ScenarioTranslation.values) {
        final r = ValuationCascade.evaluate(_com(b, leitura));
        if (leitura == ScenarioTranslation.umPorUm) {
          avaliadas[t] = r.valueOrNull;
        }
        if (r.isErr) continue;
        final v = r.unwrap();
        final l = leituras[leitura]!;
        l.justoCentavos[t.value] = v.fairValue.cents;
        if (leitura == ScenarioTranslation.umPorUm &&
            v.model == ValuationModel.dcfFcff) {
          naViaDaFirma.add(t.value);
        }

        final cenarios = v.discreteScenarios;
        final justo = v.fairValue.cents;
        if (cenarios == null || justo <= 0) continue;
        final bear = cenarios[ScenarioBand.bear]?.cents;
        final baseC = cenarios[ScenarioBand.base]?.cents;
        final bull = cenarios[ScenarioBand.bull]?.cents;
        if (bear == null || baseC == null || bull == null) continue;
        // **A pós-condição da decisão 105**: o cenário base é o preço justo.
        // Nenhuma tradução pode quebrá-la — se quebrar, a faixa cerca outro
        // número, e a medição de largura não quer dizer nada.
        if (baseC != justo) l.baseForaDoJusto++;
        l.largura[t.value] = (bull - bear) / justo;
        // Quanto da faixa fica de cada lado do preço justo. Tradução que só
        // multiplica o deslocamento não pode mover isto muito — se mover, o
        // efeito não é de escala.
        //
        // **Faixa de um lado só não tem assimetria a medir**: com o cenário
        // pessimista no próprio preço justo o denominador é zero, e a divisão
        // devolveria `Infinity`, que o `JsonEncoder` recusa e a mediana
        // contamina. O ativo sai da conta em vez de entrar com um número
        // inventado.
        final abaixo = justo - bear;
        if (abaixo > 0) {
          l.assimetria[t.value] = (bull - justo) / abaixo;
        }
      }
    }
    stderr.write('                              \r');

    final div = await c.conferirContraGabarito(avaliadas);
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

    final base = leituras[ScenarioTranslation.umPorUm]!;
    final linhas = <Map<String, Object?>>[];

    stdout.writeln('');
    stdout.writeln('-- a largura da faixa sob cada leitura --');
    stdout.writeln(
      '  leitura             com faixa   largura (p25/med/p75)      '
      '  vs um a um   base ≠ justo   preço justo muda',
    );

    for (final leitura in ScenarioTranslation.values) {
      final l = leituras[leitura]!;
      // **Só a via da firma importa**: na do acionista o campo perturbado já é
      // o `Ke`, e as três leituras devolvem o mesmo número.
      final chaves = l.largura.keys.where(naViaDaFirma.contains).toList()
        ..sort();
      final larguras = [for (final k in chaves) l.largura[k]!];
      final razao = <double>[
        for (final k in chaves)
          if (base.largura[k] != null && base.largura[k]! > 0)
            l.largura[k]! / base.largura[k]!,
      ];
      final mudam = chaves
          .where(
            (k) =>
                base.justoCentavos[k] != null &&
                l.justoCentavos[k] != base.justoCentavos[k],
          )
          .length;

      final vsUmPorUm = razao.isEmpty
          ? '   —  '
          : '${_mediana(razao).toStringAsFixed(3)}×';
      stdout.writeln(
        '  ${leitura.name.padRight(18)}  '
        '${chaves.length.toString().padLeft(9)}   '
        '${_pct(_q(larguras, 0.25))} / ${_pct(_mediana(larguras))} / '
        '${_pct(_q(larguras, 0.75))}   '
        '${vsUmPorUm.padLeft(12)}   '
        '${l.baseForaDoJusto.toString().padLeft(12)}   '
        '${mudam.toString().padLeft(16)}',
      );

      // `_q` devolve `NaN` sobre lista vazia, e `NaN` não é JSON: onde não há
      // largura a declarar, o campo é `null`.
      double? ouNulo(double v) => v.isFinite ? v : null;

      linhas.add({
        'leitura': leitura.name,
        'comFaixa': chaves.length,
        'larguraP25': ouNulo(_q(larguras, 0.25)),
        'larguraMediana': ouNulo(_mediana(larguras)),
        'larguraP75': ouNulo(_q(larguras, 0.75)),
        'razaoMedianaContraUmPorUm': razao.isEmpty ? null : _mediana(razao),
        'baseForaDoJusto': l.baseForaDoJusto,
        'precoJustoMuda': mudam,
        // Só quem tem assimetria medida entra na mediana dela — e o `null`
        // diz que nenhum tinha, em vez de um `NaN` que o JSON não carrega.
        'assimetriaMediana': () {
          final v = <double>[
            for (final k in chaves)
              if (l.assimetria[k] != null) l.assimetria[k]!,
          ];
          return v.isEmpty ? null : _mediana(v);
        }(),
        // Quem tinha faixa no um a um e perde com esta leitura: amplificar o
        // deslocamento empurra o cenário otimista para uma perpetuidade que
        // diverge, e o ativo fica sem faixa.
        'perdemAFaixa':
            (naViaDaFirma
                .where(base.largura.containsKey)
                .where((k) => !l.largura.containsKey(k))
                .toList()
              ..sort()),
      });
    }

    File(_saida).writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'naViaDaFirma': naViaDaFirma.length, 'leituras': linhas}),
    );
    stdout.writeln('');
    stdout.writeln('escrito $_saida');
  } finally {
    await c.ctx.dispose();
  }
}

ValuationInputs _com(ValuationInputs b, ScenarioTranslation leitura) =>
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
      scenarioTranslation: leitura,
    );

String _pct(double v) =>
    v.isNaN ? '   —  ' : '${(v * 100).toStringAsFixed(1).padLeft(6)}%';
