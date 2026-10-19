import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';

/// Medianas de múltiplos por grupo de pares, empacotadas com o aplicativo
/// (item B5, decisão 118).
///
/// Dão à avaliação a **segunda leitura** — o preço justo que os pares do ativo
/// implicam, ao lado do fluxo descontado. Geradas por
/// `tool/multiplos_empacotar.dart` e versionadas, como o prior do beta e o
/// registro da B3.
///
/// **Sem pacote, o repositório é transparente**: a avaliação sai como sempre
/// saiu, sem triangulação e sem ressalva inventada. Pacote ilegível tem o mesmo
/// efeito de pacote ausente — a segunda leitura é acréscimo, e a falta dela não
/// pode derrubar a primeira.
class PeerMultiplesRepository {
  /// Lê o conteúdo do pacote.
  final Future<String> Function() loadPackage;

  /// Declara o repositório.
  PeerMultiplesRepository({required this.loadPackage});

  Future<Map<String, PeerMultipleSet>>? _parsed;

  Future<Map<String, PeerMultipleSet>> _medians() => _parsed ??= _read();

  Future<Map<String, PeerMultipleSet>> _read() async {
    try {
      final json = jsonDecode(await loadPackage());
      return json is Map<String, dynamic>
          ? PeerMultipleCodec.decode(json)
          : const {};
    } on Object {
      return const {};
    }
  }

  /// As medianas que valem para [ticker], ou `null`.
  ///
  /// A chave é o **ticker inteiro**, e não a raiz do emissor: PETR3 e PETR4
  /// negociam múltiplos diferentes, e é o múltiplo negociado que entra na
  /// mediana do grupo.
  Future<PeerMultipleSet?> forTicker(Ticker ticker) async =>
      (await _medians())[ticker.value];
}
