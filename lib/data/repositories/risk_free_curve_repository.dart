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
  final TesouroDatasource? remote;

  /// Lê o pacote de cotações do build.
  final Future<String> Function() carregarPacote;

  /// Declara o repositório.
  RiskFreeCurveRepository({required this.remote, required this.carregarPacote});

  Future<List<TreasuryQuote>>? _doDia;
  DateTime? _diaDaBusca;
  Future<List<TreasuryQuote>>? _doPacote;

  /// Curva para [asOf], ou `null` quando nenhuma fonte tem data-base recente.
  Future<YieldCurve?> curveAt(DateTime asOf) async =>
      (await readAt(asOf)).curve;

  /// Curva para [asOf] e, quando não há, a ressalva que diz por quê.
  ///
  /// A busca do dia vale **pelo dia da avaliação**: o aplicativo aberto de
  /// um dia para o outro busca de novo, em vez de envelhecer a curva até o
  /// recuo.
  Future<CurveReading> readAt(DateTime asOf) async {
    final fonte = remote;
    if (fonte != null) {
      final dia = DateTime.utc(asOf.year, asOf.month, asOf.day);
      if (_diaDaBusca != dia) {
        _diaDaBusca = dia;
        _doDia = null;
      }
      final remota =
          TreasuryCurve.at(await (_doDia ??= _buscarDoDia(fonte)), asOf);
      if (remota != null) return (curve: remota, note: null);
    }
    final pacote = await (_doPacote ??= _lerPacote());
    final doPacote = TreasuryCurve.at(pacote, asOf);
    if (doPacote != null) return (curve: doPacote, note: null);
    return (curve: null, note: _ressalva(pacote, semFonteDoDia: fonte == null));
  }

  Future<List<TreasuryQuote>> _buscarDoDia(TesouroDatasource fonte) async {
    final r = await fonte.latest();
    // Falha da busca não é guardada para a sessão inteira: a próxima avaliação
    // tenta de novo. Só o sucesso fica.
    if (r.isErr) {
      _doDia = null;
      return const [];
    }
    return r.unwrap();
  }

  Future<List<TreasuryQuote>> _lerPacote() async {
    try {
      final json = jsonDecode(await carregarPacote());
      return json is Map<String, dynamic>
          ? TreasuryQuotesCodec.decode(json)
          : const [];
    } on Object {
      return const [];
    }
  }

  static String _ressalva(List<TreasuryQuote> pacote,
      {required bool semFonteDoDia}) {
    final origem = semFonteDoDia
        ? 'Na web, a curva do Tesouro vem só do pacote do build'
        : 'O Tesouro não trouxe hoje curva de até '
            '${TreasuryCurve.diasDeRecuo} dias, e o recuo é o pacote do build';
    final DateTime? maisRecente = pacote.isEmpty
        ? null
        : pacote
            .map((q) => q.baseDate)
            .reduce((a, b) => a.isAfter(b) ? a : b);
    final estado = maisRecente == null
        ? 'que este build não trouxe ou não pôde ser lido'
        : 'cuja data-base mais recente, ${_fmt(maisRecente)}, está fora dos '
            '${TreasuryCurve.diasDeRecuo} dias que a curva aceita';
    final remedio = semFonteDoDia
        ? ' Um build novo, com o pacote regerado, traz a curva de volta.'
        : '';
    return '$origem, $estado. A taxa livre de risco recuou para os dois '
        'pontos do CDI.$remedio';
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
