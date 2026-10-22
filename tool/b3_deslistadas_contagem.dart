// A3.4 — contagem de ações e eventos por data, para as companhias deslistadas.
//
// Para cada companhia da ponte de `b3_ponte.py` (A3.2), e para cada papel dela:
//
//   contagem   série do capital integralizado do Formulário de Referência:
//              aprovação a aprovação, evento a evento, e o formulário que a
//              série não explica na data de recebimento (`ShareCountHistory`)
//   eventos    desdobramento, grupamento e bonificação declarados no FRE, com
//              a data ex localizada no preço (`CorporateEvents.locate`); e,
//              onde o FRE não declara, os inferidos pelo preço (decisão 75)
//   série      fechamento do COTAHIST ajustado pelos dois
//
// **A escala é conferida de três jeitos**, porque companhia deslistada não tem
// valor de mercado publicado em data conhecida:
//
//   1. nas listadas, a contagem do FRE em 14/09/2026 contra a oficial da B3 —
//      é onde a verdade existe, e é o que valida o método;
//   2. nas deslistadas, a contagem do FRE contra a composição do capital do
//      DFP e do ITR da mesma data — dois formulários da CVM, preenchidos em
//      quadros diferentes;
//   3. e o preço sobre valor patrimonial por ação no fim de cada exercício,
//      que um erro de mil vezes na contagem tira de qualquer faixa plausível.
//
// Grava `data/b3/deslistadas_contagem.json`, para as coortes da Fase 2, e o
// resumo em `docs/validacao/b3_contagem_por_data.json`.
//
// **E as listadas, desde o item C3.** A coorte da listada também precisa da
// contagem da data — o valor de mercado dela era `contagem do exercício ×
// preço`, e a razão de unidade colapsava. A mesma série sai para cada companhia
// do universo em `data/b3/listadas_contagem.json`, com os eventos declarados
// localizados no preço dos códigos que a FCA declara. Nas duas, a série leva
// também a divisão entre ordinárias e preferenciais (`ClassesDoCapital`), para
// o valor de mercado espécie a espécie.
//
// Uso:
//   python tool/cvm_baixar.py --docs FRE --destino data/cvm/fre
//   dart run tool/b3_deslistadas_contagem.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'b3/proventos.dart';
import 'coortes/base_da_data.dart';
import 'cvm/codigos_fca.dart';
import 'cvm/csv.dart';

/// Contagens que batem: a 2% entre formulários, a 1% contra a B3.
const _formsMargin = 0.02;
const _b3Margin = 0.01;

/// P/VPA plausível para uma companhia com pregão: fora disto, a escala errou.
const _minPriceToBook = 0.02;
const _maxPriceToBook = 50.0;

Map<String, List<Map<String, String>>> _byCnpj(String pattern) {
  final out = <String, List<Map<String, String>>>{};
  final files = Directory('data/cvm/fre')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(pattern).hasMatch(f.uri.pathSegments.last))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    for (final r in readCvmCsv(f)) {
      final cnpj = r['CNPJ_Companhia'];
      if (cnpj != null) (out[cnpj] ??= []).add(r);
    }
  }
  return out;
}

/// Eventos de ações declarados no FRE de uma companhia, distintos.
List<({DateTime approval, double factor, double after, String kind})>
    _declared(List<Map<String, String>> rows) {
  final out = <({DateTime approval, double factor, double after, String kind})>[];
  final seen = <String>[];
  for (final r in rows) {
    final approval = DateTime.tryParse('${r['Data_Aprovacao']}T00:00:00Z');
    final before = double.tryParse(r['Quantidade_Total_Acoes_Antes_Aprovacao'] ?? '');
    final after = double.tryParse(r['Quantidade_Total_Acoes_Depois_Aprovacao'] ?? '');
    if (approval == null || before == null || after == null) continue;
    if (before <= 0 || after <= 0) continue;
    final key = '${_day(approval)}|${r['Quantidade_Total_Acoes_Antes_Aprovacao']}|'
        '${r['Quantidade_Total_Acoes_Depois_Aprovacao']}';
    if (seen.contains(key)) continue;
    seen.add(key);
    // Fator de 1 não é evento de ações: é o formulário repetindo a contagem.
    if (math.log(after / before).abs() < 1e-6) continue;
    out.add((
      approval: approval,
      factor: after / before,
      after: after,
      kind: r['Tipo_Evento'] ?? '',
    ));
  }
  return out;
}

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

String _day(DateTime d) => d.toIso8601String().substring(0, 10);

void main() {
  if (!Directory('data/cvm/fre').existsSync()) {
    stderr.writeln('sem data/cvm/fre — rode: python tool/cvm_baixar.py '
        '--docs FRE --destino data/cvm/fre');
    exit(2);
  }
  final bridge = (jsonDecode(File('data/b3/ponte_deslistadas.json')
          .readAsStringSync()) as Map<String, dynamic>)
      .cast<String, Map<String, dynamic>>();
  final capital = _byCnpj(r'^fre_cia_aberta_capital_social_\d{4}\.csv$');
  final splits =
      _byCnpj(r'^fre_cia_aberta_capital_social_desdobramento_\d{4}\.csv$');
  // Recebimento de cada formulário, para datar a contagem que a série não
  // explica (`ShareCountSource.filingCorrection`).
  final receivedInputs = <String, DateTime>{};
  for (final f in Directory('data/cvm/fre').listSync().whereType<File>()) {
    if (!RegExp(r'^fre_cia_aberta_\d{4}\.csv$')
        .hasMatch(f.uri.pathSegments.last)) {
      continue;
    }
    for (final r in readCvmCsv(f)) {
      final id = r['ID_DOC'];
      final day = DateTime.tryParse('${r['DT_RECEB']}T00:00:00Z');
      if (id != null && day != null) receivedInputs[id] = day;
    }
  }
  stderr.writeln('FRE: capital de ${capital.length} companhias, eventos de '
      '${splits.length}');

  // Composição do capital do DFP e do ITR, e patrimônio do DFP, por CNPJ.
  final composition = <String, List<({DateTime date, double shares})>>{};
  final equity = <String, Map<int, double>>{};
  for (final d in (jsonDecode(File('data/cvm_exercicios.json').readAsStringSync())
          as List)
      .cast<Map<String, dynamic>>()) {
    final cnpj = d['cnpj'] as String;
    final end = DateTime.tryParse('${d['fimDoExercicio']}T00:00:00Z');
    if (end == null) continue;
    final shares = (d['acoesIntegralizadas'] as num?)?.toDouble();
    if (shares != null && shares > 0) {
      (composition[cnpj] ??= []).add((date: end, shares: shares));
    }
    final pl = (d['patrimonioLiquido'] as num?)?.toDouble();
    if (d['documento'] == 'DFP' && pl != null && pl > 0) {
      (equity[cnpj] ??= {})[end.year] = pl;
    }
  }

  final tickers = {
    for (final c in bridge.values)
      ...(c['papeis'] as Map<String, dynamic>).keys,
  };
  // Os códigos das listadas: os da ponte do universo e os que a FCA declara.
  final listedBridge = ((jsonDecode(File('docs/validacao/ponte_cvm.json')
          .readAsStringSync()) as Map<String, dynamic>)['ponte']
      as Map<String, dynamic>);
  final fca = FcaCodes.read();
  final listedCodes = <String, Set<String>>{};
  for (final e in listedBridge.entries) {
    final cnpj = e.value as String;
    (listedCodes[cnpj] ??= <String>{})
      ..add(e.key)
      ..addAll(fca.byCnpj[cnpj] ?? const <String>{});
  }
  for (final e in listedCodes.entries) {
    listedCodes[e.key] = companyCodes(e.value);
  }

  // Proventos das deslistadas, pelo nome de pregão (item A4): a consulta da B3
  // responde para companhia que saiu da bolsa. Um nome de pregão pode ser de
  // outra companhia; o preço com direito contra o COTAHIST do papel é o que
  // confere que é a mesma.
  final delistedDividends = <String, List<CashDividend>>{};
  final dividendsDir = Directory('data/b3/complemento_deslistadas');
  if (dividendsDir.existsSync()) {
    for (final f in dividendsDir.listSync().whereType<File>()) {
      final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      delistedDividends[raw['cnpj'] as String] = [
        for (final queryDir in (raw['consultas'] as List).cast<Map<String, dynamic>>())
          ...B3CashDividends.parse(
              (queryDir['proventos'] as List).cast<Object?>()),
      ];
    }
  }
  final cotahist = readRawCotahist(
      {...tickers, for (final c in listedCodes.values) ...c});

  // ---- 1. O método nas listadas: FRE contra a contagem oficial da B3 ----
  final registry = B3RegistryCodec.decodePackage(
      jsonDecode(File('assets/b3/emissores.json').readAsStringSync())
          as Map<String, dynamic>);
  final queryDir = DateTime.utc(2026, 9, 14);
  var listed = 0, listedMatching = 0;
  final seenIssuers = <String>[];
  final divergentListed = <String>[];
  for (final e in listedBridge.entries) {
    final root = e.key.length >= 4 ? e.key.substring(0, 4) : '';
    if (seenIssuers.contains(root)) continue;
    final official = registry[root]?.totalShares;
    final fre = capital[e.value as String];
    if (official == null || fre == null) continue;
    final point = ShareCountHistory.fromFre(
      fre,
      events: [
        for (final d in _declared(splits[e.value] ?? const []))
          (date: d.approval, totalAfter: d.after),
      ],
      receivedOn: receivedInputs,
    ).at(queryDir);
    if (point == null) continue;
    seenIssuers.add(root);
    listed++;
    final ratio = point.total / official;
    if ((ratio - 1).abs() <= _b3Margin) {
      listedMatching++;
    } else {
      divergentListed.add('$root ${ratio.toStringAsFixed(4)}');
    }
  }

  // ---- 1b. A contagem por data das listadas, para as coortes (item C3) ----
  final listedOutput = <String, Object?>{};
  var listedWithCount = 0, listedEvents = 0, listedLocatedEvents = 0;
  for (final entry in listedCodes.entries) {
    final cnpj = entry.key;
    final declared = _declared(splits[cnpj] ?? const []);
    // A data ex de cada evento, no primeiro código que o localiza.
    final firstExDate = <int, DateTime>{};
    for (final code in entry.value) {
      final series = cotahist[code];
      if (series == null || series.isEmpty) continue;
      final rawSessions = [for (final p in series) p.raw];
      for (var k = 0; k < declared.length; k++) {
        final ev = CorporateEvents.locate(rawSessions,
            factor: declared[k].factor, approvedOn: declared[k].approval);
        if (ev == null) continue;
        final existing = firstExDate[k];
        if (existing == null || ev.exDate.isBefore(existing)) firstExDate[k] = ev.exDate;
      }
    }
    listedEvents += declared.length;
    listedLocatedEvents += firstExDate.length;
    final history = ShareCountHistory.fromFre(
      capital[cnpj] ?? const [],
      events: [
        for (var k = 0; k < declared.length; k++)
          (date: firstExDate[k] ?? declared[k].approval, totalAfter: declared[k].after),
      ],
      receivedOn: receivedInputs,
    );
    if (history.points.isEmpty) continue;
    listedWithCount++;
    listedOutput[cnpj] = {
      'codigos': entry.value.toList()..sort(),
      'contagem': [
        for (final p in history.points)
          {'desde': _day(p.date), 'acoes': p.total, 'fonte': p.source.name},
      ],
      'classes': CapitalClasses.fromFre(capital[cnpj] ?? const []).toJson(),
    };
  }
  File('data/b3/listadas_contagem.json').writeAsStringSync(jsonEncode(listedOutput));

  // ---- 2 e 3: as deslistadas ---------------------------------------------
  final output = <String, Object?>{};
  var withCount = 0, withFreEvents = 0, freEvents = 0, located = 0;
  var eventsWithTradingDay = 0, locatedEvents = 0;
  final notLocated = <String>[];
  var inferred = 0, formMatches = 0, formChecks = 0;
  var priceToBookWithin = 0, priceToBookChecks = 0, usableFiscalYears = 0;
  var companiesWithDividends = 0, securityDividends = 0;
  var checkedDividends = 0, dividendsMatching = 0;
  final priceToBooks = <double>[];
  final outOfRange = <String>[];
  for (final entry in bridge.entries) {
    final cnpj = entry.key;
    final c = entry.value;
    final declared = _declared(splits[cnpj] ?? const []);
    // Data ex de cada evento declarado, quando algum papel a localizou: é nela
    // que a contagem muda; sem ela, vale a aprovação.
    final firstExDate = <int, DateTime>{};
    if (declared.isNotEmpty) withFreEvents++;
    freEvents += declared.length;

    // Evento com pregão do papel na data de aprovação é o que se pode
    // localizar; antes de 2010 não há COTAHIST, e fora da vida do papel não há
    // preço a ajustar.
    final findings = <int>[];
    for (var k = 0; k < declared.length; k++) {
      final d = declared[k];
      final withTradingDay = (c['papeis'] as Map<String, dynamic>).keys.any((t) {
        final s = cotahist[t];
        return s != null &&
            s.isNotEmpty &&
            !s.first.date.isAfter(d.approval) &&
            !s.last.date.isBefore(d.approval);
      });
      if (withTradingDay) eventsWithTradingDay++;
    }

    final securities = <String, Object?>{};
    for (final t in (c['papeis'] as Map<String, dynamic>).keys) {
      final series = cotahist[t];
      if (series == null || series.isEmpty) continue;
      final rawSessions = [for (final p in series) p.raw];
      final events = <ShareEvent>[];
      final origin = <String>[];
      final securityFindings = <int>[];
      for (var k = 0; k < declared.length; k++) {
        final d = declared[k];
        final ev = CorporateEvents.locate(rawSessions,
            factor: d.factor, approvedOn: d.approval);
        if (ev == null) continue;
        events.add(ev);
        origin.add('fre');
        located++;
        securityFindings.add(k);
        if (!findings.contains(k)) findings.add(k);
        final existing = firstExDate[k];
        if (existing == null || ev.exDate.isBefore(existing)) firstExDate[k] = ev.exDate;
      }
      for (final ev in CorporateEvents.detect(rawSessions)) {
        final near = events.any((e) => e.exDate.difference(ev.exDate).inDays.abs() <= 15);
        if (near) continue;
        events.add(ev);
        origin.add('inferido');
        inferred++;
      }
      // Proventos da classe do papel, com data ex na vida dele.
      final shareClass = B3CashDividends.shareClassOf(t);
      final ofSecurity = [
        for (final p in delistedDividends[cnpj] ?? const <CashDividend>[])
          if (p.shareClass == shareClass &&
              !p.exDate.isBefore(series.first.date) &&
              !p.exDate.isAfter(series.last.date))
            p,
      ];
      securityDividends += ofSecurity.length;
      for (final p in ofSecurity) {
        final withInput = tradingDayUntil(series, p.lastDateWithRights, marginDays: 0);
        if (p.closeWithRights == null || withInput == null) continue;
        checkedDividends++;
        if ((p.closeWithRights! / withInput.close - 1).abs() <= 0.01) dividendsMatching++;
      }

      securities[t] = {
        'primeiro': _day(series.first.date),
        'ultimo': _day(series.last.date),
        'proventos': [
          for (final p in ofSecurity)
            {
              'dataEx': _day(p.exDate),
              'valor': p.amount,
              'tipo': p.kind.key,
              if (p.closeWithRights != null) 'precoComDireito': p.closeWithRights,
            },
        ],
        // Evento declarado com pregão e sem data ex no preço: a série não está
        // ajustada por ele, e a coorte cuja janela o atravessa tem de sair.
        'eventosNaoLocalizados': [
          for (var k = 0; k < declared.length; k++)
            if (!securityFindings.contains(k) &&
                !series.first.date.isAfter(declared[k].approval) &&
                !series.last.date.isBefore(declared[k].approval))
              _day(declared[k].approval),
        ],
        'eventos': [
          for (var k = 0; k < events.length; k++)
            {
              'dataEx': _day(events[k].exDate),
              'fator': events[k].factor,
              'origem': origin[k],
            },
        ],
      };
    }

    if ((delistedDividends[cnpj] ?? const []).isNotEmpty) {
      companiesWithDividends++;
    }
    locatedEvents += findings.length;
    final history = ShareCountHistory.fromFre(
      capital[cnpj] ?? const [],
      events: [
        for (var k = 0; k < declared.length; k++)
          (date: firstExDate[k] ?? declared[k].approval, totalAfter: declared[k].after),
      ],
      receivedOn: receivedInputs,
    );
    if (history.points.isNotEmpty) withCount++;
    for (var k = 0; k < declared.length; k++) {
      final d = declared[k];
      final alive = (c['papeis'] as Map<String, dynamic>).keys.any((t) {
        final s = cotahist[t];
        return s != null &&
            s.isNotEmpty &&
            !s.first.date.isAfter(d.approval) &&
            !s.last.date.isBefore(d.approval);
      });
      if (alive && !findings.contains(k)) {
        notLocated.add('${c['nome']} ${_day(d.approval)} ${d.kind} '
            'fator ${d.factor.toStringAsFixed(4)}');
      }
    }

    // 2. Formulário contra formulário.
    final checks = <Map<String, Object?>>[];
    for (final x in composition[cnpj] ?? const <({DateTime date, double shares})>[]) {
      final point = history.at(x.date);
      if (point == null) continue;
      formChecks++;
      final ratio = point.total / x.shares;
      // A composição do capital vem na escala do declarante — mil ações, em
      // quem publica em milhares (decisão 70). Mil exatas é a mesma contagem.
      final matches = (ratio - 1).abs() <= _formsMargin ||
          (ratio / 1000 - 1).abs() <= _formsMargin;
      if (matches) formMatches++;
      checks.add({'data': _day(x.date), 'razao': ratio, 'bate': matches});
    }

    // 3. P/VPA no fim de cada exercício, e o exercício utilizável: contagem na
    //    data e pregão no ano seguinte.
    for (final year in ((c['anosDfp'] as List?) ?? const []).cast<int>()) {
      final end = DateTime.utc(year, 12, 31);
      final point = history.at(end);
      final pl = equity[cnpj]?[year];
      final withTradingDayAfter = (c['papeis'] as Map<String, dynamic>).keys.any((t) {
        final s = cotahist[t];
        return s != null && s.any((p) => p.date.year == year + 1);
      });
      if (point != null && withTradingDayAfter) usableFiscalYears++;
      if (point == null || pl == null) continue;
      for (final t in (c['papeis'] as Map<String, dynamic>).keys) {
        final s = cotahist[t];
        if (s == null) continue;
        final p = tradingDayUntil(s, end, marginDays: 10);
        if (p == null) continue;
        final priceToBook = point.total * p.close / pl;
        priceToBookChecks++;
        priceToBooks.add(priceToBook);
        if (priceToBook >= _minPriceToBook && priceToBook <= _maxPriceToBook) {
          priceToBookWithin++;
        } else {
          outOfRange.add('${c['nome']} $t $year: ${priceToBook.toStringAsFixed(3)}');
        }
        break;
      }
    }

    output[cnpj] = {
      'nome': c['nome'],
      'contagem': [
        for (final p in history.points)
          {'desde': _day(p.date), 'acoes': p.total, 'fonte': p.source.name},
      ],
      'papeis': securities,
      'classes': CapitalClasses.fromFre(capital[cnpj] ?? const []).toJson(),
      'conferenciaComComposicao': checks,
    };
  }

  File('data/b3/deslistadas_contagem.json').writeAsStringSync(jsonEncode(output));
  final summary = {
    'medidoEm': '2026-09-15',
    'listadas': {
      'emissores': listed,
      'batemA1pct': listedMatching,
      'divergentes': divergentListed,
      'companhiasComContagemPorData': listedWithCount,
      'eventosDeclarados': listedEvents,
      'eventosLocalizados': listedLocatedEvents,
    },
    'deslistadas': {
      'companhias': bridge.length,
      'comContagem': withCount,
      'comEventosDeclarados': withFreEvents,
      'eventosDeclarados': freEvents,
      'eventosComPregaoNaAprovacao': eventsWithTradingDay,
      'eventosLocalizados': locatedEvents,
      'eventosNaoLocalizados': notLocated,
      'papelEventoLocalizado': located,
      'papelEventoInferido': inferred,
      'composicaoConferida': formChecks,
      'composicaoBateA2pct': formMatches,
      'pvpaConferido': priceToBookChecks,
      'pvpaNaFaixa': priceToBookWithin,
      'pvpaMediano': _median(priceToBooks),
      'pvpaForaDaFaixa': outOfRange,
      'exerciciosUtilizaveis': usableFiscalYears,
      'companhiasComProventos': companiesWithDividends,
      'proventosNaVidaDoPapel': securityDividends,
      'proventosComPrecoConferido': checkedDividends,
      'proventosQueBatemA1pct': dividendsMatching,
    },
  };
  File('docs/validacao/b3_contagem_por_data.json')
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(summary));

  stdout.writeln('== 1. Listadas: FRE em 14/09/2026 contra a contagem oficial ==');
  stdout.writeln('  $listedMatching de $listed a 1%');
  for (final d in divergentListed.take(15)) {
    stdout.writeln('    $d');
  }
  stdout.writeln('  contagem por data para as coortes: $listedWithCount '
      'companhias; $listedLocatedEvents de $listedEvents eventos '
      'declarados localizados no preço');
  stdout.writeln('\n== Deslistadas (${bridge.length} companhias da ponte) ==');
  stdout.writeln('  com contagem por data: $withCount');
  stdout.writeln('  com evento declarado no FRE: $withFreEvents '
      '($freEvents eventos); com pregão na aprovação: $eventsWithTradingDay; '
      'localizados no preço: $locatedEvents; inferidos onde o FRE não '
      'declara: $inferred');
  for (final n in notLocated) {
    stdout.writeln('    não localizado: $n');
  }
  stdout.writeln('  2. FRE × composição do DFP/ITR: $formMatches de '
      '$formChecks a 2%, contando a escala de mil (decisão 70)');
  stdout.writeln('  3. P/VPA no fim do exercício: $priceToBookWithin de $priceToBookChecks '
      'entre $_minPriceToBook e $_maxPriceToBook; mediana '
      '${_median(priceToBooks)?.toStringAsFixed(2)}');
  for (final f in outOfRange.take(12)) {
    stdout.writeln('    $f');
  }
  stdout.writeln('  exercícios com contagem na data e pregão no ano seguinte: '
      '$usableFiscalYears');
  stdout.writeln('  4. proventos: $companiesWithDividends companhias; '
      '$securityDividends na vida dos papéis; preço com direito contra o '
      'COTAHIST: $dividendsMatching de $checkedDividends a 1%');
  stdout.writeln('\n  gravado data/b3/deslistadas_contagem.json, '
      'data/b3/listadas_contagem.json e docs/validacao/b3_contagem_por_data.json');
}
