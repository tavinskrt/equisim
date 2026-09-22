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

const _saida = 'docs/validacao/minoritario.json';

/// Fração do patrimônio consolidado a partir da qual o minoritário é
/// **material**. Abaixo de 1% qualquer tratamento dele muda o terceiro decimal
/// da taxa, e a pergunta não é sobre esses.
const _materialidade = 0.01;

double _q(List<double> v, double p) {
  if (v.isEmpty) return double.nan;
  final o = [...v]..sort();
  return o[(o.length * p).floor().clamp(0, o.length - 1)];
}

double _mediana(List<double> v) => _q(v, 0.5);

enum _Forma { hoje, contabil, pelaRazao }

class _Leitura {
  final Map<String, int> justoCentavos = {};
  final Map<String, double> potencial = {};
  final Map<String, double> desconto = {};
}

Future<void> main(List<String> args) async {
  final c = await Congelado.montar();
  try {
    final fatia = <String, double>{};
    final estatico = <String>{};
    final viaDaFirma = <String>{};
    final leituras = {for (final f in _Forma.values) f: _Leitura()};
    final avaliadas = <Ticker, ValuationResult?>{};

    var i = 0;
    for (final t in c.universo) {
      i++;
      if (i % 50 == 0) stderr.write('  $i/${c.universo.length}   \r');
      final prep = await c.preparar(t);
      if (prep.isErr) continue;
      final b = prep.unwrap();
      if (b.fundamentals.isEmpty) continue;
      final f = b.fundamentals.last;

      final plControlador = f.totalStockholderEquity;
      final minoritario = f.minorityInterest;
      final consolidado = (plControlador ?? 0) + (minoritario ?? 0);
      final razao = (minoritario == null ||
              minoritario <= 0 ||
              plControlador == null ||
              plControlador <= 0 ||
              consolidado <= 0)
          ? null
          : minoritario / consolidado;

      for (final forma in _Forma.values) {
        final r = ValuationCascade.evaluate(
            _com(b, forma, minoritario, plControlador));
        if (forma == _Forma.hoje) avaliadas[t] = r.valueOrNull;
        if (r.isErr) continue;
        final v = r.unwrap();
        leituras[forma]!.justoCentavos[t.value] = v.fairValue.cents;
        leituras[forma]!.potencial[t.value] = v.upside;
        leituras[forma]!.desconto[t.value] = v.discountRate;
        // **Quem usa o WACC estático é quem não resolveu as taxas**, e é só
        // nele que o peso do minoritário falta. O aviso da avaliação é o que
        // separa os dois caminhos sem reimplementar a cascata.
        if (forma == _Forma.hoje) {
          if (!v.warnings.any((w) => w.contains('resolvido ano a ano'))) {
            estatico.add(t.value);
          }
          // **E a via do acionista não tem WACC nenhum**: o fluxo dela é do
          // acionista da controladora, descontado ao `Ke`, e o minoritário não
          // entra em peso porque não há peso. Sem este corte, a contagem de
          // expostos junta banco com companhia operacional.
          if (v.model == ValuationModel.dcfFcff) viaDaFirma.add(t.value);
        }
      }
      if (razao != null &&
          leituras[_Forma.hoje]!.justoCentavos.containsKey(t.value)) {
        fatia[t.value] = razao;
      }
    }
    stderr.write('                              \r');

    final div = await c.conferirContraGabarito(avaliadas);
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

    final base = leituras[_Forma.hoje]!;
    final materiais =
        fatia.entries.where((e) => e.value >= _materialidade).map((e) => e.key);
    // **O conjunto exposto é a interseção das três condições**: via da firma
    // (tem WACC), recuo estático (o peso é de mercado da controladora) e
    // minoritário material.
    final expostos = materiais
        .where(estatico.contains)
        .where(viaDaFirma.contains)
        .toSet();

    stdout.writeln('');
    stdout.writeln('-- o escopo do defeito --');
    stdout.writeln('  avaliados                          '
        '${base.justoCentavos.length}');
    stdout.writeln('  pela via da firma (têm WACC)       '
        '${viaDaFirma.length}');
    stdout.writeln('  usam o WACC estático               ${estatico.length}');
    stdout.writeln('  via da firma E estático            '
        '${viaDaFirma.where(estatico.contains).length}');
    stdout.writeln('  têm minoritário publicado          ${fatia.length}');
    stdout.writeln('  com fatia ≥ ${(_materialidade * 100).toStringAsFixed(0)}%'
        '                     ${materiais.length}');
    stdout.writeln('  **firma, estático E material**     ${expostos.length}'
        '${expostos.isEmpty ? "" : "  (${expostos.take(10).join(", ")})"}');
    final fatias = fatia.values.toList();
    if (fatias.isNotEmpty) {
      stdout.writeln('  fatia do minoritário: p50 ${_pct(_mediana(fatias))}  '
          'p90 ${_pct(_q(fatias, 0.90))}  '
          'máx ${_pct(fatias.reduce((a, b) => a > b ? a : b))}');
    }

    final linhas = <Map<String, Object?>>[];
    stdout.writeln('');
    stdout.writeln('-- o efeito de pôr o minoritário no peso --');
    stdout.writeln('  forma         avaliados   justo (todos)   '
        'justo (expostos)   Δ desconto (expostos)   postos');

    for (final forma in _Forma.values) {
      if (forma == _Forma.hoje) continue;
      final l = leituras[forma]!;
      final comuns = l.justoCentavos.keys
          .where(base.justoCentavos.containsKey)
          .toList()
        ..sort();
      double? varDe(Iterable<String> chaves) {
        final v = <double>[
          for (final k in chaves)
            if (base.justoCentavos[k] != null &&
                base.justoCentavos[k] != 0 &&
                l.justoCentavos[k] != null)
              l.justoCentavos[k]! / base.justoCentavos[k]! - 1,
        ];
        return v.isEmpty ? null : _mediana(v);
      }

      final dDesconto = <double>[
        for (final k in comuns)
          if (expostos.contains(k)) l.desconto[k]! - base.desconto[k]!,
      ];
      final rho = comuns.length < 3
          ? null
          : Regression.spearman(
              [for (final k in comuns) base.potencial[k]!],
              [for (final k in comuns) l.potencial[k]!],
            );
      final saem = base.justoCentavos.keys
          .where((k) => !l.justoCentavos.containsKey(k))
          .toList()
        ..sort();

      stdout.writeln('  ${forma.name.padRight(12)}  '
          '${l.justoCentavos.length.toString().padLeft(9)}   '
          '${_pct(varDe(comuns) ?? double.nan).padLeft(13)}   '
          '${_pct(varDe(expostos) ?? double.nan).padLeft(16)}   '
          '${dDesconto.isEmpty ? "         —      " : "${(_mediana(dDesconto) * 100).toStringAsFixed(2).padLeft(13)} p.p."}   '
          '${rho == null ? "  —   " : rho.toStringAsFixed(4)}');

      linhas.add({
        'forma': forma.name,
        'avaliados': l.justoCentavos.length,
        'justoMedianoTodos': varDe(comuns),
        'justoMedianoExpostos': varDe(expostos),
        'deltaDescontoMedianoExpostos':
            dDesconto.isEmpty ? null : _mediana(dDesconto),
        'spearmanPotencial': rho,
        'saem': saem,
      });
    }

    File(_saida).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'materialidade': _materialidade,
      'avaliados': base.justoCentavos.length,
      'usamWaccEstatico': estatico.length,
      'viaDaFirma': viaDaFirma.length,
      'viaDaFirmaEEstatico':
          (viaDaFirma.where(estatico.contains).toList()..sort()),
      'comMinoritario': fatia.length,
      'comFatiaMaterial': materiais.length,
      'estaticoEMaterial': expostos.toList()..sort(),
      'fatia': {
        'p50': fatias.isEmpty ? null : _mediana(fatias),
        'p90': fatias.isEmpty ? null : _q(fatias, 0.90),
        'maximo':
            fatias.isEmpty ? null : fatias.reduce((a, b) => a > b ? a : b),
      },
      'maioresFatias': Map.fromEntries(
        (fatia.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(15),
      ),
      'formas': linhas,
    }));
    stdout.writeln('');
    stdout.writeln('escrito $_saida');
  } finally {
    await c.ctx.dispose();
  }
}

/// Os mesmos insumos, com o minoritário somado ao peso do capital próprio.
ValuationInputs _com(
  ValuationInputs b,
  _Forma forma,
  double? minoritario,
  double? plControlador,
) {
  if (forma == _Forma.hoje) return b;
  if (minoritario == null || minoritario <= 0) return b;
  if (plControlador == null || plControlador <= 0) return b;

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
  final mercado = divisor.count * b.marketPrice;

  final valor = switch (forma) {
    _Forma.hoje => 0.0,
    // Contábil puro: o valor de livro entra num denominador de mercado.
    _Forma.contabil => minoritario,
    // Pelo `P/VP` do controlador: `PL_min × (E_mercado ÷ PL_contr)`. Coincide
    // com a contábil quando o `P/VP` é 1, e difere dela exatamente por ele.
    _Forma.pelaRazao => minoritario * (mercado / plControlador),
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
    minorityEquityValue: valor,
  );
}

String _pct(double v) =>
    v.isNaN ? '   —  ' : '${(v * 100).toStringAsFixed(2)}%';
