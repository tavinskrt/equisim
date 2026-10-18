import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';

import '../datasources/remote/tesouro_datasource.dart';

/// O que a avaliação recebe da curva: ela, ou a razão de não haver.
///
/// [note] só existe quando [curve] é `null`: com curva, a própria avaliação já
/// declara a data-base que usou.
typedef CurveReading = ({YieldCurve? curve, String? note});

/// A curva de juros da avaliação de hoje (item A2.1, decisões 84 e 86).
///
/// **A curva é o padrão do aplicativo**, por decisão do usuário: com ela, a
/// taxa de cada ano da projeção é o forward da curva dos prefixados, e a da
/// perpetuidade é o forward depois da projeção. Sem ela, a cascata recua para
/// os dois pontos do CDI e diz isso no aviso.
///
/// **De onde vem, em ordem:** no nativo, o Tesouro lido no dia; e, sem ele, o
/// pacote gerado no build. **Na web, só o pacote** — o navegador não lê o
/// arquivo do Tesouro. Nos dois casos a regra de data é a de
/// `TreasuryCurve.at`: data-base de até sete dias antes da avaliação, e nunca
/// depois dela. Um pacote velho **não** vira curva — vira recuo declarado.
class RiskFreeCurveRepository {
  /// Fonte do dia, ou `null` onde ela não alcança o Tesouro: a web.
  final TreasuryDatasource? remote;

  /// Lê o pacote de cotações do build.
  final Future<String> Function() loadPackage;

  /// Declara o repositório.
  RiskFreeCurveRepository({required this.remote, required this.loadPackage});

  Future<List<TreasuryQuote>>? _dailyQuotes;
  DateTime? _fetchDay;
  Future<List<TreasuryQuote>>? _packagedQuotes;

  /// Curva para [asOf] e, quando não há, a ressalva que diz por quê.
  ///
  /// A busca do dia vale **pelo dia da avaliação**: o aplicativo aberto de
  /// um dia para o outro busca de novo, em vez de envelhecer a curva até o
  /// recuo.
  Future<CurveReading> readAt(DateTime asOf) async {
    final source = remote;
    if (source != null) {
      final day = DateTime.utc(asOf.year, asOf.month, asOf.day);
      if (_fetchDay != day) {
        _fetchDay = day;
        _dailyQuotes = null;
      }
      final remoteReading =
          TreasuryCurve.at(await (_dailyQuotes ??= _fetchToday(source)), asOf);
      if (remoteReading != null) return (curve: remoteReading, note: null);
    }
    final package = await (_packagedQuotes ??= _readPackage());
    final packagedQuotes = TreasuryCurve.at(package, asOf);
    if (packagedQuotes != null) return (curve: packagedQuotes, note: null);
    return (curve: null, note: _caveat(package, noDailySource: source == null));
  }

  Future<List<TreasuryQuote>> _fetchToday(TreasuryDatasource source) async {
    final r = await source.latest();
    // Falha da busca não é guardada para a sessão inteira: a próxima avaliação
    // tenta de novo. Só o sucesso fica.
    if (r.isErr) {
      _dailyQuotes = null;
      return const [];
    }
    return r.unwrap();
  }

  Future<List<TreasuryQuote>> _readPackage() async {
    try {
      final json = jsonDecode(await loadPackage());
      return json is Map<String, dynamic>
          ? TreasuryQuotesCodec.decode(json)
          : const [];
    } on Object {
      return const [];
    }
  }

  static String _caveat(List<TreasuryQuote> package,
      {required bool noDailySource}) {
    final origin = noDailySource
        ? 'Na web, a curva do Tesouro vem só do pacote do build'
        : 'O Tesouro não trouxe hoje curva de até '
            '${TreasuryCurve.fallbackDays} dias, e o recuo é o pacote do build';
    final DateTime? latest = package.isEmpty
        ? null
        : package
            .map((q) => q.baseDate)
            .reduce((a, b) => a.isAfter(b) ? a : b);
    final status = latest == null
        ? 'que este build não trouxe ou não pôde ser lido'
        : 'cuja data-base mais recente, ${_fmt(latest)}, está fora dos '
            '${TreasuryCurve.fallbackDays} dias que a curva aceita';
    final remedy = noDailySource
        ? ' Um build novo, com o pacote regerado, traz a curva de volta.'
        : '';
    return '$origin, $status. A taxa livre de risco recuou para os dois '
        'pontos do CDI.$remedy';
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
