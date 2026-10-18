// Item B4 — o ajuste por tamanho no custo de capital.
//
// **A pergunta.** O CAPM do motor é de fator único: não há prêmio por tamanho,
// e um pequeno e um grande de mesmo beta pagam o mesmo custo de capital. A
// literatura de fatores diz que pequenos rendem mais; a pergunta desta medição
// é se, **neste universo e neste motor**, o tamanho ainda carrega algo que o
// beta não carrega.
//
// **O que esta ferramenta mede.**
//
//   1. **Se o beta já cobra o tamanho**: a relação de postos entre valor de
//      mercado, beta, taxa de desconto e potencial no universo avaliado.
//   2. **O perfil por tercil de tamanho**: beta, desconto e potencial medianos.
//   3. **O efeito de um prêmio explícito** de 2 p.p. no tercil menor — sobre
//      nível, cobertura e ordenação.
//
// A medição **não** é de retorno realizado: isso é coorte, e depende da base
// bruta (item C5). É sobre o que o motor de hoje já cobra, e sobre o que um
// ajuste mudaria.
//
//   dart run tool/gabarito_cascata.dart   # congela a entrada
//   dart run tool/tamanho.dart            # grava tamanho.json
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';
import 'validation/regression.dart';

const _reference = 0.055;

/// O prêmio a somar no tercil menor, na medição do efeito. Dois pontos é a
/// ordem de grandeza do prêmio por tamanho na literatura de fatores — e é
/// grande o bastante para que, se nada se mover aqui, nada se mova nunca.
const _sizePremium = 0.02;
const _output = 'docs/validacao/tamanho.json';

double _q(List<double> v, double p) {
  if (v.isEmpty) return double.nan;
  final o = [...v]..sort();
  return o[(o.length * p).floor().clamp(0, o.length - 1)];
}

double _median(List<double> v) => _q(v, 0.5);

class _Asset {
  _Asset({
    required this.ticker,
    required this.marketValueOf,
    required this.beta,
    required this.discount,
    required this.upside,
    required this.fairValueCents,
  });
  final String ticker;
  final double marketValueOf;
  final double beta;
  final double discount;
  final double upside;
  final int fairValueCents;
}

Future<void> main(List<String> args) async {
  final c = await Frozen.build();
  try {
    final assets = <_Asset>[];
    final evaluated = <Ticker, ValuationResult?>{};
    var i = 0;
    for (final t in c.universe) {
      i++;
      if (i % 50 == 0) stderr.write('  $i/${c.universe.length}   \r');
      final prep = await c.prepare(t);
      if (prep.isErr) continue;
      final inputs = prep.unwrap();
      final r = ValuationCascade.evaluate(inputs);
      evaluated[t] = r.valueOrNull;
      if (r.isErr) continue;
      final v = r.unwrap();
      // O valor de mercado da fonte, que é o que existe na data congelada. Ele
      // erra em alguns tickers (decisão 83) e por isso **não entra em conta de
      // dinheiro** aqui: entra só na **ordenação** por tamanho, onde um erro de
      // escala não troca tercil.
      final marketValue = inputs.fundamentals.isEmpty
          ? null
          : inputs.fundamentals.last.marketCap;
      if (marketValue == null || marketValue <= 0) continue;
      assets.add(_Asset(
        ticker: t.value,
        marketValueOf: marketValue,
        beta: inputs.capm.beta,
        discount: v.discountRate,
        upside: v.upside,
        fairValueCents: v.fairValue.cents,
      ));
    }
    stderr.write('                              \r');

    final div = await c.checkAgainstAnswerKey(evaluated);
    if (div == null) {
      stderr.writeln('AVISO: gabarito ausente; montagem não conferida.');
    } else if (div.isNotEmpty) {
      stderr.writeln('ERRO: montagem diverge do gabarito em ${div.length}: '
          '${div.take(8).join(", ")}');
      exitCode = 1;
      return;
    } else {
      stdout.writeln('montagem conferida contra o gabarito: zero '
          'divergências.');
    }

    assets.sort((a, b) => a.marketValueOf.compareTo(b.marketValueOf));
    final n = assets.length;
    final logMarketValue = [for (final a in assets) math.log(a.marketValueOf)];

    stdout.writeln('');
    stdout.writeln('-- o tamanho contra o que o motor já cobra ($n avaliados) --');
    final rhoBeta =
        Regression.spearman(logMarketValue, [for (final a in assets) a.beta]);
    final rhoDiscount =
        Regression.spearman(logMarketValue, [for (final a in assets) a.discount]);
    final rhoUpside =
        Regression.spearman(logMarketValue, [for (final a in assets) a.upside]);
    stdout.writeln('  postos de log(valor de mercado) contra');
    stdout.writeln('    beta                ${_f(rhoBeta)}');
    stdout.writeln('    taxa de desconto    ${_f(rhoDiscount)}');
    stdout.writeln('    potencial           ${_f(rhoUpside)}');

    // Tercis, do menor para o maior.
    final cut = [0, n ~/ 3, 2 * n ~/ 3, n];
    final names = ['menor', 'meio', 'maior'];
    final terciles = <Map<String, dynamic>>[];
    stdout.writeln('');
    stdout.writeln('-- o perfil por tercil de tamanho --');
    stdout.writeln('  tercil   n   valor de mercado mediano   beta   desconto '
        '  potencial');
    for (var k = 0; k < 3; k++) {
      final band = assets.sublist(cut[k], cut[k + 1]);
      final medianMarketValue = _median([for (final a in band) a.marketValueOf]);
      final betaMed = _median([for (final a in band) a.beta]);
      final descMed = _median([for (final a in band) a.discount]);
      final medianUpside = _median([for (final a in band) a.upside]);
      stdout.writeln('  ${names[k].padRight(6)} ${band.length.toString().padLeft(3)}   '
          '${_billions(medianMarketValue).padLeft(22)}   ${betaMed.toStringAsFixed(3)}   '
          '${_pct(descMed).padLeft(7)}   ${_pct(medianUpside).padLeft(8)}');
      terciles.add({
        'tercil': names[k],
        'n': band.length,
        'valorDeMercadoMediano': medianMarketValue,
        'betaMediano': betaMed,
        'descontoMediano': descMed,
        'potencialMediano': medianUpside,
        'tickers': [for (final a in band) a.ticker],
      });
    }

    // ---------------------------------------------------------------------
    // O efeito de um prêmio explícito de tamanho no tercil menor
    // ---------------------------------------------------------------------
    final smallest = {for (final a in assets.sublist(0, cut[1])) a.ticker};
    final withPremium = <String, int>{};
    final upsideWithPremium = <String, double>{};
    i = 0;
    for (final t in c.universe) {
      i++;
      if (i % 50 == 0) stderr.write('  com prêmio: $i/${c.universe.length}   \r');
      final premium =
          smallest.contains(t.value) ? _reference + _sizePremium : _reference;
      final prep = await c.prepare(t, premium: premium);
      if (prep.isErr) continue;
      final r = ValuationCascade.evaluate(prep.unwrap());
      if (r.isErr) continue;
      withPremium[t.value] = r.unwrap().fairValue.cents;
      upsideWithPremium[t.value] = r.unwrap().upside;
    }
    stderr.write('                                   \r');

    final before = {for (final a in assets) a.ticker: a};
    final common = withPremium.keys.where(before.containsKey).toList()..sort();
    final changeList = <double>[
      for (final k in common)
        if (before[k]!.fairValueCents != 0)
          withPremium[k]! / before[k]!.fairValueCents - 1,
    ];
    final smallestChange = <double>[
      for (final k in common)
        if (smallest.contains(k) && before[k]!.fairValueCents != 0)
          withPremium[k]! / before[k]!.fairValueCents - 1,
    ];
    final rhoWithPremium = Regression.spearman(
      [for (final k in common) before[k]!.upside],
      [for (final k in common) upsideWithPremium[k]!],
    );
    final leaving = before.keys.where((k) => !withPremium.containsKey(k)).toList()
      ..sort();

    stdout.writeln('');
    stdout.writeln('-- o efeito de ${_pct(_sizePremium)} no tercil menor --');
    stdout.writeln('  preço justo, no tercil menor   mediana '
        '${_pct(_median(smallestChange))}  (p25 '
        '${_pct(_q(smallestChange, 0.25))}, p75 '
        '${_pct(_q(smallestChange, 0.75))})');
    stdout.writeln('  preço justo, no universo       mediana '
        '${_pct(_median(changeList))}');
    stdout.writeln('  postos do potencial            ${_f(rhoWithPremium)}');
    stdout.writeln('  deixam de ser avaliáveis       ${leaving.length}'
        '${leaving.isEmpty ? "" : " (${leaving.take(6).join(", ")})"}');

    File(_output).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'avaliados': n,
      'spearmanLogValorDeMercado': {
        'beta': rhoBeta,
        'desconto': rhoDiscount,
        'potencial': rhoUpside,
      },
      'tercis': terciles,
      'premioDeTamanho': {
        'premio': _sizePremium,
        'aplicadoEm': smallest.length,
        'precoJustoMedianoNoTercilMenor': _median(smallestChange),
        'precoJustoMedianoNoUniverso': _median(changeList),
        'spearmanPotencial': rhoWithPremium,
        'saem': leaving,
      },
    }));
    stdout.writeln('');
    stdout.writeln('escrito $_output');
  } finally {
    await c.ctx.dispose();
  }
}

String _f(double? v) => v == null ? '—' : v.toStringAsFixed(4);
String _pct(double v) =>
    v.isNaN ? '  —  ' : '${(v * 100).toStringAsFixed(2)}%';
String _billions(double v) =>
    v.isFinite ? 'R\$ ${(v / 1e9).toStringAsFixed(2)} bi' : '   —  ';
