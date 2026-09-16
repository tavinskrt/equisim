import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';

/// Leitura da habilidade do potencial empacotada com o aplicativo (item B1.0).
///
/// Gerada por `tool/regressao_condicional.dart --trimestral` a partir das
/// coortes da validação. **Sem pacote, a leitura é `null`**, e a tela de metas
/// diz que a habilidade não foi medida: a ausência não pode esconder a
/// ressalva.
class SkillReadingRepository {
  /// Lê o conteúdo do pacote.
  final Future<String> Function() carregarPacote;

  /// Declara o repositório.
  SkillReadingRepository({required this.carregarPacote});

  Future<SkillReading?>? _leitura;

  Future<SkillReading?> _ler() async {
    try {
      final json = jsonDecode(await carregarPacote());
      return json is Map<String, dynamic>
          ? SkillReadingCodec.decode(json)
          : null;
    } on Object {
      return null;
    }
  }

  /// A leitura do pacote, ou `null`.
  Future<SkillReading?> reading() => _leitura ??= _ler();
}
