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

const _referencia = 0.055;

/// O prêmio a somar no tercil menor, na medição do efeito. Dois pontos é a
/// ordem de grandeza do prêmio por tamanho na literatura de fatores — e é
/// grande o bastante para que, se nada se mover aqui, nada se mova nunca.
const _premioDeTamanho = 0.02;
const _saida = 'docs/validacao/tamanho.json';

double _q(List<double> v, double p) {
  if (v.isEmpty) return double.nan;
  final o = [...v]..sort();
  return o[(o.length * p).floor().clamp(0, o.length - 1)];
}

double _mediana(List<double> v) => _q(v, 0.5);

class _Ativo {
  _Ativo({
    required this.ticker,
    required this.valorDeMercado,
    required this.beta,
    required this.desconto,
    required this.potencial,
    required this.justoCentavos,
  });
  final String ticker;
  final double valorDeMercado;
  final double beta;
  final double desconto;
  final double potencial;
  final int justoCentavos;
}

Future<void> main(List<String> args) async {
  final c = await Congelado.montar();
  try {
    final ativos = <_Ativo>[];
    final avaliadas = <Ticker, ValuationResult?>{};
    var i = 0;
    for (final t in c.universo) {
      i++;
      if (i % 50 == 0) stderr.write('  $i/${c.universo.length}   \r');
      final prep = await c.preparar(t);
      if (prep.isErr) continue;
      final insumos = prep.unwrap();
      final r = ValuationCascade.evaluate(insumos);
      avaliadas[t] = r.valueOrNull;
      if (r.isErr) continue;
      final v = r.unwrap();
      // O valor de mercado da fonte, que é o que existe na data congelada. Ele
      // erra em alguns tickers (decisão 83) e por isso **não entra em conta de
      // dinheiro** aqui: entra só na **ordenação** por tamanho, onde um erro de
      // escala não troca tercil.
      final vm = insumos.fundamentals.isEmpty
          ? null
          : insumos.fundamentals.last.marketCap;
      if (vm == null || vm <= 0) continue;
      ativos.add(_Ativo(
        ticker: t.value,
        valorDeMercado: vm,
        beta: insumos.capm.beta,
        desconto: v.discountRate,
        potencial: v.upside,
        justoCentavos: v.fairValue.cents,
      ));
    }
    stderr.write('                              \r');

    final div = await c.conferirContraGabarito(avaliadas);
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

    ativos.sort((a, b) => a.valorDeMercado.compareTo(b.valorDeMercado));
    final n = ativos.length;
    final logVm = [for (final a in ativos) math.log(a.valorDeMercado)];

    stdout.writeln('');
    stdout.writeln('-- o tamanho contra o que o motor já cobra ($n avaliados) --');
    final rhoBeta =
        Regression.spearman(logVm, [for (final a in ativos) a.beta]);
    final rhoDesconto =
        Regression.spearman(logVm, [for (final a in ativos) a.desconto]);
    final rhoPotencial =
        Regression.spearman(logVm, [for (final a in ativos) a.potencial]);
    stdout.writeln('  postos de log(valor de mercado) contra');
    stdout.writeln('    beta                ${_f(rhoBeta)}');
    stdout.writeln('    taxa de desconto    ${_f(rhoDesconto)}');
    stdout.writeln('    potencial           ${_f(rhoPotencial)}');

    // Tercis, do menor para o maior.
    final corte = [0, n ~/ 3, 2 * n ~/ 3, n];
    final nomes = ['menor', 'meio', 'maior'];
    final tercis = <Map<String, dynamic>>[];
    stdout.writeln('');
    stdout.writeln('-- o perfil por tercil de tamanho --');
    stdout.writeln('  tercil   n   valor de mercado mediano   beta   desconto '
        '  potencial');
    for (var k = 0; k < 3; k++) {
      final faixa = ativos.sublist(corte[k], corte[k + 1]);
      final vmMed = _mediana([for (final a in faixa) a.valorDeMercado]);
      final betaMed = _mediana([for (final a in faixa) a.beta]);
      final descMed = _mediana([for (final a in faixa) a.desconto]);
      final potMed = _mediana([for (final a in faixa) a.potencial]);
      stdout.writeln('  ${nomes[k].padRight(6)} ${faixa.length.toString().padLeft(3)}   '
          '${_bilhoes(vmMed).padLeft(22)}   ${betaMed.toStringAsFixed(3)}   '
          '${_pct(descMed).padLeft(7)}   ${_pct(potMed).padLeft(8)}');
      tercis.add({
        'tercil': nomes[k],
        'n': faixa.length,
        'valorDeMercadoMediano': vmMed,
        'betaMediano': betaMed,
        'descontoMediano': descMed,
        'potencialMediano': potMed,
        'tickers': [for (final a in faixa) a.ticker],
      });
    }

    // ---------------------------------------------------------------------
    // O efeito de um prêmio explícito de tamanho no tercil menor
    // ---------------------------------------------------------------------
    final menores = {for (final a in ativos.sublist(0, corte[1])) a.ticker};
    final comPremio = <String, int>{};
    final potencialComPremio = <String, double>{};
    i = 0;
    for (final t in c.universo) {
      i++;
      if (i % 50 == 0) stderr.write('  com prêmio: $i/${c.universo.length}   \r');
      final premio =
          menores.contains(t.value) ? _referencia + _premioDeTamanho : _referencia;
      final prep = await c.preparar(t, premio: premio);
      if (prep.isErr) continue;
      final r = ValuationCascade.evaluate(prep.unwrap());
      if (r.isErr) continue;
      comPremio[t.value] = r.unwrap().fairValue.cents;
      potencialComPremio[t.value] = r.unwrap().upside;
    }
    stderr.write('                                   \r');

    final antes = {for (final a in ativos) a.ticker: a};
    final comuns = comPremio.keys.where(antes.containsKey).toList()..sort();
    final variacao = <double>[
      for (final k in comuns)
        if (antes[k]!.justoCentavos != 0)
          comPremio[k]! / antes[k]!.justoCentavos - 1,
    ];
    final variacaoMenores = <double>[
      for (final k in comuns)
        if (menores.contains(k) && antes[k]!.justoCentavos != 0)
          comPremio[k]! / antes[k]!.justoCentavos - 1,
    ];
    final rhoComPremio = Regression.spearman(
      [for (final k in comuns) antes[k]!.potencial],
      [for (final k in comuns) potencialComPremio[k]!],
    );
    final saem = antes.keys.where((k) => !comPremio.containsKey(k)).toList()
      ..sort();

    stdout.writeln('');
    stdout.writeln('-- o efeito de ${_pct(_premioDeTamanho)} no tercil menor --');
    stdout.writeln('  preço justo, no tercil menor   mediana '
        '${_pct(_mediana(variacaoMenores))}  (p25 '
        '${_pct(_q(variacaoMenores, 0.25))}, p75 '
        '${_pct(_q(variacaoMenores, 0.75))})');
    stdout.writeln('  preço justo, no universo       mediana '
        '${_pct(_mediana(variacao))}');
    stdout.writeln('  postos do potencial            ${_f(rhoComPremio)}');
    stdout.writeln('  deixam de ser avaliáveis       ${saem.length}'
        '${saem.isEmpty ? "" : " (${saem.take(6).join(", ")})"}');

    File(_saida).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'avaliados': n,
      'spearmanLogValorDeMercado': {
        'beta': rhoBeta,
        'desconto': rhoDesconto,
        'potencial': rhoPotencial,
      },
      'tercis': tercis,
      'premioDeTamanho': {
        'premio': _premioDeTamanho,
        'aplicadoEm': menores.length,
        'precoJustoMedianoNoTercilMenor': _mediana(variacaoMenores),
        'precoJustoMedianoNoUniverso': _mediana(variacao),
        'spearmanPotencial': rhoComPremio,
        'saem': saem,
      },
    }));
    stdout.writeln('');
    stdout.writeln('escrito $_saida');
  } finally {
    await c.ctx.dispose();
  }
}

String _f(double? v) => v == null ? '—' : v.toStringAsFixed(4);
String _pct(double v) =>
    v.isNaN ? '  —  ' : '${(v * 100).toStringAsFixed(2)}%';
String _bilhoes(double v) =>
    v.isFinite ? 'R\$ ${(v / 1e9).toStringAsFixed(2)} bi' : '   —  ';
