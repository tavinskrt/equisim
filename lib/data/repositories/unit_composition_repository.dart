import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';

/// Composição declarada das units, empacotada com o aplicativo (item B16).
///
/// A razão de unidade era **inferida** do valor de mercado, e só acerta quando
/// ordinária e preferencial valem o mesmo: nas coortes ela erra 79 de 220
/// observações de unit. A composição que a companhia declara no quadro de
/// valores mobiliários da FCA é fonte primária e datada. Gerada por
/// `tool/unit_empacotar.dart` e versionada, como o pacote da CVM.
///
/// **Sem pacote, o repositório é transparente**: sem composição declarada, a
/// cascata volta a inferir a razão e passa a dizer que a inferiu.
class UnitCompositionRepository {
  /// Lê o conteúdo do pacote.
  final Future<String> Function() loadPackage;

  /// Data da avaliação. **Recebida por função**, e não lida do relógio no
  /// ponto de uso: a composição vigente depende da data, e o núcleo recebe a
  /// data pronta — é a mesma convenção de `CvmFundamentalsRepository`.
  final DateTime Function() today;

  /// Declara o repositório.
  UnitCompositionRepository({
    required this.loadPackage,
    DateTime Function()? today,
  }) : today = today ?? DateTime.now;

  Future<Map<String, List<UnitComposition>>>? _units;

  Future<Map<String, List<UnitComposition>>> _read() async {
    try {
      final json = jsonDecode(await loadPackage());
      return json is Map<String, dynamic>
          ? UnitCompositionCodec.decodePackage(json)
          : const {};
    } on Object {
      return const {};
    }
  }

  /// Ações na unit de [ticker] declaradas até [asOf], ou `null`.
  ///
  /// Formulário posterior à data não entra: numa avaliação datada, a
  /// composição de um ano futuro seria conhecimento futuro. Sem [asOf], vale a
  /// data de [today].
  Future<int?> sharesPerUnitFor(Ticker ticker, {DateTime? asOf}) async {
    final declared = (await (_units ??= _read()))[ticker.value];
    if (declared == null) return null;
    return UnitCompositionCodec.at(declared, asOf ?? today())?.shares;
  }
}
