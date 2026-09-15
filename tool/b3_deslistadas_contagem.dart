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
const _folgaFormularios = 0.02;
const _folgaB3 = 0.01;

/// P/VPA plausível para uma companhia com pregão: fora disto, a escala errou.
const _pvpaMinimo = 0.02;
const _pvpaMaximo = 50.0;

Map<String, List<Map<String, String>>> _porCnpj(String padrao) {
  final out = <String, List<Map<String, String>>>{};
  final arquivos = Directory('data/cvm/fre')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(padrao).hasMatch(f.uri.pathSegments.last))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in arquivos) {
    for (final r in lerCsvCvm(f)) {
      final cnpj = r['CNPJ_Companhia'];
      if (cnpj != null) (out[cnpj] ??= []).add(r);
    }
  }
  return out;
}

/// Eventos de ações declarados no FRE de uma companhia, distintos.
List<({DateTime aprovacao, double fator, double depois, String tipo})>
    _declarados(List<Map<String, String>> linhas) {
  final out = <({DateTime aprovacao, double fator, double depois, String tipo})>[];
  final vistos = <String>[];
  for (final r in linhas) {
    final aprov = DateTime.tryParse('${r['Data_Aprovacao']}T00:00:00Z');
    final antes = double.tryParse(r['Quantidade_Total_Acoes_Antes_Aprovacao'] ?? '');
    final depois = double.tryParse(r['Quantidade_Total_Acoes_Depois_Aprovacao'] ?? '');
    if (aprov == null || antes == null || depois == null) continue;
    if (antes <= 0 || depois <= 0) continue;
    final chave = '${_dia(aprov)}|${r['Quantidade_Total_Acoes_Antes_Aprovacao']}|'
        '${r['Quantidade_Total_Acoes_Depois_Aprovacao']}';
    if (vistos.contains(chave)) continue;
    vistos.add(chave);
    // Fator de 1 não é evento de ações: é o formulário repetindo a contagem.
    if (math.log(depois / antes).abs() < 1e-6) continue;
    out.add((
      aprovacao: aprov,
      fator: depois / antes,
      depois: depois,
      tipo: r['Tipo_Evento'] ?? '',
    ));
  }
  return out;
}

double? _mediana(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

String _dia(DateTime d) => d.toIso8601String().substring(0, 10);

void main() {
  if (!Directory('data/cvm/fre').existsSync()) {
    stderr.writeln('sem data/cvm/fre — rode: python tool/cvm_baixar.py '
        '--docs FRE --destino data/cvm/fre');
    exit(2);
  }
  final ponte = (jsonDecode(File('data/b3/ponte_deslistadas.json')
          .readAsStringSync()) as Map<String, dynamic>)
      .cast<String, Map<String, dynamic>>();
  final capital = _porCnpj(r'^fre_cia_aberta_capital_social_\d{4}\.csv$');
  final desdobramentos =
      _porCnpj(r'^fre_cia_aberta_capital_social_desdobramento_\d{4}\.csv$');
  // Recebimento de cada formulário, para datar a contagem que a série não
  // explica (`ShareCountSource.filingCorrection`).
  final recebidos = <String, DateTime>{};
  for (final f in Directory('data/cvm/fre').listSync().whereType<File>()) {
    if (!RegExp(r'^fre_cia_aberta_\d{4}\.csv$')
        .hasMatch(f.uri.pathSegments.last)) {
      continue;
    }
    for (final r in lerCsvCvm(f)) {
      final id = r['ID_DOC'];
      final dia = DateTime.tryParse('${r['DT_RECEB']}T00:00:00Z');
      if (id != null && dia != null) recebidos[id] = dia;
    }
  }
  stderr.writeln('FRE: capital de ${capital.length} companhias, eventos de '
      '${desdobramentos.length}');

  // Composição do capital do DFP e do ITR, e patrimônio do DFP, por CNPJ.
  final composicao = <String, List<({DateTime data, double acoes})>>{};
  final patrimonio = <String, Map<int, double>>{};
  for (final d in (jsonDecode(File('data/cvm_exercicios.json').readAsStringSync())
          as List)
      .cast<Map<String, dynamic>>()) {
    final cnpj = d['cnpj'] as String;
    final fim = DateTime.tryParse('${d['fimDoExercicio']}T00:00:00Z');
    if (fim == null) continue;
    final acoes = (d['acoesIntegralizadas'] as num?)?.toDouble();
    if (acoes != null && acoes > 0) {
      (composicao[cnpj] ??= []).add((data: fim, acoes: acoes));
    }
    final pl = (d['patrimonioLiquido'] as num?)?.toDouble();
    if (d['documento'] == 'DFP' && pl != null && pl > 0) {
      (patrimonio[cnpj] ??= {})[fim.year] = pl;
    }
  }

  final tickers = {
    for (final c in ponte.values)
      ...(c['papeis'] as Map<String, dynamic>).keys,
  };
  // Os códigos das listadas: os da ponte do universo e os que a FCA declara.
  final ponteListadas = ((jsonDecode(File('docs/validacao/ponte_cvm.json')
          .readAsStringSync()) as Map<String, dynamic>)['ponte']
      as Map<String, dynamic>);
  final fca = CodigosFca.ler();
  final codigosListadas = <String, Set<String>>{};
  for (final e in ponteListadas.entries) {
    final cnpj = e.value as String;
    (codigosListadas[cnpj] ??= <String>{})
      ..add(e.key)
      ..addAll(fca.porCnpj[cnpj] ?? const <String>{});
  }
  for (final e in codigosListadas.entries) {
    codigosListadas[e.key] = codigosDaCompanhia(e.value);
  }

  // Proventos das deslistadas, pelo nome de pregão (item A4): a consulta da B3
  // responde para companhia que saiu da bolsa. Um nome de pregão pode ser de
  // outra companhia; o preço com direito contra o COTAHIST do papel é o que
  // confere que é a mesma.
  final proventosDeslistadas = <String, List<CashDividend>>{};
  final pastaProventos = Directory('data/b3/complemento_deslistadas');
  if (pastaProventos.existsSync()) {
    for (final f in pastaProventos.listSync().whereType<File>()) {
      final bruto = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      proventosDeslistadas[bruto['cnpj'] as String] = [
        for (final consulta in (bruto['consultas'] as List).cast<Map<String, dynamic>>())
          ...B3CashDividends.parse(
              (consulta['proventos'] as List).cast<Object?>()),
      ];
    }
  }
  final cotahist = lerCotahistBruto(
      {...tickers, for (final c in codigosListadas.values) ...c});

  // ---- 1. O método nas listadas: FRE contra a contagem oficial da B3 ----
  final registro = B3RegistryCodec.decodePackage(
      jsonDecode(File('assets/b3/emissores.json').readAsStringSync())
          as Map<String, dynamic>);
  final consulta = DateTime.utc(2026, 9, 14);
  var listadas = 0, listadasBatem = 0;
  final emissoresVistos = <String>[];
  final divergentesListadas = <String>[];
  for (final e in ponteListadas.entries) {
    final raiz = e.key.length >= 4 ? e.key.substring(0, 4) : '';
    if (emissoresVistos.contains(raiz)) continue;
    final oficial = registro[raiz]?.totalShares;
    final fre = capital[e.value as String];
    if (oficial == null || fre == null) continue;
    final ponto = ShareCountHistory.fromFre(
      fre,
      events: [
        for (final d in _declarados(desdobramentos[e.value] ?? const []))
          (date: d.aprovacao, totalAfter: d.depois),
      ],
      receivedOn: recebidos,
    ).at(consulta);
    if (ponto == null) continue;
    emissoresVistos.add(raiz);
    listadas++;
    final razao = ponto.total / oficial;
    if ((razao - 1).abs() <= _folgaB3) {
      listadasBatem++;
    } else {
      divergentesListadas.add('$raiz ${razao.toStringAsFixed(4)}');
    }
  }

  // ---- 1b. A contagem por data das listadas, para as coortes (item C3) ----
  final saidaListadas = <String, Object?>{};
  var listadasComContagem = 0, listadasEventos = 0, listadasEventosLocalizados = 0;
  for (final entrada in codigosListadas.entries) {
    final cnpj = entrada.key;
    final declarados = _declarados(desdobramentos[cnpj] ?? const []);
    // A data ex de cada evento, no primeiro código que o localiza.
    final dataEx = <int, DateTime>{};
    for (final codigo in entrada.value) {
      final serie = cotahist[codigo];
      if (serie == null || serie.isEmpty) continue;
      final brutos = [for (final p in serie) p.raw];
      for (var k = 0; k < declarados.length; k++) {
        final ev = CorporateEvents.locate(brutos,
            factor: declarados[k].fator, approvedOn: declarados[k].aprovacao);
        if (ev == null) continue;
        final ja = dataEx[k];
        if (ja == null || ev.exDate.isBefore(ja)) dataEx[k] = ev.exDate;
      }
    }
    listadasEventos += declarados.length;
    listadasEventosLocalizados += dataEx.length;
    final historico = ShareCountHistory.fromFre(
      capital[cnpj] ?? const [],
      events: [
        for (var k = 0; k < declarados.length; k++)
          (date: dataEx[k] ?? declarados[k].aprovacao, totalAfter: declarados[k].depois),
      ],
      receivedOn: recebidos,
    );
    if (historico.points.isEmpty) continue;
    listadasComContagem++;
    saidaListadas[cnpj] = {
      'codigos': entrada.value.toList()..sort(),
      'contagem': [
        for (final p in historico.points)
          {'desde': _dia(p.date), 'acoes': p.total, 'fonte': p.source.name},
      ],
      'classes': ClassesDoCapital.fromFre(capital[cnpj] ?? const []).toJson(),
    };
  }
  File('data/b3/listadas_contagem.json').writeAsStringSync(jsonEncode(saidaListadas));

  // ---- 2 e 3: as deslistadas ---------------------------------------------
  final saida = <String, Object?>{};
  var comContagem = 0, comEventosFre = 0, eventosFre = 0, localizados = 0;
  var eventosComPregao = 0, eventosLocalizados = 0;
  final naoLocalizados = <String>[];
  var inferidos = 0, formularioBate = 0, formularioConfere = 0;
  var pvpaDentro = 0, pvpaConfere = 0, exerciciosUtilizaveis = 0;
  var companhiasComProventos = 0, proventosNoPapel = 0;
  var proventosConferidos = 0, proventosBatem = 0;
  final pvpas = <double>[];
  final foraDaFaixa = <String>[];
  for (final entrada in ponte.entries) {
    final cnpj = entrada.key;
    final c = entrada.value;
    final declarados = _declarados(desdobramentos[cnpj] ?? const []);
    // Data ex de cada evento declarado, quando algum papel a localizou: é nela
    // que a contagem muda; sem ela, vale a aprovação.
    final dataEx = <int, DateTime>{};
    if (declarados.isNotEmpty) comEventosFre++;
    eventosFre += declarados.length;

    // Evento com pregão do papel na data de aprovação é o que se pode
    // localizar; antes de 2010 não há COTAHIST, e fora da vida do papel não há
    // preço a ajustar.
    final achados = <int>[];
    for (var k = 0; k < declarados.length; k++) {
      final d = declarados[k];
      final comPregao = (c['papeis'] as Map<String, dynamic>).keys.any((t) {
        final s = cotahist[t];
        return s != null &&
            s.isNotEmpty &&
            !s.first.date.isAfter(d.aprovacao) &&
            !s.last.date.isBefore(d.aprovacao);
      });
      if (comPregao) eventosComPregao++;
    }

    final papeis = <String, Object?>{};
    for (final t in (c['papeis'] as Map<String, dynamic>).keys) {
      final serie = cotahist[t];
      if (serie == null || serie.isEmpty) continue;
      final brutos = [for (final p in serie) p.raw];
      final eventos = <ShareEvent>[];
      final origem = <String>[];
      final achadosDoPapel = <int>[];
      for (var k = 0; k < declarados.length; k++) {
        final d = declarados[k];
        final ev = CorporateEvents.locate(brutos,
            factor: d.fator, approvedOn: d.aprovacao);
        if (ev == null) continue;
        eventos.add(ev);
        origem.add('fre');
        localizados++;
        achadosDoPapel.add(k);
        if (!achados.contains(k)) achados.add(k);
        final ja = dataEx[k];
        if (ja == null || ev.exDate.isBefore(ja)) dataEx[k] = ev.exDate;
      }
      for (final ev in CorporateEvents.detect(brutos)) {
        final perto = eventos.any((e) => e.exDate.difference(ev.exDate).inDays.abs() <= 15);
        if (perto) continue;
        eventos.add(ev);
        origem.add('inferido');
        inferidos++;
      }
      // Proventos da classe do papel, com data ex na vida dele.
      final classe = B3CashDividends.shareClassOf(t);
      final doPapel = [
        for (final p in proventosDeslistadas[cnpj] ?? const <CashDividend>[])
          if (p.shareClass == classe &&
              !p.exDate.isBefore(serie.first.date) &&
              !p.exDate.isAfter(serie.last.date))
            p,
      ];
      proventosNoPapel += doPapel.length;
      for (final p in doPapel) {
        final com = pregaoAte(serie, p.lastDateWithRights, folgaDias: 0);
        if (p.closeWithRights == null || com == null) continue;
        proventosConferidos++;
        if ((p.closeWithRights! / com.close - 1).abs() <= 0.01) proventosBatem++;
      }

      papeis[t] = {
        'primeiro': _dia(serie.first.date),
        'ultimo': _dia(serie.last.date),
        'proventos': [
          for (final p in doPapel)
            {
              'dataEx': _dia(p.exDate),
              'valor': p.amount,
              'tipo': p.kind.name,
              if (p.closeWithRights != null) 'precoComDireito': p.closeWithRights,
            },
        ],
        // Evento declarado com pregão e sem data ex no preço: a série não está
        // ajustada por ele, e a coorte cuja janela o atravessa tem de sair.
        'eventosNaoLocalizados': [
          for (var k = 0; k < declarados.length; k++)
            if (!achadosDoPapel.contains(k) &&
                !serie.first.date.isAfter(declarados[k].aprovacao) &&
                !serie.last.date.isBefore(declarados[k].aprovacao))
              _dia(declarados[k].aprovacao),
        ],
        'eventos': [
          for (var k = 0; k < eventos.length; k++)
            {
              'dataEx': _dia(eventos[k].exDate),
              'fator': eventos[k].factor,
              'origem': origem[k],
            },
        ],
      };
    }

    if ((proventosDeslistadas[cnpj] ?? const []).isNotEmpty) {
      companhiasComProventos++;
    }
    eventosLocalizados += achados.length;
    final historico = ShareCountHistory.fromFre(
      capital[cnpj] ?? const [],
      events: [
        for (var k = 0; k < declarados.length; k++)
          (date: dataEx[k] ?? declarados[k].aprovacao, totalAfter: declarados[k].depois),
      ],
      receivedOn: recebidos,
    );
    if (historico.points.isNotEmpty) comContagem++;
    for (var k = 0; k < declarados.length; k++) {
      final d = declarados[k];
      final vivo = (c['papeis'] as Map<String, dynamic>).keys.any((t) {
        final s = cotahist[t];
        return s != null &&
            s.isNotEmpty &&
            !s.first.date.isAfter(d.aprovacao) &&
            !s.last.date.isBefore(d.aprovacao);
      });
      if (vivo && !achados.contains(k)) {
        naoLocalizados.add('${c['nome']} ${_dia(d.aprovacao)} ${d.tipo} '
            'fator ${d.fator.toStringAsFixed(4)}');
      }
    }

    // 2. Formulário contra formulário.
    final conferencias = <Map<String, Object?>>[];
    for (final x in composicao[cnpj] ?? const <({DateTime data, double acoes})>[]) {
      final ponto = historico.at(x.data);
      if (ponto == null) continue;
      formularioConfere++;
      final razao = ponto.total / x.acoes;
      // A composição do capital vem na escala do declarante — mil ações, em
      // quem publica em milhares (decisão 70). Mil exatas é a mesma contagem.
      final bate = (razao - 1).abs() <= _folgaFormularios ||
          (razao / 1000 - 1).abs() <= _folgaFormularios;
      if (bate) formularioBate++;
      conferencias.add({'data': _dia(x.data), 'razao': razao, 'bate': bate});
    }

    // 3. P/VPA no fim de cada exercício, e o exercício utilizável: contagem na
    //    data e pregão no ano seguinte.
    for (final ano in ((c['anosDfp'] as List?) ?? const []).cast<int>()) {
      final fim = DateTime.utc(ano, 12, 31);
      final ponto = historico.at(fim);
      final pl = patrimonio[cnpj]?[ano];
      final comPregaoDepois = (c['papeis'] as Map<String, dynamic>).keys.any((t) {
        final s = cotahist[t];
        return s != null && s.any((p) => p.date.year == ano + 1);
      });
      if (ponto != null && comPregaoDepois) exerciciosUtilizaveis++;
      if (ponto == null || pl == null) continue;
      for (final t in (c['papeis'] as Map<String, dynamic>).keys) {
        final s = cotahist[t];
        if (s == null) continue;
        final p = pregaoAte(s, fim, folgaDias: 10);
        if (p == null) continue;
        final pvpa = ponto.total * p.close / pl;
        pvpaConfere++;
        pvpas.add(pvpa);
        if (pvpa >= _pvpaMinimo && pvpa <= _pvpaMaximo) {
          pvpaDentro++;
        } else {
          foraDaFaixa.add('${c['nome']} $t $ano: ${pvpa.toStringAsFixed(3)}');
        }
        break;
      }
    }

    saida[cnpj] = {
      'nome': c['nome'],
      'contagem': [
        for (final p in historico.points)
          {'desde': _dia(p.date), 'acoes': p.total, 'fonte': p.source.name},
      ],
      'papeis': papeis,
      'classes': ClassesDoCapital.fromFre(capital[cnpj] ?? const []).toJson(),
      'conferenciaComComposicao': conferencias,
    };
  }

  File('data/b3/deslistadas_contagem.json').writeAsStringSync(jsonEncode(saida));
  final resumo = {
    'medidoEm': '2026-09-15',
    'listadas': {
      'emissores': listadas,
      'batemA1pct': listadasBatem,
      'divergentes': divergentesListadas,
      'companhiasComContagemPorData': listadasComContagem,
      'eventosDeclarados': listadasEventos,
      'eventosLocalizados': listadasEventosLocalizados,
    },
    'deslistadas': {
      'companhias': ponte.length,
      'comContagem': comContagem,
      'comEventosDeclarados': comEventosFre,
      'eventosDeclarados': eventosFre,
      'eventosComPregaoNaAprovacao': eventosComPregao,
      'eventosLocalizados': eventosLocalizados,
      'eventosNaoLocalizados': naoLocalizados,
      'papelEventoLocalizado': localizados,
      'papelEventoInferido': inferidos,
      'composicaoConferida': formularioConfere,
      'composicaoBateA2pct': formularioBate,
      'pvpaConferido': pvpaConfere,
      'pvpaNaFaixa': pvpaDentro,
      'pvpaMediano': _mediana(pvpas),
      'pvpaForaDaFaixa': foraDaFaixa,
      'exerciciosUtilizaveis': exerciciosUtilizaveis,
      'companhiasComProventos': companhiasComProventos,
      'proventosNaVidaDoPapel': proventosNoPapel,
      'proventosComPrecoConferido': proventosConferidos,
      'proventosQueBatemA1pct': proventosBatem,
    },
  };
  File('docs/validacao/b3_contagem_por_data.json')
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(resumo));

  stdout.writeln('== 1. Listadas: FRE em 14/09/2026 contra a contagem oficial ==');
  stdout.writeln('  $listadasBatem de $listadas a 1%');
  for (final d in divergentesListadas.take(15)) {
    stdout.writeln('    $d');
  }
  stdout.writeln('  contagem por data para as coortes: $listadasComContagem '
      'companhias; $listadasEventosLocalizados de $listadasEventos eventos '
      'declarados localizados no preço');
  stdout.writeln('\n== Deslistadas (${ponte.length} companhias da ponte) ==');
  stdout.writeln('  com contagem por data: $comContagem');
  stdout.writeln('  com evento declarado no FRE: $comEventosFre '
      '($eventosFre eventos); com pregão na aprovação: $eventosComPregao; '
      'localizados no preço: $eventosLocalizados; inferidos onde o FRE não '
      'declara: $inferidos');
  for (final n in naoLocalizados) {
    stdout.writeln('    não localizado: $n');
  }
  stdout.writeln('  2. FRE × composição do DFP/ITR: $formularioBate de '
      '$formularioConfere a 2%, contando a escala de mil (decisão 70)');
  stdout.writeln('  3. P/VPA no fim do exercício: $pvpaDentro de $pvpaConfere '
      'entre $_pvpaMinimo e $_pvpaMaximo; mediana '
      '${_mediana(pvpas)?.toStringAsFixed(2)}');
  for (final f in foraDaFaixa.take(12)) {
    stdout.writeln('    $f');
  }
  stdout.writeln('  exercícios com contagem na data e pregão no ano seguinte: '
      '$exerciciosUtilizaveis');
  stdout.writeln('  4. proventos: $companhiasComProventos companhias; '
      '$proventosNoPapel na vida dos papéis; preço com direito contra o '
      'COTAHIST: $proventosBatem de $proventosConferidos a 1%');
  stdout.writeln('\n  gravado data/b3/deslistadas_contagem.json, '
      'data/b3/listadas_contagem.json e docs/validacao/b3_contagem_por_data.json');
}
