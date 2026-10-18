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
import 'package:equisim/presentation/shared/domain_copy.dart';

const _output = 'assets/mercado/multiplos_setoriais.json';

/// Mínimo de pares para que um grupo produza mediana. O mesmo corte que a
/// cascata cobra em `PeerValuation.minimumPeers` — duas cópias divergiriam.
const _minPeers = PeerValuation.minimumPeers;

/// A chave do grupo de mercado, quando nem o setor reúne pares.
const _market = 'mercado';

/// Um par observado: o múltiplo que ele negocia, com o grupo a que pertence.
class _Peer {
  _Peer({
    required this.ticker,
    required this.sector,
    required this.subsector,
    required this.priceToEarnings,
    required this.priceToBook,
    required this.evToEbitda,
  });
  final String ticker;
  final String sector;
  final String? subsector;
  final double? priceToEarnings;
  final double? priceToBook;
  final double? evToEbitda;

  double? mult(MultipleKind k) => switch (k) {
        MultipleKind.priceToEarnings => priceToEarnings,
        MultipleKind.priceToBook => priceToBook,
        MultipleKind.evToEbitda => evToEbitda,
      };
}

double _median(List<double> v) {
  final o = [...v]..sort();
  final mid = o.length ~/ 2;
  return o.length.isOdd ? o[mid] : (o[mid - 1] + o[mid]) / 2;
}

/// A companhia do papel: as quatro letras que as classes compartilham.
String _company(String ticker) =>
    ticker.length >= 4 ? ticker.substring(0, 4) : ticker;

/// Os múltiplos do grupo, **um por companhia**, sem a companhia [without].
///
/// **Par é outra companhia** (item B41). A mediana contava cada classe como um
/// par e incluía o próprio ativo: os sete «pares» de saneamento da SAPR11 eram
/// SAPR3, SAPR4 e SAPR11 e mais quatro, a mediana caía na própria Sanepar, e a
/// leitura de P/VP e a de EV/EBITDA devolviam, as duas, o preço da Sanepar na
/// data do pacote — R$ 38,15 ao centavo. Cada companhia entra com a mediana
/// das classes dela, e a do ativo avaliado não entra.
List<double> _values(List<_Peer> group, MultipleKind k, {String? without}) {
  final byCompany = <String, List<double>>{};
  for (final p in group) {
    final c = _company(p.ticker);
    if (c == without) continue;
    final m = p.mult(k);
    if (m != null && m.isFinite && m > 0) {
      byCompany.putIfAbsent(c, () => []).add(m);
    }
  }
  return [for (final v in byCompany.values) _median(v)];
}

Future<void> main(List<String> args) async {
  final c = await Frozen.build();
  try {
    final pairs = <_Peer>[];
    var i = 0;
    for (final t in c.universe) {
      i++;
      if (i % 50 == 0) stderr.write('  $i/${c.universe.length}   \r');
      final prep = await c.prepare(t);
      if (prep.isErr) continue;
      final inputs = prep.unwrap();
      if (inputs.fundamentals.isEmpty) continue;
      final f = inputs.fundamentals.last;
      final sector = inputs.sectorKey;
      if (sector == null) continue;

      // **O divisor da ponte, e não a contagem da fonte.** O múltiplo
      // observado tem de sair da mesma contagem que a cascata usa do outro
      // lado, ou a mediana e a leitura medem pontes diferentes (decisão 83).
      final divisor = ValuationCascade.quotedShares(
        latest: f,
        marketPrice: inputs.marketPrice,
        sharesPerQuote: inputs.declaredSharesPerUnit?.toDouble() ?? 1.0,
        published: inputs.fundamentals,
        official: inputs.officialShares,
        asOf: inputs.asOf,
      );
      if (divisor == null || divisor.count <= 0) continue;
      final marketValueOf = divisor.count * inputs.marketPrice;

      final profit = f.netIncome;
      final pl = f.totalStockholderEquity;
      final ebitda = f.ebitda;
      final financial = FinancialSectors.isFinancial(
        sectorKey: sector,
        industry: inputs.industry,
      );

      pairs.add(_Peer(
        ticker: t.value,
        sector: sector,
        subsector: inputs.industry,
        // Só múltiplo com a grandeza de baixo **positiva** entra na mediana:
        // P/L de prejuízo é negativo e não descreve quanto o mercado paga por
        // lucro — incluí-lo puxaria a mediana do setor para baixo por um
        // motivo que não é preço.
        priceToEarnings:
            profit != null && profit > 0 ? marketValueOf / profit : null,
        priceToBook: pl != null && pl > 0 ? marketValueOf / pl : null,
        // EBITDA de instituição financeira não descreve geração operacional
        // (decisão 102): ela não entra nem como par.
        evToEbitda: !financial && ebitda != null && ebitda > 0
            ? (marketValueOf + f.netDebt) / ebitda
            : null,
      ));
    }
    stderr.write('                              \r');

    // ---------------------------------------------------------------------
    // As medianas, por grupo
    // ---------------------------------------------------------------------
    final bySubsector = <String, List<_Peer>>{};
    final bySector = <String, List<_Peer>>{};
    for (final p in pairs) {
      bySector.putIfAbsent(p.sector, () => []).add(p);
      final sub = p.subsector;
      if (sub != null && sub.isNotEmpty) {
        bySubsector.putIfAbsent(sub, () => []).add(p);
      }
    }

    Map<String, Object?>? medianOf(List<_Peer> group, MultipleKind k,
        String name, {String? without}) {
      final v = _values(group, k, without: without);
      if (v.length < _minPeers) return null;
      return {'mediana': _median(v), 'pares': v.length, 'grupo': name};
    }

    final groups = <String, Map<String, Object?>>{};
    void register(String key, List<_Peer> group) {
      final m = <String, Object?>{};
      for (final k in MultipleKind.values) {
        final r = medianOf(group, k, key);
        if (r != null) m[k.key] = r;
      }
      if (m.isNotEmpty) groups[key] = m;
    }

    for (final e in bySubsector.entries) {
      register(e.key, e.value);
    }
    for (final e in bySector.entries) {
      register(e.key, e.value);
    }
    register(_market, pairs);

    // A ligação de cada ticker ao grupo que vale para ele: subsetor, setor,
    // mercado — na ordem, e **por múltiplo**, porque um subsetor pode ter pares
    // bastantes para P/VP e não para EV/EBITDA. A mediana de cada ticker é a
    // do grupo **sem a companhia dele** (item B41), e o mínimo de pares vale
    // sobre as outras companhias.
    final byTicker = <String, Map<String, Object?>>{};
    for (final p in pairs) {
      final chosen = <String, Object?>{};
      final without = _company(p.ticker);
      for (final k in MultipleKind.values) {
        for (final (key, members) in [
          (p.subsector, bySubsector[p.subsector]),
          (p.sector, bySector[p.sector]),
          (_market, pairs),
        ]) {
          if (key == null || members == null) continue;
          final m = medianOf(members, k, key, without: without);
          if (m != null) {
            chosen[k.key] = m;
            break;
          }
        }
      }
      if (chosen.isNotEmpty) byTicker[p.ticker] = chosen;
    }

    final json = <String, Object?>{
      'geradoEm': frozenToday.toIso8601String(),
      'minimoDePares': _minPeers,
      'observados': pairs.length,
      'grupos': groups,
      'porTicker': byTicker,
    };
    File(_output).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(json));

    stdout.writeln('-- múltiplos de pares, sobre a entrada congelada --');
    stdout.writeln('  observados                 ${pairs.length}');
    stdout.writeln('  grupos com alguma mediana  ${groups.length}');
    stdout.writeln('  tickers ligados            ${byTicker.length}');
    stdout.writeln('');
    stdout.writeln('  o mercado inteiro:');
    for (final k in MultipleKind.values) {
      final m = groups[_market]?[k.key] as Map<String, Object?>?;
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
    final keys = bySector.keys.toList()..sort();
    for (final key in keys) {
      final g = groups[key];
      if (g == null) continue;
      final row = <String>[];
      for (final k in MultipleKind.values) {
        final m = g[k.key] as Map<String, Object?>?;
        if (m == null) continue;
        final median = (m['mediana'] as double).toStringAsFixed(1);
        row.add('${k.label} $median× (${m['pares']})');
      }
      stdout.writeln('    ${key.padRight(32)} ${row.join("  ")}');
    }
    stdout.writeln('');
    stdout.writeln('escrito $_output');
  } finally {
    await c.ctx.dispose();
  }
}
