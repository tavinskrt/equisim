import 'dart:convert';
import 'dart:io';

import 'package:equisim/data/repositories/skill_reading_repository.dart';
import 'package:equisim/di/providers.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A leitura da habilidade é o que a tela de metas cita na ressalva do prêmio
/// (item B1.0). Pacote ausente ou divergente da medição reprova a suíte: no
/// aplicativo a ausência vira a ressalva de "não medida", e o descuido que
/// importa pegar é o pacote dizer outra coisa que a medição.
void main() {
  final arquivo = File(skillReadingAsset);

  Map<String, dynamic> m(Object? v) => v as Map<String, dynamic>;

  test('existe, está declarado e é legível', () {
    expect(arquivo.existsSync(), isTrue,
        reason: 'gerar com `dart run tool/regressao_condicional.dart '
            '--pacote-habilidade` e versionar');
    expect(File('pubspec.yaml').readAsStringSync(),
        contains('- assets/validacao/'));
    expect(SkillReadingCodec.decode(m(jsonDecode(arquivo.readAsStringSync()))),
        isNotNull);
  });

  test('os números e o veredito são os da medição trimestral com deslistadas',
      () {
    final leitura =
        SkillReadingCodec.decode(m(jsonDecode(arquivo.readAsStringSync())))!;
    final medicao = m(jsonDecode(
        File('docs/validacao/habilidade_trimestral.json').readAsStringSync()));
    final fm = m(m(m(m(medicao['h36'])['trimestral'])['comDeslistadas'])[
        'famaMacBeth']);
    final dado = m(fm['potencialDadoBm']);

    expect(leitura.months, 36);
    expect(leitura.cohorts, dado['coortes']);
    expect(leitura.conditionalCoefficient,
        closeTo((dado['media'] as num).toDouble(), 1e-12));
    expect(leitura.overlapT,
        closeTo((dado['tSobreposicao'] as num).toDouble(), 1e-12));
    expect(leitura.overlapCritical,
        closeTo((dado['criticoSobreposicao'] as num).toDouble(), 1e-12));
    expect(leitura.neweyWestT,
        closeTo((dado['tNeweyWest'] as num).toDouble(), 1e-12));
    expect(leitura.potentialIc,
        closeTo((m(fm['icPotencial'])['media'] as num).toDouble(), 1e-12));
    expect(leitura.bookToMarketIc,
        closeTo((m(fm['icBookToMarket'])['media'] as num).toDouble(), 1e-12));
    // O critério mora no núcleo, e a ferramenta o aplica por conta própria: os
    // dois têm de concordar.
    expect(leitura.demonstrated, dado['passaR3']);
  });

  test('sem pacote, ou com lixo, a leitura é nula', () async {
    final sem = SkillReadingRepository(
        carregarPacote: () async => throw const FileSystemException('sem'));
    expect(await sem.reading(), isNull);
    final lixo = SkillReadingRepository(carregarPacote: () async => '[1, 2]');
    expect(await lixo.reading(), isNull);
  });
}
