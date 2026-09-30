// O prêmio de risco medido do Ibovespa, no lugar dos 5,5% fixos — medição, sem
// ligar nada no motor.
//
// **A pergunta.** O orientador perguntou se o prêmio de mercado pode ser
// capturado em vez de fixado. A forma mais direta é a histórica: o que o
// Ibovespa rendeu acima do CDI na mesma janela,
//
//     prêmio = (1 + CAGR do Ibovespa) ÷ (1 + CAGR do CDI) − 1
//
// com as duas pontas como as âncoras de mercado do aplicativo já as medem
// (`ResolveMarketAnchors`: o índice entre médias de 63 pregões nas pontas, o
// CDI composto). A decisão 116 mediu isso numa janela e o recusou por ruído;
// esta ferramenta mede o que faltava para decidir: quanto o prêmio muda com a
// janela, quanto ele muda de uma data para outra, e o que cada um faz ao preço
// justo, à cobertura e à ordenação.
//
// **Duas partes.**
//
//   1. Sobre a entrada congelada de 14/09/2026: o prêmio com janelas de 5, 10,
//      15 e 20 anos, e o universo reavaliado com cada um contra os 5,5%.
//   2. Nas datas das coortes trimestrais: o prêmio de cada data, só com dado
//      até ela, com janelas de 5 e 10 anos. O backtest com esse prêmio é
//      `tool/backtest_valuation.dart --premio-historico 10 --saida <arq>`.
//
// O índice antes de 23/09/2016 vem do SGS 7 do Banco Central
// (`tool/ibovespa_sgs_baixar.py`), emendado à fonte de mercado — ver
// `tool/validation/ibovespa_longo.dart`.
//
//   python tool/ibovespa_sgs_baixar.py
//   dart run tool/premio_historico.dart       # grava premio_historico.json
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';
import 'validation/ibovespa_longo.dart';
import 'validation/regression.dart';

const _saida = 'docs/validacao/premio_historico.json';
const _janelas = [5, 10, 15, 20];
const _janelasDasCoortes = [5, 10];
const _referencia = CapmInputs.defaultMarketPremium;
const _casos = ['WEGE3', 'ITUB4', 'VALE3', 'SAPR11', 'RENT3'];

String _pct(double v, [int casas = 2]) =>
    '${(v * 100).toStringAsFixed(casas)}%';

double _mediana(List<double> v) {
  final o = [...v]..sort();
  if (o.isEmpty) return double.nan;
  final m = o.length ~/ 2;
  return o.length.isOdd ? o[m] : (o[m - 1] + o[m]) / 2;
}

/// O prêmio de uma janela terminada em [fim], com a barra de erro.
Future<Map<String, Object?>> _medir({
  required MacroRepository macro,
  required IbovespaLongo indice,
  required DateTime fim,
  required int anos,
}) async {
  final janela = DateRange(DateTime(fim.year - anos, fim.month, fim.day), fim);
  final ancoras = (await ResolveMarketAnchors.call(
    macro: macro,
    benchmark: indice,
    asOf: fim,
    windowYears: anos,
  ))
      .unwrap();
  // O CDI da janela precisa estar inteiro: sem ele, as âncoras recuam para o
  // valor de 2026 e o prêmio mediria outra coisa.
  final cdi = (await macro.riskFreeDaily(janela)).unwrap();
  final cdiCompleto = cdi.points.isNotEmpty &&
      cdi.points.first.date.difference(janela.start).inDays.abs() <= 10;
  final pontos = (await indice.ibovespa(janela)).unwrap().points;
  final indiceCompleto = pontos.isNotEmpty &&
      pontos.first.date.difference(janela.start).inDays.abs() <= 10;

  // Erro-padrão da média de um prêmio: `σ ÷ √T`, com a volatilidade anual dos
  // retornos diários do índice e `T` em anos. É a conta que diz quanto a
  // janela sabe.
  final retornos = <double>[
    for (var i = 1; i < pontos.length; i++)
      if (pontos[i - 1].close > 0) pontos[i].close / pontos[i - 1].close - 1,
  ];
  double? erro;
  if (retornos.length > 1) {
    final media = retornos.reduce((a, b) => a + b) / retornos.length;
    final variancia = retornos
            .map((r) => (r - media) * (r - media))
            .reduce((a, b) => a + b) /
        (retornos.length - 1);
    erro = math.sqrt(variancia) * math.sqrt(252.0) / math.sqrt(anos.toDouble());
  }
  return {
    'fim': fim.toIso8601String().substring(0, 10),
    'anos': anos,
    'ibovespa': ancoras.marketCagr,
    'cdi': ancoras.riskFreeCagr,
    'premio': premioDasAncoras(ancoras),
    'erroPadrao': erro,
    'completa': cdiCompleto && indiceCompleto,
  };
}

/// As datas das coortes trimestrais do backtest: o último dia de cada
/// trimestre, de 31/03/2018 a 30/09/2025.
List<DateTime> _datasDasCoortes() => [
      for (var ano = 2018; ano <= 2025; ano++)
        for (final mes in const [3, 6, 9, 12])
          if (!(ano == 2025 && mes == 12)) DateTime(ano, mes + 1, 0),
    ];

class _Leitura {
  _Leitura(this.rotulo, this.premio);
  final String rotulo;
  final double premio;
  final Map<String, int> justo = {};
  final Map<String, double> potencial = {};
}

Future<void> main(List<String> args) async {
  final c = await Congelado.montar();
  try {
    final hoje = hojeCongelado;
    final indice = await IbovespaLongo.montar(
      c.ctx.benchmark,
      janelaDaFonte: DateRange(DateTime(hoje.year - 10, hoje.month, hoje.day), hoje),
    );
    stdout.writeln('-- Ibovespa emendado: SGS 7 até '
        '${indice.inicioDaFonte.toIso8601String().substring(0, 10)}, fonte de '
        'mercado depois; razão mediana na sobreposição '
        '${indice.razaoNaSobreposicao.toStringAsFixed(6)} --');

    // -------------------------------------------------------------------
    // 1) Sobre a entrada congelada
    // -------------------------------------------------------------------
    final doAplicativo = premioDasAncoras(c.anchors);
    stdout.writeln('');
    stdout.writeln('-- o prêmio histórico em 14/09/2026, por janela --');
    stdout.writeln('  o do aplicativo (âncoras congeladas, dez anos): '
        '${_pct(doAplicativo)} = (1 + ${_pct(c.anchors.marketCagr)}) ÷ '
        '(1 + ${_pct(c.anchors.riskFreeCagr)}) − 1');
    final porJanela = <Map<String, Object?>>[];
    for (final anos in _janelas) {
      final m = await _medir(
          macro: c.ctx.macro, indice: indice, fim: hoje, anos: anos);
      porJanela.add(m);
      final e = m['erroPadrao'] as double?;
      final p = m['premio'] as double;
      stdout.writeln('  ${anos.toString().padLeft(2)} anos   Ibovespa '
          '${_pct(m['ibovespa'] as double)}   CDI ${_pct(m['cdi'] as double)}   '
          'prêmio ${_pct(p)}   erro-padrão ${e == null ? '—' : _pct(e)}   '
          '95%: ${e == null ? '—' : '${_pct(p - 1.96 * e)} a ${_pct(p + 1.96 * e)}'}'
          '${m['completa'] == true ? '' : '   (JANELA INCOMPLETA)'}');
    }

    // O universo reavaliado com cada prêmio.
    final candidatos = <(String, double)>[
      ('5,5% fixo', _referencia),
      for (final m in porJanela)
        ('${m['anos']} anos', m['premio'] as double),
    ];
    final leituras = <_Leitura>[];
    for (final (rotulo, premio) in candidatos) {
      final l = _Leitura(rotulo, premio);
      final avaliadas = <Ticker, ValuationResult?>{};
      var i = 0;
      for (final t in c.universo) {
        i++;
        if (i % 50 == 0) stderr.write('  $rotulo: $i/${c.universo.length}   \r');
        final prep = await c.preparar(t, premio: premio);
        if (prep.isErr) continue;
        final r = ValuationCascade.evaluate(prep.unwrap());
        if (identical(rotulo, candidatos.first.$1)) avaliadas[t] = r.valueOrNull;
        if (r.isErr) continue;
        l.justo[t.value] = r.unwrap().fairValue.cents;
        l.potencial[t.value] = r.unwrap().upside;
      }
      if (identical(rotulo, candidatos.first.$1)) {
        final div = await c.conferirContraGabarito(avaliadas);
        if (div == null) {
          stderr.writeln('AVISO: gabarito ausente; montagem não conferida.');
        } else if (div.isNotEmpty) {
          stderr.writeln('ERRO: a montagem de 5,5% diverge do gabarito em '
              '${div.length}: ${div.take(8).join(', ')}');
          exitCode = 1;
          return;
        }
      }
      leituras.add(l);
    }
    stderr.write('                                        \r');

    final base = leituras.first;
    final efeitos = <Map<String, Object?>>[];
    stdout.writeln('');
    stdout.writeln('-- o universo reavaliado --');
    stdout.writeln('  prêmio              avaliados   potencial mediano   acima '
        'de zero   preço justo vs 5,5%   postos');
    for (final l in leituras) {
      final pots = l.potencial.values.toList();
      final comuns = l.justo.keys.where(base.justo.containsKey).toList()..sort();
      final variacao = <double>[
        for (final k in comuns)
          if (base.justo[k]! != 0) l.justo[k]! / base.justo[k]! - 1,
      ];
      final rho = comuns.length < 3
          ? null
          : Regression.spearman(
              [for (final k in comuns) base.potencial[k]!],
              [for (final k in comuns) l.potencial[k]!],
            );
      final acima = pots.where((p) => p > 0).length;
      final medPot = _mediana(pots);
      final medVar = variacao.isEmpty ? null : _mediana(variacao);
      stdout.writeln('  ${'${l.rotulo} (${_pct(l.premio)})'.padRight(20)}'
          '${l.justo.length.toString().padLeft(9)}   '
          '${_pct(medPot).padLeft(17)}   '
          '${'$acima de ${pots.length}'.padLeft(13)}   '
          '${(medVar == null ? '—' : _pct(medVar)).padLeft(19)}   '
          '${rho == null ? '—' : rho.toStringAsFixed(3)}');
      efeitos.add({
        'rotulo': l.rotulo,
        'premio': l.premio,
        'avaliados': l.justo.length,
        'potencialMediano': medPot,
        'acimaDeZero': acima,
        'precoJustoMedianoContraReferencia': medVar,
        'spearmanContraReferencia': rho,
        'casos': {
          for (final t in _casos)
            t: {
              'justoCentavos': l.justo[t],
              'potencial': l.potencial[t],
            },
        },
      });
    }

    // -------------------------------------------------------------------
    // 2) O prêmio em cada data de coorte
    // -------------------------------------------------------------------
    stdout.writeln('');
    stdout.writeln('-- o prêmio histórico em cada data de coorte --');
    stdout.writeln('  data          5 anos (erro)         10 anos (erro)');
    final porCoorte = <Map<String, Object?>>[];
    for (final t in _datasDasCoortes()) {
      final linha = <String, Object?>{'data': t.toIso8601String().substring(0, 10)};
      final partes = <String>[];
      for (final anos in _janelasDasCoortes) {
        final m =
            await _medir(macro: c.ctx.macro, indice: indice, fim: t, anos: anos);
        linha['janela$anos'] = m;
        final e = m['erroPadrao'] as double?;
        partes.add('${_pct(m['premio'] as double).padLeft(7)} '
            '(${e == null ? '—' : _pct(e, 1)})'
            '${m['completa'] == true ? '' : '*'}');
      }
      porCoorte.add(linha);
      stdout.writeln('  ${linha['data']}    ${partes.join('      ')}');
    }
    final p10 = [
      for (final l in porCoorte)
        ((l['janela10'] as Map)['premio'] as double),
    ];
    final p5 = [
      for (final l in porCoorte) ((l['janela5'] as Map)['premio'] as double),
    ];
    stdout.writeln('  10 anos: de ${_pct(p10.reduce(math.min))} a '
        '${_pct(p10.reduce(math.max))}, mediana ${_pct(_mediana(p10))}; '
        'negativos: ${p10.where((p) => p <= 0).length} de ${p10.length}');
    stdout.writeln('   5 anos: de ${_pct(p5.reduce(math.min))} a '
        '${_pct(p5.reduce(math.max))}, mediana ${_pct(_mediana(p5))}; '
        'negativos: ${p5.where((p) => p <= 0).length} de ${p5.length}');

    File(_saida).writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
      'geradoPor': 'tool/premio_historico.dart',
      'dataDaEntrada': hoje.toIso8601String().substring(0, 10),
      'emenda': {
        'inicioDaFonteDeMercado':
            indice.inicioDaFonte.toIso8601String().substring(0, 10),
        'razaoMedianaNaSobreposicao': indice.razaoNaSobreposicao,
      },
      'premioDoAplicativoDezAnos': doAplicativo,
      'porJanela': porJanela,
      'efeitos': efeitos,
      'porCoorte': porCoorte,
    }));
    stdout.writeln('');
    stdout.writeln('escrito $_saida');
  } finally {
    await c.ctx.dispose();
  }
}
