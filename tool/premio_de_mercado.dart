// Item B3 — o prêmio de risco de mercado deixa de ser parâmetro.
//
// **A pergunta.** O prêmio é 5,5% fixo, ponto médio de uma faixa de 5–6%
// adotada por convenção. As alternativas que o item nomeia são duas: histórico
// com encolhimento, ou **implícito** — o prêmio que faz o próprio modelo
// concordar com o preço de mercado.
//
// **O que esta ferramenta mede.**
//
//   1. **O histórico**, do Ibovespa contra o CDI na janela que a entrada
//      congelada tem, com o erro-padrão ao lado — porque um prêmio de risco
//      estimado em dez anos é ruído, e o número sem a barra engana.
//   2. **O implícito**, por varredura: o prêmio que zera o potencial **mediano**
//      do universo. É o prêmio que o motor teria de usar para dizer que a ação
//      mediana está no preço.
//
//      A mediana, e não o agregado ponderado pelo valor de mercado: ponderar
//      exigiria a contagem de papéis de cada ativo, que é justamente a grandeza
//      que a ponte arbitra (decisão 83), e o resultado passaria a depender dela.
//      A mediana do potencial é a mesma grandeza que a §0 do plano usa.
//   3. **O efeito de cada candidato** sobre preço justo, cobertura e ordenação.
//
//   dart run tool/gabarito_cascata.dart        # congela a entrada
//   dart run tool/premio_de_mercado.dart       # grava premio_de_mercado.json
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';
import 'validation/regression.dart';

/// A faixa varrida desce a **−6%** de propósito: um prêmio negativo é absurdo
/// econômico — o acionista exigindo menos que o CDI —, e é justamente por isso
/// que interessa saber se o implícito cai lá. Se cair, o desacordo entre motor
/// e mercado não é do prêmio.
const _premiums = [
  -0.06, -0.05, -0.04, -0.03, -0.02, -0.01, 0.0, 0.01, 0.02, 0.03, 0.04, 0.045,
  0.05, 0.055, 0.06, 0.07, 0.08, 0.10,
];
/// Posição de [_premiums] que serve de referência — o 5,5% de hoje.
///
/// **Posição, e não valor**: `double` não serve de chave de mapa nem de
/// critério de igualdade (regra R6). E é constante declarada, e não
/// `indexOf(0.055)`: procurar um `double` numa lista compara por `==` por
/// dentro, que é a mesma regra por outro nome. [_checkReference] impede
/// que a posição e a lista se desencontrem.
const int _referenceIndex = 13;

/// O prêmio de referência, para exibição.
double get _reference => _premiums[_referenceIndex];

/// Falha cedo se alguém mexer em [_premiums] sem mexer em [_referenceIndex].
void _checkReference() {
  if ((_reference - 0.055).abs() > 1e-9) {
    throw StateError('_iReferencia aponta para $_reference, e não para o '
        'prêmio de 5,5% que a montagem do gabarito usa.');
  }
}
const _output = 'docs/validacao/premio_de_mercado.json';

/// Diferença de potencial abaixo da qual dois degraus da varredura são o mesmo
/// número, e a interpolação entre eles não tem o que interpolar.
///
/// Um centésimo de ponto percentual de potencial: a varredura anda de 1 p.p.
/// em prêmio e move o potencial em pontos inteiros, de modo que qualquer coisa
/// abaixo disso é ruído de arredondamento, e não inclinação.
const _plateau = 1e-4;

double _q(List<double> v, double p) {
  if (v.isEmpty) return double.nan;
  final o = [...v]..sort();
  return o[(o.length * p).floor().clamp(0, o.length - 1)];
}

double _median(List<double> v) => _q(v, 0.5);

class _Reading {
  final Map<String, int> fairValueCents = {};
  final Map<String, double> upside = {};
}

Future<void> main(List<String> args) async {
  _checkReference();
  final c = await Frozen.build();
  try {
    // ---------------------------------------------------------------------
    // 1) O histórico, com a barra de erro
    // ---------------------------------------------------------------------
    final indexResult = await c.ctx.benchmark.ibovespa(c.betaWindow);
    if (indexResult.isErr) {
      stderr.writeln('sem índice: ${indexResult.failureOrNull?.message}');
      exitCode = 2;
      return;
    }
    final index = indexResult.unwrap();
    final points = index.points;
    final years = points.last.date.difference(points.first.date).inDays / 365.25;
    final indexCagr =
        math.pow(points.last.close / points.first.close, 1 / years) - 1.0;
    final cdi = c.anchors.riskFreeCagr;
    // Fisher, e não subtração: o prêmio é razão de fatores brutos.
    final historicalPremium = (1 + indexCagr) / (1 + cdi) - 1;

    // Volatilidade anualizada dos retornos diários do índice. O erro-padrão da
    // média de um prêmio é `σ ÷ √T`, com `T` em anos — é a conta que mostra
    // por que dez anos não estimam prêmio de risco.
    final returns = <double>[
      for (var i = 1; i < points.length; i++)
        points[i].close / points[i - 1].close - 1,
    ];
    // Série de um pregão só não tem variância amostral, e `n − 1` daria zero
    // no denominador: o `NaN` se propagaria calado até o intervalo de 95%.
    if (returns.length < 2) {
      stderr.writeln('índice com menos de dois pregões: sem variância '
          'amostral, e sem erro-padrão a declarar.');
      exitCode = 2;
      return;
    }
    final mean = returns.reduce((a, b) => a + b) / returns.length;
    final variance = returns
            .map((r) => (r - mean) * (r - mean))
            .reduce((a, b) => a + b) /
        (returns.length - 1);
    final dailyVol = math.sqrt(variance);
    final annualVol = dailyVol * math.sqrt(252.0);
    final standardError = annualVol / math.sqrt(years);

    stdout.writeln('-- o prêmio histórico, na janela da entrada congelada --');
    stdout.writeln('  janela                     ${years.toStringAsFixed(2)} anos '
        '(${points.length} pregões)');
    stdout.writeln('  Ibovespa, CAGR             ${_pct(indexCagr)}');
    stdout.writeln('  CDI, CAGR                  ${_pct(cdi)}');
    stdout.writeln('  prêmio (Fisher)            ${_pct(historicalPremium)}');
    stdout.writeln('  volatilidade anual         ${_pct(annualVol)}');
    stdout.writeln('  erro-padrão do prêmio      ${_pct(standardError)}');
    stdout.writeln('  intervalo de 95%           '
        '${_pct(historicalPremium - 1.96 * standardError)} a '
        '${_pct(historicalPremium + 1.96 * standardError)}');
    stdout.writeln('  anos para erro de 1 p.p.   '
        '${(annualVol * annualVol / 0.0001).toStringAsFixed(0)}');

    // **O encolhimento é a segunda saída que o item B3 nomeia**, e ela se
    // resolve sozinha: o peso do estimador amostral é `τ² ÷ (τ² + σ²)`, e com
    // um erro-padrão de quase 8 p.p. contra uma faixa a priori de meio ponto,
    // esse peso é de alguns por cento. **O encolhimento devolve o parâmetro.**
    stdout.writeln('');
    stdout.writeln('-- o encolhimento do histórico para a faixa declarada --');
    final shrunkList = <Map<String, dynamic>>[];
    for (final tau in [0.0025, 0.005, 0.010, 0.020]) {
      final weight = tau * tau / (tau * tau + standardError * standardError);
      final shrunk = weight * historicalPremium + (1 - weight) * _reference;
      stdout.writeln('  τ = ${_pct(tau)}   peso da amostra '
          '${(weight * 100).toStringAsFixed(2).padLeft(5)}%   '
          'prêmio encolhido ${_pct(shrunk)}');
      shrunkList.add({'tau': tau, 'peso': weight, 'premio': shrunk});
    }

    // ---------------------------------------------------------------------
    // 2) A varredura do prêmio sobre o universo
    // ---------------------------------------------------------------------
    final readings = <int, _Reading>{};
    for (var premiumIndex = 0; premiumIndex < _premiums.length; premiumIndex++) {
      final premium = _premiums[premiumIndex];
      final l = _Reading();
      final evaluated = <Ticker, ValuationResult?>{};
      var i = 0;
      for (final t in c.universe) {
        i++;
        if (i % 50 == 0) {
          stderr.write('  prêmio ${_pct(premium)}: $i/${c.universe.length}   \r');
        }
        final prep = await c.prepare(t, premium: premium);
        if (prep.isErr) continue;
        final inputs = prep.unwrap();
        final r = ValuationCascade.evaluate(inputs);
        if (premiumIndex == _referenceIndex) evaluated[t] = r.valueOrNull;
        if (r.isErr) continue;
        final v = r.unwrap();
        l.fairValueCents[t.value] = v.fairValue.cents;
        l.upside[t.value] = v.upside;
      }
      readings[premiumIndex] = l;

      if (premiumIndex == _referenceIndex) {
        final mismatches = await c.checkAgainstAnswerKey(evaluated);
        if (mismatches == null) {
          stderr.writeln('AVISO: gabarito ausente; montagem não conferida.');
        } else if (mismatches.isNotEmpty) {
          stderr.writeln('ERRO: a montagem de referência diverge do gabarito '
              'em ${mismatches.length}: ${mismatches.take(8).join(", ")}');
          exitCode = 1;
          return;
        } else {
          stdout.writeln('');
          stdout.writeln('montagem de ${_pct(_reference)} conferida contra o '
              'gabarito: zero divergências.');
        }
      }
    }
    stderr.write('                                        \r');

    final base = readings[_referenceIndex]!;
    final rows = <Map<String, dynamic>>[];

    stdout.writeln('');
    stdout.writeln('-- a varredura do prêmio, sobre a entrada congelada --');
    stdout.writeln('  prêmio  avaliados   potencial mediano   acima de zero  '
        ' preço justo vs 5,5%   postos');

    for (var premiumIndex = 0; premiumIndex < _premiums.length; premiumIndex++) {
      final premium = _premiums[premiumIndex];
      final l = readings[premiumIndex]!;
      final upsideValues = l.upside.values.toList();
      final medianUpside = _median(upsideValues);
      final above = upsideValues.where((p) => p > 0).length;

      final common = l.fairValueCents.keys
          .where(base.fairValueCents.containsKey)
          .toList()
        ..sort();
      final changeList = <double>[
        for (final k in common)
          if (base.fairValueCents[k]! != 0)
            l.fairValueCents[k]! / base.fairValueCents[k]! - 1,
      ];
      final rho = common.length < 3
          ? null
          : Regression.spearman(
              [for (final k in common) base.upside[k]!],
              [for (final k in common) l.upside[k]!],
            );

      stdout.writeln('  ${_pct(premium)}  '
          '${l.fairValueCents.length.toString().padLeft(9)}   '
          '${_pct(medianUpside).padLeft(16)}   '
          '${above.toString().padLeft(9)} de ${upsideValues.length}   '
          '${_pct(_median(changeList)).padLeft(17)}   '
          '${rho == null ? "  —   " : rho.toStringAsFixed(4)}');

      rows.add({
        'premio': premium,
        'avaliados': l.fairValueCents.length,
        'potencialMediano': medianUpside.isFinite ? medianUpside : null,
        'acimaDeZero': above,
        'precoJustoMedianoVsReferencia': _median(changeList),
        'spearmanContraReferencia': rho,
      });
    }

    // ---------------------------------------------------------------------
    // 3) O implícito: onde o agregado cruza zero
    // ---------------------------------------------------------------------
    double? implied;
    for (var i = 1; i < rows.length; i++) {
      final a = rows[i - 1]['potencialMediano'] as double?;
      final b = rows[i]['potencialMediano'] as double?;
      if (a == null || b == null) continue;
      if ((a >= 0 && b <= 0) || (a <= 0 && b >= 0)) {
        final premiumA = rows[i - 1]['premio'] as double;
        final premiumB = rows[i]['premio'] as double;
        // **A guarda é do denominador, e não da igualdade.** Dois potenciais
        // que deveriam ser iguais diferem por epsilon, e `a == b` passaria
        // reto para uma divisão por infinitésimo — o prêmio implícito sairia
        // absurdo sem que nada acusasse. Com o degrau da varredura em 1 p.p.,
        // uma diferença abaixo de `_plateau` é platô, e ali o extremo
        // esquerdo é a leitura honesta.
        implied = (b - a).abs() < _plateau
            ? premiumA
            : premiumA + (premiumB - premiumA) * (0 - a) / (b - a);
        break;
      }
    }

    stdout.writeln('');
    if (implied == null) {
      stdout.writeln('  o potencial mediano NÃO cruza zero na faixa varrida '
          '(${_pct(_premiums.first)} a ${_pct(_premiums.last)}).');
    } else {
      stdout.writeln('  prêmio implícito (mediana do potencial em zero): '
          '${_pct(implied)}');
    }

    File(_output).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'historico': {
        'anos': years,
        'pregoes': points.length,
        'cagrIbovespa': indexCagr,
        'cagrCdi': cdi,
        'premio': historicalPremium,
        'volatilidadeAnual': annualVol,
        'erroPadrao': standardError,
        'ic95': [
          historicalPremium - 1.96 * standardError,
          historicalPremium + 1.96 * standardError,
        ],
      },
      'encolhimento': shrunkList,
      'referencia': _reference,
      'varredura': rows,
      'premioImplicito': implied,
    }));
    stdout.writeln('');
    stdout.writeln('escrito $_output');
  } finally {
    await c.ctx.dispose();
  }
}

String _pct(double v) =>
    v.isNaN ? '   —  ' : '${(v * 100).toStringAsFixed(2).padLeft(6)}%';
