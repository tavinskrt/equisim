import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';

/// Eventos de capital empacotados com o aplicativo (itens B28 e B29).
///
/// Gerado por `tool/capital_empacotar.dart` a partir do Formulário de
/// Referência da CVM, do registro da B3 e do COTAHIST. Duas listas por ativo:
/// as emissões de ações, que a cascata soma ao patrimônio quando o valor é
/// declarado e só avisa quando não é, e os eventos de ações, com que o preparo
/// completa o ajuste que a fonte de preços deixou de fazer.
///
/// **Sem pacote, o repositório é transparente**: sem emissão, o patrimônio é o
/// do balanço, e sem evento a série da fonte segue como veio — que é o
/// comportamento anterior.
class CapitalEventsRepository {
  /// Lê o conteúdo do pacote.
  final Future<String> Function() carregarPacote;

  /// Declara o repositório.
  CapitalEventsRepository({required this.carregarPacote});

  Future<Map<String, CapitalEvents>>? _pacote;

  Future<Map<String, CapitalEvents>> _ler() async {
    try {
      final json = jsonDecode(await carregarPacote());
      return json is Map<String, dynamic>
          ? CapitalEventsCodec.decodePackage(json)
          : const {};
    } on Object {
      return const {};
    }
  }

  /// Emissões e eventos de ações de [ticker]; vazio sem entrada no pacote.
  Future<CapitalEvents> eventsFor(Ticker ticker) async =>
      (await (_pacote ??= _ler()))[ticker.value] ?? const CapitalEvents();
}
