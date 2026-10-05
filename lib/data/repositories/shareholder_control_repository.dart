import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';

/// A espécie do controle acionário, empacotada com o aplicativo (item B46).
///
/// Vem do Formulário Cadastral da CVM, gerada por `tool/controle_empacotar.dart`
/// e versionada em `assets/cvm/controle.json`, pela raiz do código de
/// negociação — a mesma chave do registro da B3. A avaliação a usa só para a
/// ressalva de controle estatal: o preço justo não muda.
///
/// **Sem pacote, o repositório é transparente**: sem a espécie, a avaliação
/// sai sem a ressalva, como antes dela.
class ShareholderControlRepository {
  /// Lê o conteúdo do pacote.
  final Future<String> Function() carregarPacote;

  /// Data da avaliação. **Recebida por função**, e não lida do relógio no
  /// ponto de uso — a mesma convenção de `UnitCompositionRepository`.
  final DateTime Function() hoje;

  /// Declara o repositório.
  ShareholderControlRepository({
    required this.carregarPacote,
    DateTime Function()? hoje,
  }) : hoje = hoje ?? DateTime.now;

  Future<Map<String, List<ShareholderControlPeriod>>>? _emissores;

  Future<Map<String, List<ShareholderControlPeriod>>> _ler() async {
    try {
      final json = jsonDecode(await carregarPacote());
      return json is Map<String, dynamic>
          ? ShareholderControlHistory.decode(json)?.porEmissor ?? const {}
          : const {};
    } on Object {
      return const {};
    }
  }

  /// `true` quando o emissor de [ticker] é de controle estatal em [asOf] —
  /// ou na data de [hoje], sem ela.
  Future<bool> isStateControlled(Ticker ticker, {DateTime? asOf}) async {
    final raiz = ticker.value.length >= 4
        ? ticker.value.substring(0, 4)
        : ticker.value;
    final periodos = (await (_emissores ??= _ler()))[raiz];
    if (periodos == null) return false;
    return ShareholderControlHistory.at(periodos, asOf ?? hoje()) ==
        ShareholderControl.state;
  }
}
