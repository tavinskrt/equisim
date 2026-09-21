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
const _premios = [
  -0.06, -0.05, -0.04, -0.03, -0.02, -0.01, 0.0, 0.01, 0.02, 0.03, 0.04, 0.045,
  0.05, 0.055, 0.06, 0.07, 0.08, 0.10,
];
/// Posição de [_premios] que serve de referência — o 5,5% de hoje.
///
/// **Posição, e não valor**: `double` não serve de chave de mapa nem de
/// critério de igualdade (regra R6). E é constante declarada, e não
/// `indexOf(0.055)`: procurar um `double` numa lista compara por `==` por
/// dentro, que é a mesma regra por outro nome. [_conferirReferencia] impede
/// que a posição e a lista se desencontrem.
const int _iReferencia = 13;

/// O prêmio de referência, para exibição.
double get _referencia => _premios[_iReferencia];

/// Falha cedo se alguém mexer em [_premios] sem mexer em [_iReferencia].
void _conferirReferencia() {
  if ((_referencia - 0.055).abs() > 1e-9) {
    throw StateError('_iReferencia aponta para $_referencia, e não para o '
        'prêmio de 5,5% que a montagem do gabarito usa.');
  }
}
const _saida = 'docs/validacao/premio_de_mercado.json';

/// Diferença de potencial abaixo da qual dois degraus da varredura são o mesmo
/// número, e a interpolação entre eles não tem o que interpolar.
///
/// Um centésimo de ponto percentual de potencial: a varredura anda de 1 p.p.
/// em prêmio e move o potencial em pontos inteiros, de modo que qualquer coisa
/// abaixo disso é ruído de arredondamento, e não inclinação.
const _planicie = 1e-4;

double _q(List<double> v, double p) {
  if (v.isEmpty) return double.nan;
  final o = [...v]..sort();
  return o[(o.length * p).floor().clamp(0, o.length - 1)];
}

double _mediana(List<double> v) => _q(v, 0.5);

class _Leitura {
  _Leitura(this.premio);
  final double premio;
  final Map<String, int> justoCentavos = {};
  final Map<String, double> potencial = {};
}

Future<void> main(List<String> args) async {
  _conferirReferencia();
  final c = await Congelado.montar();
  try {
    // ---------------------------------------------------------------------
    // 1) O histórico, com a barra de erro
    // ---------------------------------------------------------------------
    final indiceRes = await c.ctx.benchmark.ibovespa(c.janelaDoBeta);
    if (indiceRes.isErr) {
      stderr.writeln('sem índice: ${indiceRes.failureOrNull?.message}');
      exitCode = 2;
      return;
    }
    final indice = indiceRes.unwrap();
    final pontos = indice.points;
    final anos = pontos.last.date.difference(pontos.first.date).inDays / 365.25;
    final cagrIndice =
        math.pow(pontos.last.close / pontos.first.close, 1 / anos) - 1.0;
    final cdi = c.anchors.riskFreeCagr;
    // Fisher, e não subtração: o prêmio é razão de fatores brutos.
    final premioHistorico = (1 + cagrIndice) / (1 + cdi) - 1;

    // Volatilidade anualizada dos retornos diários do índice. O erro-padrão da
    // média de um prêmio é `σ ÷ √T`, com `T` em anos — é a conta que mostra
    // por que dez anos não estimam prêmio de risco.
    final retornos = <double>[
      for (var i = 1; i < pontos.length; i++)
        pontos[i].close / pontos[i - 1].close - 1,
    ];
    // Série de um pregão só não tem variância amostral, e `n − 1` daria zero
    // no denominador: o `NaN` se propagaria calado até o intervalo de 95%.
    if (retornos.length < 2) {
      stderr.writeln('índice com menos de dois pregões: sem variância '
          'amostral, e sem erro-padrão a declarar.');
      exitCode = 2;
      return;
    }
    final media = retornos.reduce((a, b) => a + b) / retornos.length;
    final variancia = retornos
            .map((r) => (r - media) * (r - media))
            .reduce((a, b) => a + b) /
        (retornos.length - 1);
    final volDiaria = math.sqrt(variancia);
    final volAnual = volDiaria * math.sqrt(252.0);
    final erroPadrao = volAnual / math.sqrt(anos);

    stdout.writeln('-- o prêmio histórico, na janela da entrada congelada --');
    stdout.writeln('  janela                     ${anos.toStringAsFixed(2)} anos '
        '(${pontos.length} pregões)');
    stdout.writeln('  Ibovespa, CAGR             ${_pct(cagrIndice)}');
    stdout.writeln('  CDI, CAGR                  ${_pct(cdi)}');
    stdout.writeln('  prêmio (Fisher)            ${_pct(premioHistorico)}');
    stdout.writeln('  volatilidade anual         ${_pct(volAnual)}');
    stdout.writeln('  erro-padrão do prêmio      ${_pct(erroPadrao)}');
    stdout.writeln('  intervalo de 95%           '
        '${_pct(premioHistorico - 1.96 * erroPadrao)} a '
        '${_pct(premioHistorico + 1.96 * erroPadrao)}');
    stdout.writeln('  anos para erro de 1 p.p.   '
        '${(volAnual * volAnual / 0.0001).toStringAsFixed(0)}');

    // **O encolhimento é a segunda saída que o item B3 nomeia**, e ela se
    // resolve sozinha: o peso do estimador amostral é `τ² ÷ (τ² + σ²)`, e com
    // um erro-padrão de quase 8 p.p. contra uma faixa a priori de meio ponto,
    // esse peso é de alguns por cento. **O encolhimento devolve o parâmetro.**
    stdout.writeln('');
    stdout.writeln('-- o encolhimento do histórico para a faixa declarada --');
    final encolhidos = <Map<String, dynamic>>[];
    for (final tau in [0.0025, 0.005, 0.010, 0.020]) {
      final peso = tau * tau / (tau * tau + erroPadrao * erroPadrao);
      final encolhido = peso * premioHistorico + (1 - peso) * _referencia;
      stdout.writeln('  τ = ${_pct(tau)}   peso da amostra '
          '${(peso * 100).toStringAsFixed(2).padLeft(5)}%   '
          'prêmio encolhido ${_pct(encolhido)}');
      encolhidos.add({'tau': tau, 'peso': peso, 'premio': encolhido});
    }

    // ---------------------------------------------------------------------
    // 2) A varredura do prêmio sobre o universo
    // ---------------------------------------------------------------------
    final leituras = <int, _Leitura>{};
    for (var iPremio = 0; iPremio < _premios.length; iPremio++) {
      final premio = _premios[iPremio];
      final l = _Leitura(premio);
      final avaliadas = <Ticker, ValuationResult?>{};
      var i = 0;
      for (final t in c.universo) {
        i++;
        if (i % 50 == 0) {
          stderr.write('  prêmio ${_pct(premio)}: $i/${c.universo.length}   \r');
        }
        final prep = await c.preparar(t, premio: premio);
        if (prep.isErr) continue;
        final insumos = prep.unwrap();
        final r = ValuationCascade.evaluate(insumos);
        if (iPremio == _iReferencia) avaliadas[t] = r.valueOrNull;
        if (r.isErr) continue;
        final v = r.unwrap();
        l.justoCentavos[t.value] = v.fairValue.cents;
        l.potencial[t.value] = v.upside;
      }
      leituras[iPremio] = l;

      if (iPremio == _iReferencia) {
        final div = await c.conferirContraGabarito(avaliadas);
        if (div == null) {
          stderr.writeln('AVISO: gabarito ausente; montagem não conferida.');
        } else if (div.isNotEmpty) {
          stderr.writeln('ERRO: a montagem de referência diverge do gabarito '
              'em ${div.length}: ${div.take(8).join(", ")}');
          exitCode = 1;
          return;
        } else {
          stdout.writeln('');
          stdout.writeln('montagem de ${_pct(_referencia)} conferida contra o '
              'gabarito: zero divergências.');
        }
      }
    }
    stderr.write('                                        \r');

    final base = leituras[_iReferencia]!;
    final linhas = <Map<String, dynamic>>[];

    stdout.writeln('');
    stdout.writeln('-- a varredura do prêmio, sobre a entrada congelada --');
    stdout.writeln('  prêmio  avaliados   potencial mediano   acima de zero  '
        ' preço justo vs 5,5%   postos');

    for (var iPremio = 0; iPremio < _premios.length; iPremio++) {
      final premio = _premios[iPremio];
      final l = leituras[iPremio]!;
      final pots = l.potencial.values.toList();
      final medianaPot = _mediana(pots);
      final acima = pots.where((p) => p > 0).length;

      final comuns = l.justoCentavos.keys
          .where(base.justoCentavos.containsKey)
          .toList()
        ..sort();
      final variacao = <double>[
        for (final k in comuns)
          if (base.justoCentavos[k]! != 0)
            l.justoCentavos[k]! / base.justoCentavos[k]! - 1,
      ];
      final rho = comuns.length < 3
          ? null
          : Regression.spearman(
              [for (final k in comuns) base.potencial[k]!],
              [for (final k in comuns) l.potencial[k]!],
            );

      stdout.writeln('  ${_pct(premio)}  '
          '${l.justoCentavos.length.toString().padLeft(9)}   '
          '${_pct(medianaPot).padLeft(16)}   '
          '${acima.toString().padLeft(9)} de ${pots.length}   '
          '${_pct(_mediana(variacao)).padLeft(17)}   '
          '${rho == null ? "  —   " : rho.toStringAsFixed(4)}');

      linhas.add({
        'premio': premio,
        'avaliados': l.justoCentavos.length,
        'potencialMediano': medianaPot.isFinite ? medianaPot : null,
        'acimaDeZero': acima,
        'precoJustoMedianoVsReferencia': _mediana(variacao),
        'spearmanContraReferencia': rho,
      });
    }

    // ---------------------------------------------------------------------
    // 3) O implícito: onde o agregado cruza zero
    // ---------------------------------------------------------------------
    double? implicito;
    for (var i = 1; i < linhas.length; i++) {
      final a = linhas[i - 1]['potencialMediano'] as double?;
      final b = linhas[i]['potencialMediano'] as double?;
      if (a == null || b == null) continue;
      if ((a >= 0 && b <= 0) || (a <= 0 && b >= 0)) {
        final pa = linhas[i - 1]['premio'] as double;
        final pb = linhas[i]['premio'] as double;
        // **A guarda é do denominador, e não da igualdade.** Dois potenciais
        // que deveriam ser iguais diferem por epsilon, e `a == b` passaria
        // reto para uma divisão por infinitésimo — o prêmio implícito sairia
        // absurdo sem que nada acusasse. Com o degrau da varredura em 1 p.p.,
        // uma diferença abaixo de `_planicie` é platô, e ali o extremo
        // esquerdo é a leitura honesta.
        implicito = (b - a).abs() < _planicie
            ? pa
            : pa + (pb - pa) * (0 - a) / (b - a);
        break;
      }
    }

    stdout.writeln('');
    if (implicito == null) {
      stdout.writeln('  o potencial mediano NÃO cruza zero na faixa varrida '
          '(${_pct(_premios.first)} a ${_pct(_premios.last)}).');
    } else {
      stdout.writeln('  prêmio implícito (mediana do potencial em zero): '
          '${_pct(implicito)}');
    }

    File(_saida).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'historico': {
        'anos': anos,
        'pregoes': pontos.length,
        'cagrIbovespa': cagrIndice,
        'cagrCdi': cdi,
        'premio': premioHistorico,
        'volatilidadeAnual': volAnual,
        'erroPadrao': erroPadrao,
        'ic95': [
          premioHistorico - 1.96 * erroPadrao,
          premioHistorico + 1.96 * erroPadrao,
        ],
      },
      'encolhimento': encolhidos,
      'referencia': _referencia,
      'varredura': linhas,
      'premioImplicito': implicito,
    }));
    stdout.writeln('');
    stdout.writeln('escrito $_saida');
  } finally {
    await c.ctx.dispose();
  }
}

String _pct(double v) =>
    v.isNaN ? '   —  ' : '${(v * 100).toStringAsFixed(2).padLeft(6)}%';
