import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';

/// Faixa calibrada empacotada com o aplicativo (item C2, decisão 92).
///
/// Gerada por `tool/cobertura_banda.py` a partir das coortes da validação.
/// **Sem pacote, o repositório é transparente**: a tela de avaliação não mostra
/// faixa calibrada, e a banda de cenários continua sendo o que ela é — a
/// sensibilidade às premissas.
class CalibratedBandRepository {
  /// Lê o conteúdo do pacote.
  final Future<String> Function() loadPackage;

  /// Declara o repositório.
  CalibratedBandRepository({required this.loadPackage});

  Future<List<CalibratedBandTable>>? _bands;

  Future<List<CalibratedBandTable>> _read() async {
    try {
      final json = jsonDecode(await loadPackage());
      return json is Map<String, dynamic>
          ? CalibratedBandCodec.decode(json)
          : const [];
    } on Object {
      return const [];
    }
  }

  /// Todas as faixas do pacote, ou vazio.
  Future<List<CalibratedBandTable>> tables() => _bands ??= _read();
}
