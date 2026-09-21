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
  final Future<String> Function() carregarPacote;

  /// Declara o repositório.
  PeerMultiplesRepository({required this.carregarPacote});

  Future<Map<String, PeerMultipleSet>>? _lido;

  Future<Map<String, PeerMultipleSet>> _medianas() => _lido ??= _ler();

  Future<Map<String, PeerMultipleSet>> _ler() async {
    try {
      final json = jsonDecode(await carregarPacote());
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
      (await _medianas())[ticker.value];

  /// Data em que as medianas foram apuradas, ou `null` sem pacote.
  Future<DateTime?> get asOf async {
    final m = await _medianas();
    return m.isEmpty ? null : m.values.first.asOf;
  }
}
