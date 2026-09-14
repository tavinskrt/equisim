import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';

/// Proventos da B3 empacotados com o aplicativo (item A4, decisão 89).
///
/// Dão ao beta o **retorno total** do ativo. Gerado por
/// `tool/b3_proventos_empacotar.dart`. **Sem pacote, o repositório é
/// transparente**: sem proventos, o beta sai do fechamento, que é o de antes.
class CashDividendsRepository {
  /// Lê o conteúdo do pacote.
  final Future<String> Function() carregarPacote;

  /// Declara o repositório.
  CashDividendsRepository({required this.carregarPacote});

  Future<Map<String, List<CashDividend>>>? _proventos;

  Future<Map<String, List<CashDividend>>> _ler() async {
    try {
      final json = jsonDecode(await carregarPacote());
      return json is Map<String, dynamic>
          ? CashDividendsCodec.decode(json)
          : const {};
    } on Object {
      return const {};
    }
  }

  /// Proventos da classe de [ticker], em ordem de data ex.
  Future<List<CashDividend>> dividendsFor(Ticker ticker) async =>
      CashDividendsCodec.forTicker(await (_proventos ??= _ler()), ticker.value);
}
