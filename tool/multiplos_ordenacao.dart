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

const _entrada = 'docs/validacao/backtest_trimestral.json';
const _saida = 'docs/validacao/multiplos_ordenacao.json';

/// Mínimo de pares para uma mediana setorial da coorte ser usável — o mesmo
/// corte que a cascata cobra, e por isso vem dela.
const _minimoDePares = PeerValuation.minimumPeers;

double? _num(dynamic v) {
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d : null;
  }
  return null;
}

double _mediana(List<double> v) {
  final o = [...v]..sort();
  final meio = o.length ~/ 2;
  return o.length.isOdd ? o[meio] : (o[meio - 1] + o[meio]) / 2;
}

/// Uma observação com tudo o que as quatro ordenações pedem.
class _Obs {
  _Obs({
    required this.coorte,
    required this.ticker,
    required this.setor,
    required this.potencial,
    required this.bookToMarket,
    required this.earningsYield,
    required this.multiplos,
    required this.retorno,
  });
  final String coorte;
  final String ticker;
  final String setor;
  final double potencial;
  final double bookToMarket;
  final double earningsYield;
  final double multiplos;
  final double retorno;
}

/// O potencial que os pares da coorte implicam, ou `null`.
///
/// **Sem divisor e sem contagem de papéis**: o potencial é
/// `valor implicado ÷ valor de mercado − 1`, e os dois lados são da companhia
/// inteira. A ponte não entra, e por isso não há como ela entrar.
double? _potencialPorMultiplos({
  required Map<String, dynamic> m,
  required Map<MultipleKind, double> medianas,
}) {
  final vm = _num(m['valorDeMercado']);
  if (vm == null || vm <= 0) return null;

  final leituras = <double>[];

  final lucro = _num(m['lucro']);
  final pl = medianas[MultipleKind.precoLucro];
  if (lucro != null && lucro > 0 && pl != null) {
    leituras.add(pl * lucro / vm - 1);
  }

  final patrimonio = _num(m['patrimonio']);
  final pvp = medianas[MultipleKind.precoPatrimonio];
  if (patrimonio != null && patrimonio > 0 && pvp != null) {
    leituras.add(pvp * patrimonio / vm - 1);
  }

  final ebitda = _num(m['ebitda']);
  final ev = medianas[MultipleKind.firmaEbitda];
  final divida = _num(m['dividaLiquida']);
  if (ebitda != null && ebitda > 0 && ev != null && divida != null) {
    final acionista = ev * ebitda - divida;
    if (acionista > 0) leituras.add(acionista / vm - 1);
  }

  if (leituras.isEmpty) return null;
  return _mediana(leituras);
}

void main(List<String> args) {
  final arquivo = File(_entrada);
  if (!arquivo.existsSync()) {
    stderr.writeln('sem $_entrada: rode o backtest trimestral antes.');
    exitCode = 2;
    return;
  }
  final bruto = jsonDecode(arquivo.readAsStringSync());
  final linhas = (bruto is Map<String, dynamic>
          ? (bruto['observacoes'] ?? bruto['linhas'] ?? bruto['dados'])
          : bruto) as List<dynamic>?;
  if (linhas == null) {
    stderr.writeln('$_entrada não tem a lista de observações esperada.');
    exitCode = 2;
    return;
  }

  final resultado = <String, dynamic>{'entrada': _entrada};
  for (final horizonte in const [12, 36]) {
    final campoRetorno = 'ret${horizonte}tot';

    // ------------------------------------------------------------------
    // 1) As medianas setoriais de cada coorte, da própria seção transversal
    // ------------------------------------------------------------------
    final porCoorte = <String, List<Map<String, dynamic>>>{};
    for (final l in linhas) {
      final m = l as Map<String, dynamic>;
      porCoorte.putIfAbsent('${m['coorte']}', () => []).add(m);
    }

    final obs = <_Obs>[];
    var semMediana = 0;
    for (final e in porCoorte.entries) {
      // Por setor, e com recuo para o mercado inteiro da coorte — a mesma
      // hierarquia do pacote, sem o degrau do subsetor, que a coorte não tem.
      final porSetor = <String, List<Map<String, dynamic>>>{};
      for (final m in e.value) {
        final setor = m['setor'] as String?;
        if (setor == null) continue;
        porSetor.putIfAbsent(setor, () => []).add(m);
      }

      Map<MultipleKind, double> medianasDe(List<Map<String, dynamic>> grupo) {
        final out = <MultipleKind, double>{};
        void juntar(MultipleKind k, double? Function(Map<String, dynamic>) f) {
          final v = <double>[
            for (final m in grupo)
              if (f(m) != null && f(m)! > 0) f(m)!,
          ];
          if (v.length >= _minimoDePares) out[k] = _mediana(v);
        }

        // `bookToMarket` é `1 ÷ (P/VP)` e `earningsYield` é `1 ÷ (P/L)`: os
        // dois já vinham do backtest, e invertê-los aqui evita gravar o mesmo
        // número duas vezes com nomes diferentes.
        juntar(MultipleKind.precoLucro, (m) {
          final ey = _num(m['earningsYield']);
          return (ey == null || ey <= 0) ? null : 1 / ey;
        });
        juntar(MultipleKind.precoPatrimonio, (m) {
          final bm = _num(m['bookToMarket']);
          return (bm == null || bm <= 0) ? null : 1 / bm;
        });
        juntar(MultipleKind.firmaEbitda, (m) => _num(m['firmaSobreEbitda']));
        return out;
      }

      final doMercado = medianasDe(e.value);
      final porSetorMedianas = {
        for (final s in porSetor.entries) s.key: medianasDe(s.value),
      };

      for (final m in e.value) {
        final pot = _num(m['upside']);
        final bm = _num(m['bookToMarket']);
        final ey = _num(m['earningsYield']);
        final ret = _num(m[campoRetorno]);
        final setor = m['setor'] as String?;
        if (pot == null || bm == null || ey == null || ret == null) continue;
        if (setor == null) continue;

        // Setor quando ele reúne pares; mercado da coorte quando não.
        final doSetor = porSetorMedianas[setor] ?? const {};
        final medianas = <MultipleKind, double>{
          for (final k in MultipleKind.values)
            if (doSetor[k] != null)
              k: doSetor[k]!
            else if (doMercado[k] != null)
              k: doMercado[k]!,
        };
        final mult = _potencialPorMultiplos(m: m, medianas: medianas);
        if (mult == null) {
          semMediana++;
          continue;
        }
        obs.add(_Obs(
          coorte: '${m['coorte']}',
          ticker: m['ticker'] as String,
          setor: setor,
          potencial: pot,
          bookToMarket: bm,
          earningsYield: ey,
          multiplos: mult,
          retorno: ret,
        ));
      }
    }

    // ------------------------------------------------------------------
    // 2) As quatro ordenações, coorte a coorte, nas mesmas observações
    // ------------------------------------------------------------------
    final coortes = <String, List<_Obs>>{};
    for (final o in obs) {
      coortes.putIfAbsent(o.coorte, () => []).add(o);
    }
    final chaves = coortes.keys.toList()..sort();

    final series = <String, List<double>>{
      'potencial': [],
      'bookToMarket': [],
      'earningsYield': [],
      'multiplos': [],
      'composto': [],
    };
    final porCoorteSaida = <Map<String, dynamic>>[];

    for (final chave in chaves) {
      final grupo = coortes[chave]!;
      if (grupo.length < 10) continue;
      final zRet =
          Regression.standardizedRanks([for (final o in grupo) o.retorno]);
      double? ic(List<double> v) =>
          Regression.pearson(Regression.standardizedRanks(v), zRet);

      final icPot = ic([for (final o in grupo) o.potencial]);
      final icBm = ic([for (final o in grupo) o.bookToMarket]);
      final icEy = ic([for (final o in grupo) o.earningsYield]);
      final icMult = ic([for (final o in grupo) o.multiplos]);
      // O composto é o do núcleo, com os três sinais da decisão 103 — o
      // múltiplo entra como quarto candidato **separado**, e não dentro dele:
      // mudar a composição seria mudar a regra depois de ver o resultado.
      final composto = TransversalScore.scores({
        for (var i = 0; i < grupo.length; i++)
          i: TransversalSignals(
            potential: grupo[i].potencial,
            bookToMarket: grupo[i].bookToMarket,
            earningsYield: grupo[i].earningsYield,
          ),
      }, TransversalOrdering.composite);
      final icComp = Regression.pearson(
        Regression.standardizedRanks(
            [for (var i = 0; i < grupo.length; i++) composto[i] ?? 0.0]),
        zRet,
      );

      void guardar(String nome, double? v) {
        if (v != null && v.isFinite) series[nome]!.add(v);
      }

      guardar('potencial', icPot);
      guardar('bookToMarket', icBm);
      guardar('earningsYield', icEy);
      guardar('multiplos', icMult);
      guardar('composto', icComp);

      porCoorteSaida.add({
        'coorte': chave,
        'n': grupo.length,
        'icPotencial': icPot,
        'icBookToMarket': icBm,
        'icEarningsYield': icEy,
        'icMultiplos': icMult,
        'icComposto': icComp,
      });
    }

    // A defasagem da sobreposição: coortes trimestrais e horizonte em meses.
    final defasagem = (horizonte / 3).round() - 1;
    final leituras = <String, dynamic>{};
    for (final e in series.entries) {
      final v = Regression.summarize(e.value);
      final nw = Regression.neweyWestMean(e.value, defasagem);
      final sob = Regression.overlapAdjustedT(e.value, defasagem);
      final critico =
          sob == null ? null : Regression.overlapCritical(sob.n, sob.overlap);
      leituras[e.key] = {
        'coortes': e.value.length,
        'media': v?.mean,
        't': v?.t,
        'tNeweyWest': nw?.t,
        'tSobreposicao': sob?.t,
        'criticoSobreposicao': critico,
        'positivas': e.value.where((x) => x > 0).length,
        if (sob != null && nw != null && critico != null)
          'passaR3': sob.t > critico && nw.t > 2,
      };
    }

    resultado['h$horizonte'] = {
      'observacoes': obs.length,
      'semMedianaUsavel': semMediana,
      'coortes': porCoorteSaida.length,
      'leituras': leituras,
      'porCoorte': porCoorteSaida,
    };

    stdout.writeln('');
    stdout.writeln('-- $horizonte meses: ${obs.length} observações, '
        '${porCoorteSaida.length} coortes --');
    stdout.writeln('  ordenação        média      t     Newey-West   '
        't corrigido / crítico   positivas   passa');
    for (final nome in const [
      'multiplos',
      'potencial',
      'bookToMarket',
      'earningsYield',
      'composto',
    ]) {
      final l = leituras[nome] as Map<String, dynamic>;
      String f(Object? v, [int casas = 3]) =>
          v is num ? v.toDouble().toStringAsFixed(casas) : '—';
      stdout.writeln('  ${nome.padRight(14)}  '
          '${f(l['media']).padLeft(7)}  ${f(l['t'], 2).padLeft(6)}  '
          '${f(l['tNeweyWest'], 2).padLeft(11)}   '
          '${f(l['tSobreposicao'], 2).padLeft(10)} / '
          '${f(l['criticoSobreposicao'], 2)}   '
          '${'${l['positivas']} de ${l['coortes']}'.padLeft(11)}   '
          '${l['passaR3'] == true ? 'SIM' : 'não'}');
    }
  }

  File(_saida)
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(resultado));
  stdout.writeln('');
  stdout.writeln('escrito $_saida');
}
