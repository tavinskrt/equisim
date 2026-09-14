import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';

/// Prazo das outorgas empacotado com o aplicativo (item A6, decisão 88).
///
/// Gerado por `tool/fre_outorgas.dart` a partir do Formulário de Referência da
/// CVM. **Sem pacote, o repositório é transparente**: sem prazo, a concessão
/// segue com a projeção inteira, e o aviso da avaliação diz o que isso supõe.
class ConcessionTermRepository {
  /// Lê o conteúdo do pacote.
  final Future<String> Function() carregarPacote;

  /// Declara o repositório.
  ConcessionTermRepository({required this.carregarPacote});

  Future<Map<String, ConcessionTerm>>? _prazos;

  Future<Map<String, ConcessionTerm>> _ler() async {
    try {
      final json = jsonDecode(await carregarPacote());
      return json is Map<String, dynamic>
          ? ConcessionTermsCodec.decode(json)
          : const {};
    } on Object {
      return const {};
    }
  }

  /// Fim do contrato de [ticker], ou `null`.
  Future<DateTime?> endFor(Ticker ticker) async =>
      (await (_prazos ??= _ler()))[ticker.value]?.end;
}
