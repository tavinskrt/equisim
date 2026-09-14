import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';

/// Registro de emissores da B3 empacotado com o aplicativo (item A3.3).
///
/// Dá à ponte por papel a **contagem oficial de ações** — o árbitro que as duas
/// contagens da fonte de preços não tinham (decisão 83). Gerado por
/// `tool/b3_empacotar.dart` e versionado, como o pacote da CVM.
///
/// **Sem pacote, o repositório é transparente**: sem contagem oficial, a ponte
/// segue a regra da fonte, que é a de antes.
class B3RegistryRepository {
  /// Lê o conteúdo do pacote.
  final Future<String> Function() carregarPacote;

  /// Declara o repositório.
  B3RegistryRepository({required this.carregarPacote});

  Future<Map<String, B3Issuer>>? _emissores;

  Future<Map<String, B3Issuer>> _lidos() => _emissores ??= _ler();

  Future<Map<String, B3Issuer>> _ler() async {
    try {
      final json = jsonDecode(await carregarPacote());
      return json is Map<String, dynamic>
          ? B3RegistryCodec.decodePackage(json)
          : const {};
    } on Object {
      return const {};
    }
  }

  /// Contagem oficial do emissor de [ticker], ou `null`.
  ///
  /// O emissor é a raiz de quatro letras: `PETR3` e `PETR4` são a mesma
  /// companhia, e a contagem é o total das classes.
  Future<OfficialShareCount?> officialSharesFor(Ticker ticker) async {
    final t = ticker.value;
    if (t.length < 4) return null;
    final e = (await _lidos())[t.substring(0, 4)];
    final total = e?.totalShares;
    if (e == null || total == null) return null;
    return OfficialShareCount(total: total, asOf: e.consultedOn);
  }
}
