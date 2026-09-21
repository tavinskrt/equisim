// Item B5 — mede as medianas de múltiplos por grupo de pares e as empacota.
//
// **Por que empacotar.** A mediana é do **universo**, e a cascata avalia um
// ativo por vez: o núcleo não tem como calculá-la sem deixar de ser puro. É o
// mesmo arranjo do prior do beta (decisão 40) e do registro da B3 (decisão 82)
// — um programa varre, grava pacote versionado, e o aplicativo carrega.
//
// **Sobre a entrada congelada do gabarito, por padrão**, como os outros
// pacotes: todos são de 14/09/2026, e gerá-lo contra o dado do dia faria o
// pacote depender do que a fonte devolvesse naquele instante.
//
// **A hierarquia de grupo é declarada.** Subsetor quando há pares bastantes;
// setor quando não; mercado quando nem o setor tem. Cada mediana viaja com o
// grupo que a produziu e com quantos pares entraram, para que a tela possa
// dizer de onde o número saiu.
//
// Uso:
//   dart run tool/gabarito_cascata.dart       # congela a entrada
//   dart run tool/multiplos_empacotar.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';

const _saida = 'assets/mercado/multiplos_setoriais.json';

/// Mínimo de pares para que um grupo produza mediana. O mesmo corte que a
/// cascata cobra em `PeerValuation.minimumPeers` — duas cópias divergiriam.
const _minimoDePares = PeerValuation.minimumPeers;

/// A chave do grupo de mercado, quando nem o setor reúne pares.
const _mercado = 'mercado';

/// Um par observado: o múltiplo que ele negocia, com o grupo a que pertence.
class _Par {
  _Par({
    required this.ticker,
    required this.setor,
    required this.subsetor,
    required this.precoLucro,
    required this.precoPatrimonio,
    required this.firmaEbitda,
  });
  final String ticker;
  final String setor;
  final String? subsetor;
  final double? precoLucro;
  final double? precoPatrimonio;
  final double? firmaEbitda;

  double? mult(MultipleKind k) => switch (k) {
        MultipleKind.precoLucro => precoLucro,
        MultipleKind.precoPatrimonio => precoPatrimonio,
        MultipleKind.firmaEbitda => firmaEbitda,
      };
}

double _mediana(List<double> v) {
  final o = [...v]..sort();
  final meio = o.length ~/ 2;
  return o.length.isOdd ? o[meio] : (o[meio - 1] + o[meio]) / 2;
}

Future<void> main(List<String> args) async {
  final c = await Congelado.montar();
  try {
    final pares = <_Par>[];
    var i = 0;
    for (final t in c.universo) {
      i++;
      if (i % 50 == 0) stderr.write('  $i/${c.universo.length}   \r');
      final prep = await c.preparar(t);
      if (prep.isErr) continue;
      final insumos = prep.unwrap();
      if (insumos.fundamentals.isEmpty) continue;
      final f = insumos.fundamentals.last;
      final setor = insumos.sectorKey;
      if (setor == null) continue;

      // **O divisor da ponte, e não a contagem da fonte.** O múltiplo
      // observado tem de sair da mesma contagem que a cascata usa do outro
      // lado, ou a mediana e a leitura medem pontes diferentes (decisão 83).
      final divisor = ValuationCascade.quotedShares(
        latest: f,
        marketPrice: insumos.marketPrice,
        sharesPerQuote: insumos.declaredSharesPerUnit?.toDouble() ?? 1.0,
        published: insumos.fundamentals,
        official: insumos.officialShares,
        asOf: insumos.asOf,
      );
      if (divisor == null || divisor.count <= 0) continue;
      final valorDeMercado = divisor.count * insumos.marketPrice;

      final lucro = f.netIncome;
      final pl = f.totalStockholderEquity;
      final ebitda = f.ebitda;
      final financeira = FinancialSectors.isFinancial(
        sectorKey: setor,
        industry: insumos.industry,
      );

      pares.add(_Par(
        ticker: t.value,
        setor: setor,
        subsetor: insumos.industry,
        // Só múltiplo com a grandeza de baixo **positiva** entra na mediana:
        // P/L de prejuízo é negativo e não descreve quanto o mercado paga por
        // lucro — incluí-lo puxaria a mediana do setor para baixo por um
        // motivo que não é preço.
        precoLucro:
            lucro != null && lucro > 0 ? valorDeMercado / lucro : null,
        precoPatrimonio: pl != null && pl > 0 ? valorDeMercado / pl : null,
        // EBITDA de instituição financeira não descreve geração operacional
        // (decisão 102): ela não entra nem como par.
        firmaEbitda: !financeira && ebitda != null && ebitda > 0
            ? (valorDeMercado + f.netDebt) / ebitda
            : null,
      ));
    }
    stderr.write('                              \r');

    // ---------------------------------------------------------------------
    // As medianas, por grupo
    // ---------------------------------------------------------------------
    final porSubsetor = <String, List<_Par>>{};
    final porSetor = <String, List<_Par>>{};
    for (final p in pares) {
      porSetor.putIfAbsent(p.setor, () => []).add(p);
      final sub = p.subsetor;
      if (sub != null && sub.isNotEmpty) {
        porSubsetor.putIfAbsent(sub, () => []).add(p);
      }
    }

    Map<String, Object?>? medianaDe(List<_Par> grupo, MultipleKind k,
        String nome) {
      final v = <double>[
        for (final p in grupo)
          if (p.mult(k) != null && p.mult(k)!.isFinite && p.mult(k)! > 0)
            p.mult(k)!,
      ];
      if (v.length < _minimoDePares) return null;
      return {'mediana': _mediana(v), 'pares': v.length, 'grupo': nome};
    }

    final grupos = <String, Map<String, Object?>>{};
    void registrar(String chave, List<_Par> grupo) {
      final m = <String, Object?>{};
      for (final k in MultipleKind.values) {
        final r = medianaDe(grupo, k, chave);
        if (r != null) m[k.name] = r;
      }
      if (m.isNotEmpty) grupos[chave] = m;
    }

    for (final e in porSubsetor.entries) {
      registrar(e.key, e.value);
    }
    for (final e in porSetor.entries) {
      registrar(e.key, e.value);
    }
    registrar(_mercado, pares);

    // A ligação de cada ticker ao grupo que vale para ele: subsetor, setor,
    // mercado — na ordem, e **por múltiplo**, porque um subsetor pode ter pares
    // bastantes para P/VP e não para EV/EBITDA.
    final porTicker = <String, Map<String, Object?>>{};
    for (final p in pares) {
      final escolhido = <String, Object?>{};
      for (final k in MultipleKind.values) {
        for (final chave in [p.subsetor, p.setor, _mercado]) {
          if (chave == null) continue;
          final g = grupos[chave];
          final m = g?[k.name];
          if (m != null) {
            escolhido[k.name] = m;
            break;
          }
        }
      }
      if (escolhido.isNotEmpty) porTicker[p.ticker] = escolhido;
    }

    final json = <String, Object?>{
      'geradoEm': hojeCongelado.toIso8601String(),
      'minimoDePares': _minimoDePares,
      'observados': pares.length,
      'grupos': grupos,
      'porTicker': porTicker,
    };
    File(_saida).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(json));

    stdout.writeln('-- múltiplos de pares, sobre a entrada congelada --');
    stdout.writeln('  observados                 ${pares.length}');
    stdout.writeln('  grupos com alguma mediana  ${grupos.length}');
    stdout.writeln('  tickers ligados            ${porTicker.length}');
    stdout.writeln('');
    stdout.writeln('  o mercado inteiro:');
    for (final k in MultipleKind.values) {
      final m = grupos[_mercado]?[k.name] as Map<String, Object?>?;
      if (m == null) {
        stdout.writeln('    ${k.label.padRight(10)} —');
      } else {
        stdout.writeln('    ${k.label.padRight(10)} '
            '${(m['mediana'] as double).toStringAsFixed(2).padLeft(7)}×   '
            '${m['pares']} pares');
      }
    }
    stdout.writeln('');
    stdout.writeln('  por setor econômico:');
    final chaves = porSetor.keys.toList()..sort();
    for (final chave in chaves) {
      final g = grupos[chave];
      if (g == null) continue;
      final linha = <String>[];
      for (final k in MultipleKind.values) {
        final m = g[k.name] as Map<String, Object?>?;
        if (m == null) continue;
        final mediana = (m['mediana'] as double).toStringAsFixed(1);
        linha.add('${k.label} $mediana× (${m['pares']})');
      }
      stdout.writeln('    ${chave.padRight(32)} ${linha.join("  ")}');
    }
    stdout.writeln('');
    stdout.writeln('escrito $_saida');
  } finally {
    await c.ctx.dispose();
  }
}
