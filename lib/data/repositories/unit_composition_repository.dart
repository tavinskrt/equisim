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
  final Future<String> Function() carregarPacote;

  /// Data da avaliação. **Recebida por função**, e não lida do relógio no
  /// ponto de uso: a composição vigente depende da data, e o núcleo recebe a
  /// data pronta — é a mesma convenção de `CvmFundamentalsRepository`.
  final DateTime Function() hoje;

  /// Declara o repositório.
  UnitCompositionRepository({
    required this.carregarPacote,
    DateTime Function()? hoje,
  }) : hoje = hoje ?? DateTime.now;

  Future<Map<String, List<UnitComposition>>>? _units;

  Future<Map<String, List<UnitComposition>>> _ler() async {
    try {
      final json = jsonDecode(await carregarPacote());
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
  /// data de [hoje].
  Future<int?> sharesPerUnitFor(Ticker ticker, {DateTime? asOf}) async {
    final declaradas = (await (_units ??= _ler()))[ticker.value];
    if (declaradas == null) return null;
    return UnitCompositionCodec.at(declaradas, asOf ?? hoje())?.shares;
  }
}
