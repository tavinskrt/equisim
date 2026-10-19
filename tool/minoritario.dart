// Item B23 — o minoritário nos pesos do custo médio de capital.
//
// **A acusação da lente `metodo`.** O fluxo que o WACC desconta é o
// **consolidado**, e o peso do capital próprio é `divisor × preço`, que é o
// valor de mercado da **controladora**. A fatia dos não controladores fica fora
// do denominador `E + D`, o que infla a participação da dívida e achata o WACC.
//
// **A primeira coisa que a medição precisa estabelecer é o escopo**, e ele é
// menor do que a acusação sugere: o caminho **resolvido** pondera pelo capital
// próprio que o modelo produz — `V − D` sobre um fluxo consolidado —, que já
// inclui o minoritário. Só o WACC **estático**, que é o recuo, fica de fora.
//
// **Duas formas de introduzi-lo, e a ferramenta mede as duas:**
//
//   (a) **contábil puro** — soma `minorityInterest` ao `E` de mercado, e o
//       denominador passa a ter duas unidades.
//   (b) **pelo `P/VP` do controlador** — supõe que o minoritário negocia à
//       mesma razão preço/patrimônio que o controlador, e soma
//       `PL_min × (E_mercado ÷ PL_contr)`. Não mistura unidades.
//
//   dart run tool/gabarito_cascata.dart   # congela a entrada
//   dart run tool/minoritario.dart        # grava minoritario.json
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';
import 'validation/regression.dart';

const _output = 'docs/validacao/minoritario.json';

/// Fração do patrimônio consolidado a partir da qual o minoritário é
/// **material**. Abaixo de 1% qualquer tratamento dele muda o terceiro decimal
/// da taxa, e a pergunta não é sobre esses.
const _materiality = 0.01;

double _q(List<double> v, double p) {
  if (v.isEmpty) return double.nan;
  final o = [...v]..sort();
  return o[(o.length * p).floor().clamp(0, o.length - 1)];
}

double _median(List<double> v) => _q(v, 0.5);

enum _Form implements WireKeyed {
  today('hoje'),
  book('contabil'),
  byRatio('pelaRazao');

  const _Form(this.key);

  /// Chave gravada nas saídas — pacote de dados, rastro de auditoria,
  /// relatório. É dado, e não nome de código: renomear o valor não a muda.
  @override
  final String key;
}

class _Reading {
  final Map<String, int> fairValueCents = {};
  final Map<String, double> upside = {};
  final Map<String, double> discount = {};
}

Future<void> main(List<String> args) async {
  final c = await Frozen.build();
  try {
    final slice = <String, double>{};
    final staticSet = <String>{};
    final firmLane = <String>{};
    final readings = {for (final f in _Form.values) f: _Reading()};
    final evaluated = <Ticker, ValuationResult?>{};

    var i = 0;
    for (final t in c.universe) {
      i++;
      if (i % 50 == 0) stderr.write('  $i/${c.universe.length}   \r');
      final prep = await c.prepare(t);
      if (prep.isErr) continue;
      final b = prep.unwrap();
      if (b.fundamentals.isEmpty) continue;
      final f = b.fundamentals.last;

      final controllingEquity = f.totalStockholderEquity;
      final minority = f.minorityInterest;
      final consolidated = (controllingEquity ?? 0) + (minority ?? 0);
      final ratio = (minority == null ||
              minority <= 0 ||
              controllingEquity == null ||
              controllingEquity <= 0 ||
              consolidated <= 0)
          ? null
          : minority / consolidated;

      for (final form in _Form.values) {
        final r = ValuationCascade.evaluate(
            _withInput(b, form, minority, controllingEquity));
        if (form == _Form.today) evaluated[t] = r.valueOrNull;
        if (r.isErr) continue;
        final v = r.unwrap();
        readings[form]!.fairValueCents[t.value] = v.fairValue.cents;
        readings[form]!.upside[t.value] = v.upside;
        readings[form]!.discount[t.value] = v.discountRate;
        // **Quem usa o WACC estático é quem não resolveu as taxas**, e é só
        // nele que o peso do minoritário falta. O aviso da avaliação é o que
        // separa os dois caminhos sem reimplementar a cascata.
        if (form == _Form.today) {
          if (!v.warnings.any((w) => w.contains('resolvido ano a ano'))) {
            staticSet.add(t.value);
          }
          // **E a via do acionista não tem WACC nenhum**: o fluxo dela é do
          // acionista da controladora, descontado ao `Ke`, e o minoritário não
          // entra em peso porque não há peso. Sem este corte, a contagem de
          // expostos junta banco com companhia operacional.
          if (v.model == ValuationModel.dcfFcff) firmLane.add(t.value);
        }
      }
      if (ratio != null &&
          readings[_Form.today]!.fairValueCents.containsKey(t.value)) {
        slice[t.value] = ratio;
      }
    }
    stderr.write('                              \r');

    final div = await c.checkAgainstAnswerKey(evaluated);
    if (div == null) {
      stderr.writeln('AVISO: gabarito ausente; montagem não conferida.');
    } else if (div.isNotEmpty) {
      stderr.writeln('ERRO: a montagem de hoje diverge do gabarito em '
          '${div.length}: ${div.take(8).join(", ")}');
      exitCode = 1;
      return;
    } else {
      stdout.writeln('montagem de hoje conferida contra o gabarito: zero '
          'divergências.');
    }

    final base = readings[_Form.today]!;
    final material =
        slice.entries.where((e) => e.value >= _materiality).map((e) => e.key);
    // **O conjunto exposto é a interseção das três condições**: via da firma
    // (tem WACC), recuo estático (o peso é de mercado da controladora) e
    // minoritário material.
    final exposed = material
        .where(staticSet.contains)
        .where(firmLane.contains)
        .toSet();

    stdout.writeln('');
    stdout.writeln('-- o escopo do defeito --');
    stdout.writeln('  avaliados                          '
        '${base.fairValueCents.length}');
    stdout.writeln('  pela via da firma (têm WACC)       '
        '${firmLane.length}');
    stdout.writeln('  usam o WACC estático               ${staticSet.length}');
    stdout.writeln('  via da firma E estático            '
        '${firmLane.where(staticSet.contains).length}');
    stdout.writeln('  têm minoritário publicado          ${slice.length}');
    stdout.writeln('  com fatia ≥ ${(_materiality * 100).toStringAsFixed(0)}%'
        '                     ${material.length}');
    stdout.writeln('  **firma, estático E material**     ${exposed.length}'
        '${exposed.isEmpty ? "" : "  (${exposed.take(10).join(", ")})"}');
    final slices = slice.values.toList();
    if (slices.isNotEmpty) {
      stdout.writeln('  fatia do minoritário: p50 ${_pct(_median(slices))}  '
          'p90 ${_pct(_q(slices, 0.90))}  '
          'máx ${_pct(slices.reduce((a, b) => a > b ? a : b))}');
    }

    final rows = <Map<String, Object?>>[];
    stdout.writeln('');
    stdout.writeln('-- o efeito de pôr o minoritário no peso --');
    stdout.writeln('  forma         avaliados   justo (todos)   '
        'justo (expostos)   Δ desconto (expostos)   postos');

    for (final form in _Form.values) {
      if (form == _Form.today) continue;
      final l = readings[form]!;
      final common = l.fairValueCents.keys
          .where(base.fairValueCents.containsKey)
          .toList()
        ..sort();
      double? varianceOf(Iterable<String> keys) {
        final v = <double>[
          for (final k in keys)
            if (base.fairValueCents[k] != null &&
                base.fairValueCents[k] != 0 &&
                l.fairValueCents[k] != null)
              l.fairValueCents[k]! / base.fairValueCents[k]! - 1,
        ];
        return v.isEmpty ? null : _median(v);
      }

      final discountDelta = <double>[
        for (final k in common)
          if (exposed.contains(k)) l.discount[k]! - base.discount[k]!,
      ];
      final rho = common.length < 3
          ? null
          : Regression.spearman(
              [for (final k in common) base.upside[k]!],
              [for (final k in common) l.upside[k]!],
            );
      final leaving = base.fairValueCents.keys
          .where((k) => !l.fairValueCents.containsKey(k))
          .toList()
        ..sort();

      stdout.writeln('  ${form.key.padRight(12)}  '
          '${l.fairValueCents.length.toString().padLeft(9)}   '
          '${_pct(varianceOf(common) ?? double.nan).padLeft(13)}   '
          '${_pct(varianceOf(exposed) ?? double.nan).padLeft(16)}   '
          '${discountDelta.isEmpty ? "         —      " : "${(_median(discountDelta) * 100).toStringAsFixed(2).padLeft(13)} p.p."}   '
          '${rho == null ? "  —   " : rho.toStringAsFixed(4)}');

      rows.add({
        'forma': form.key,
        'avaliados': l.fairValueCents.length,
        'justoMedianoTodos': varianceOf(common),
        'justoMedianoExpostos': varianceOf(exposed),
        'deltaDescontoMedianoExpostos':
            discountDelta.isEmpty ? null : _median(discountDelta),
        'spearmanPotencial': rho,
        'saem': leaving,
      });
    }

    File(_output).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'materialidade': _materiality,
      'avaliados': base.fairValueCents.length,
      'usamWaccEstatico': staticSet.length,
      'viaDaFirma': firmLane.length,
      'viaDaFirmaEEstatico':
          (firmLane.where(staticSet.contains).toList()..sort()),
      'comMinoritario': slice.length,
      'comFatiaMaterial': material.length,
      'estaticoEMaterial': exposed.toList()..sort(),
      'fatia': {
        'p50': slices.isEmpty ? null : _median(slices),
        'p90': slices.isEmpty ? null : _q(slices, 0.90),
        'maximo':
            slices.isEmpty ? null : slices.reduce((a, b) => a > b ? a : b),
      },
      'maioresFatias': Map.fromEntries(
        (slice.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(15),
      ),
      'formas': rows,
    }));
    stdout.writeln('');
    stdout.writeln('escrito $_output');
  } finally {
    await c.ctx.dispose();
  }
}

/// Os mesmos insumos, com o minoritário somado ao peso do capital próprio.
ValuationInputs _withInput(
  ValuationInputs b,
  _Form form,
  double? minority,
  double? controllingEquity,
) {
  if (form == _Form.today) return b;
  if (minority == null || minority <= 0) return b;
  if (controllingEquity == null || controllingEquity <= 0) return b;

  // O valor de mercado da controladora, pela mesma contagem que a ponte
  // arbitra — é o que está no denominador hoje.
  final divisor = ValuationCascade.quotedShares(
    latest: b.fundamentals.last,
    marketPrice: b.marketPrice,
    sharesPerQuote: b.declaredSharesPerUnit?.toDouble() ?? 1.0,
    published: b.fundamentals,
    official: b.officialShares,
    asOf: b.asOf,
  );
  if (divisor == null || divisor.count <= 0) return b;
  final market = divisor.count * b.marketPrice;

  final value = switch (form) {
    _Form.today => 0.0,
    // Contábil puro: o valor de livro entra num denominador de mercado.
    _Form.book => minority,
    // Pelo `P/VP` do controlador: `PL_min × (E_mercado ÷ PL_contr)`. Coincide
    // com a contábil quando o `P/VP` é 1, e difere dela exatamente por ele.
    _Form.byRatio => minority * (market / controllingEquity),
  };

  return ValuationInputs(
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
    minorityEquityValue: value,
  );
}

String _pct(double v) =>
    v.isNaN ? '   —  ' : '${(v * 100).toStringAsFixed(2)}%';
