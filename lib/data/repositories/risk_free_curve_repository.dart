import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';

import '../datasources/remote/tesouro_datasource.dart';

/// A curva de juros da avaliação de hoje (item A2.1, decisão 84).
///
/// **A curva é o padrão do aplicativo**, por decisão do usuário: com ela, a
/// taxa de cada ano da projeção é o forward da curva dos prefixados, e a da
/// perpetuidade é o forward depois da projeção. Sem ela, a cascata recua para
/// os dois pontos do CDI e diz isso no aviso.
///
/// **De onde vem, em ordem:** o Tesouro, lido no dia; e, sem rede ou sem a
/// função na web, o pacote gerado no build. Nos dois casos a regra de data é a
/// de `TreasuryCurve.at`: data-base de até sete dias antes da avaliação, e
/// nunca depois dela. Um pacote velho **não** vira curva — vira recuo
/// declarado.
class RiskFreeCurveRepository {
  /// Fonte do dia.
  final TesouroDatasource remote;

  /// Lê o pacote de cotações do build.
  final Future<String> Function() carregarPacote;

  /// Declara o repositório.
  RiskFreeCurveRepository({required this.remote, required this.carregarPacote});

  Future<List<TreasuryQuote>>? _doDia;
  DateTime? _diaDaBusca;
  Future<List<TreasuryQuote>>? _doPacote;

  /// Curva para [asOf], ou `null` quando nenhuma fonte tem data-base recente.
  ///
  /// A busca do dia vale **pelo dia da avaliação**: o aplicativo aberto de
  /// um dia para o outro busca de novo, em vez de envelhecer a curva até o
  /// recuo.
  Future<YieldCurve?> curveAt(DateTime asOf) async {
    final dia = DateTime.utc(asOf.year, asOf.month, asOf.day);
    if (_diaDaBusca != dia) {
      _diaDaBusca = dia;
      _doDia = null;
    }
    final remota = TreasuryCurve.at(await (_doDia ??= _buscarDoDia()), asOf);
    if (remota != null) return remota;
    return TreasuryCurve.at(await (_doPacote ??= _lerPacote()), asOf);
  }

  Future<List<TreasuryQuote>> _buscarDoDia() async {
    final r = await remote.latest();
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
}
