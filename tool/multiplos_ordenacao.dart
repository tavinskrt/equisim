// Item B22 — o múltiplo de pares como ordenação, medido ao lado das três da
// decisão 103.
//
// **Por que ele entrou.** O item B5 mediu que o potencial do DCF e o dos
// múltiplos têm correlação de postos de **0,470**, com o mesmo sinal em 63 de
// 93: o múltiplo relativo é **sinal distinto**, e não cópia. Se ele ordena
// melhor é pergunta de coorte, e é esta ferramenta.
//
// **A mediana é da coorte, e não do pacote.** O pacote versionado
// (`assets/mercado/multiplos_setoriais.json`) é de 14/09/2026: usá-lo numa
// observação de 2018 seria conhecimento futuro pela porta da frente. Aqui a
// mediana setorial sai da **própria seção transversal da coorte**, com os
// ingredientes que o backtest grava por observação.
//
// **A regra é a da decisão 103**, e foi fixada antes de medir: o prêmio do
// retorno esperado sai da **primeira ordenação que passar** no critério da
// decisão 96 — `t` corrigido pela sobreposição acima do crítico dela **e**
// Newey-West acima de 2. Esta ferramenta não muda a regra: acrescenta um
// candidato e diz se ele passa.
//
// **As quatro são medidas nas mesmas observações.** Comparar ordenadores
// medidos em subconjuntos diferentes compararia coberturas.
//
//   dart run tool/backtest_valuation.dart --montagem aplicativo \
//       --com-deslistadas --trimestral
//   dart run tool/multiplos_ordenacao.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/regression.dart';

const _inputFile = 'docs/validacao/backtest_trimestral.json';
const _output = 'docs/validacao/multiplos_ordenacao.json';

/// Mínimo de pares para uma mediana setorial da coorte ser usável — o mesmo
/// corte que a cascata cobra, e por isso vem dela.
const _minPeers = PeerValuation.minimumPeers;

double? _num(dynamic v) {
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d : null;
  }
  return null;
}

double _median(List<double> v) {
  final o = [...v]..sort();
  final mid = o.length ~/ 2;
  return o.length.isOdd ? o[mid] : (o[mid - 1] + o[mid]) / 2;
}

/// Uma observação com tudo o que as quatro ordenações pedem.
class _Obs {
  _Obs({
    required this.cohort,
    required this.upside,
    required this.bookToMarket,
    required this.earningsYield,
    required this.multiples,
    required this.returnRate,
  });
  final String cohort;
  final double upside;
  final double bookToMarket;
  final double earningsYield;
  final double multiples;
  final double returnRate;
}

/// O potencial que os pares da coorte implicam, ou `null`.
///
/// **Sem divisor e sem contagem de papéis**: o potencial é
/// `valor implicado ÷ valor de mercado − 1`, e os dois lados são da companhia
/// inteira. A ponte não entra, e por isso não há como ela entrar.
double? _multiplesUpsideOf({
  required Map<String, dynamic> m,
  required Map<MultipleKind, double> mediansByKind,
}) {
  final marketValue = _num(m['valorDeMercado']);
  if (marketValue == null || marketValue <= 0) return null;

  final readings = <double>[];

  final profit = _num(m['lucro']);
  final pl = mediansByKind[MultipleKind.priceToEarnings];
  if (profit != null && profit > 0 && pl != null) {
    readings.add(pl * profit / marketValue - 1);
  }

  final equity = _num(m['patrimonio']);
  final priceToBookMedian = mediansByKind[MultipleKind.priceToBook];
  if (equity != null && equity > 0 && priceToBookMedian != null) {
    readings.add(priceToBookMedian * equity / marketValue - 1);
  }

  final ebitda = _num(m['ebitda']);
  final ev = mediansByKind[MultipleKind.evToEbitda];
  final debt = _num(m['dividaLiquida']);
  if (ebitda != null && ebitda > 0 && ev != null && debt != null) {
    final shareholder = ev * ebitda - debt;
    if (shareholder > 0) readings.add(shareholder / marketValue - 1);
  }

  if (readings.isEmpty) return null;
  return _median(readings);
}

void main(List<String> args) {
  final file = File(_inputFile);
  if (!file.existsSync()) {
    stderr.writeln('sem $_inputFile: rode o backtest trimestral antes.');
    exitCode = 2;
    return;
  }
  final raw = jsonDecode(file.readAsStringSync());
  final rows = (raw is Map<String, dynamic>
          ? (raw['observacoes'] ?? raw['linhas'] ?? raw['dados'])
          : raw) as List<dynamic>?;
  if (rows == null) {
    stderr.writeln('$_inputFile não tem a lista de observações esperada.');
    exitCode = 2;
    return;
  }

  final result = <String, dynamic>{'entrada': _inputFile};
  for (final horizon in const [12, 36]) {
    final returnField = 'ret${horizon}tot';

    // ------------------------------------------------------------------
    // 1) As medianas setoriais de cada coorte, da própria seção transversal
    // ------------------------------------------------------------------
    final byCohort = <String, List<Map<String, dynamic>>>{};
    for (final l in rows) {
      final m = l as Map<String, dynamic>;
      byCohort.putIfAbsent('${m['coorte']}', () => []).add(m);
    }

    final obs = <_Obs>[];
    var withoutMedian = 0;
    for (final e in byCohort.entries) {
      // Por setor, e com recuo para o mercado inteiro da coorte — a mesma
      // hierarquia do pacote, sem o degrau do subsetor, que a coorte não tem.
      final bySector = <String, List<Map<String, dynamic>>>{};
      for (final m in e.value) {
        final sector = m['setor'] as String?;
        if (sector == null) continue;
        bySector.putIfAbsent(sector, () => []).add(m);
      }

      Map<MultipleKind, double> mediansOf(List<Map<String, dynamic>> group) {
        final out = <MultipleKind, double>{};
        void collect(MultipleKind k, double? Function(Map<String, dynamic>) f) {
          final v = <double>[
            for (final m in group)
              if (f(m) != null && f(m)! > 0) f(m)!,
          ];
          if (v.length >= _minPeers) out[k] = _median(v);
        }

        // `bookToMarket` é `1 ÷ (P/VP)` e `earningsYield` é `1 ÷ (P/L)`: os
        // dois já vinham do backtest, e invertê-los aqui evita gravar o mesmo
        // número duas vezes com nomes diferentes.
        collect(MultipleKind.priceToEarnings, (m) {
          final ey = _num(m['earningsYield']);
          return (ey == null || ey <= 0) ? null : 1 / ey;
        });
        collect(MultipleKind.priceToBook, (m) {
          final bm = _num(m['bookToMarket']);
          return (bm == null || bm <= 0) ? null : 1 / bm;
        });
        collect(MultipleKind.evToEbitda, (m) => _num(m['firmaSobreEbitda']));
        return out;
      }

      final marketMedians = mediansOf(e.value);
      final sectorMediansByName = {
        for (final s in bySector.entries) s.key: mediansOf(s.value),
      };

      for (final m in e.value) {
        final upsides = _num(m['upside']);
        final bm = _num(m['bookToMarket']);
        final ey = _num(m['earningsYield']);
        final ret = _num(m[returnField]);
        final sector = m['setor'] as String?;
        if (upsides == null || bm == null || ey == null || ret == null) continue;
        if (sector == null) continue;

        // Setor quando ele reúne pares; mercado da coorte quando não.
        final sectorMedians = sectorMediansByName[sector] ?? const {};
        final mediansByKind = <MultipleKind, double>{
          for (final k in MultipleKind.values)
            if (sectorMedians[k] != null)
              k: sectorMedians[k]!
            else if (marketMedians[k] != null)
              k: marketMedians[k]!,
        };
        final mult = _multiplesUpsideOf(m: m, mediansByKind: mediansByKind);
        if (mult == null) {
          withoutMedian++;
          continue;
        }
        obs.add(_Obs(
          cohort: '${m['coorte']}',
          upside: upsides,
          bookToMarket: bm,
          earningsYield: ey,
          multiples: mult,
          returnRate: ret,
        ));
      }
    }

    // ------------------------------------------------------------------
    // 2) As quatro ordenações, coorte a coorte, nas mesmas observações
    // ------------------------------------------------------------------
    final cohorts = <String, List<_Obs>>{};
    for (final o in obs) {
      cohorts.putIfAbsent(o.cohort, () => []).add(o);
    }
    final keys = cohorts.keys.toList()..sort();

    final series = <String, List<double>>{
      'potencial': [],
      'bookToMarket': [],
      'earningsYield': [],
      'multiplos': [],
      'composto': [],
    };
    final byCohortOutput = <Map<String, dynamic>>[];

    for (final key in keys) {
      final group = cohorts[key]!;
      if (group.length < 10) continue;
      final zRet =
          Regression.standardizedRanks([for (final o in group) o.returnRate]);
      double? ic(List<double> v) =>
          Regression.pearson(Regression.standardizedRanks(v), zRet);

      final upsideIc = ic([for (final o in group) o.upside]);
      final icBm = ic([for (final o in group) o.bookToMarket]);
      final icEy = ic([for (final o in group) o.earningsYield]);
      final icMult = ic([for (final o in group) o.multiples]);
      // O composto é o do núcleo, com os três sinais da decisão 103 — o
      // múltiplo entra como quarto candidato **separado**, e não dentro dele:
      // mudar a composição seria mudar a regra depois de ver o resultado.
      final composite = TransversalScore.scores({
        for (var i = 0; i < group.length; i++)
          i: TransversalSignals(
            potential: group[i].upside,
            bookToMarket: group[i].bookToMarket,
            earningsYield: group[i].earningsYield,
          ),
      }, TransversalOrdering.composite);
      final icComp = Regression.pearson(
        Regression.standardizedRanks(
            [for (var i = 0; i < group.length; i++) composite[i] ?? 0.0]),
        zRet,
      );

      void store(String name, double? v) {
        if (v != null && v.isFinite) series[name]!.add(v);
      }

      store('potencial', upsideIc);
      store('bookToMarket', icBm);
      store('earningsYield', icEy);
      store('multiplos', icMult);
      store('composto', icComp);

      byCohortOutput.add({
        'coorte': key,
        'n': group.length,
        'icPotencial': upsideIc,
        'icBookToMarket': icBm,
        'icEarningsYield': icEy,
        'icMultiplos': icMult,
        'icComposto': icComp,
      });
    }

    // A defasagem da sobreposição: coortes trimestrais e horizonte em meses.
    final lag = (horizon / 3).round() - 1;
    final readings = <String, dynamic>{};
    for (final e in series.entries) {
      final v = Regression.summarize(e.value);
      final nw = Regression.neweyWestMean(e.value, lag);
      final overlapT = Regression.overlapAdjustedT(e.value, lag);
      final critical =
          overlapT == null ? null : Regression.overlapCritical(overlapT.n, overlapT.overlap);
      readings[e.key] = {
        'coortes': e.value.length,
        'media': v?.mean,
        't': v?.t,
        'tNeweyWest': nw?.t,
        'tSobreposicao': overlapT?.t,
        'criticoSobreposicao': critical,
        'positivas': e.value.where((x) => x > 0).length,
        if (overlapT != null && nw != null && critical != null)
          'passaR3': overlapT.t > critical && nw.t > 2,
      };
    }

    result['h$horizon'] = {
      'observacoes': obs.length,
      'semMedianaUsavel': withoutMedian,
      'coortes': byCohortOutput.length,
      'leituras': readings,
      'porCoorte': byCohortOutput,
    };

    stdout.writeln('');
    stdout.writeln('-- $horizon meses: ${obs.length} observações, '
        '${byCohortOutput.length} coortes --');
    stdout.writeln('  ordenação        média      t     Newey-West   '
        't corrigido / crítico   positivas   passa');
    for (final name in const [
      'multiplos',
      'potencial',
      'bookToMarket',
      'earningsYield',
      'composto',
    ]) {
      final l = readings[name] as Map<String, dynamic>;
      String f(Object? v, [int decimals = 3]) =>
          v is num ? v.toDouble().toStringAsFixed(decimals) : '—';
      stdout.writeln('  ${name.padRight(14)}  '
          '${f(l['media']).padLeft(7)}  ${f(l['t'], 2).padLeft(6)}  '
          '${f(l['tNeweyWest'], 2).padLeft(11)}   '
          '${f(l['tSobreposicao'], 2).padLeft(10)} / '
          '${f(l['criticoSobreposicao'], 2)}   '
          '${'${l['positivas']} de ${l['coortes']}'.padLeft(11)}   '
          '${l['passaR3'] == true ? 'SIM' : 'não'}');
    }
  }

  File(_output)
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
  stdout.writeln('');
  stdout.writeln('escrito $_output');
}
