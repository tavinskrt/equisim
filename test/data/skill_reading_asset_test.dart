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
  final file = File(skillReadingAsset);

  Map<String, dynamic> m(Object? v) => v as Map<String, dynamic>;

  test('existe, está declarado e é legível', () {
    expect(file.existsSync(), isTrue,
        reason: 'gerar com `dart run tool/regressao_condicional.dart '
            '--pacote-habilidade` e versionar');
    expect(File('pubspec.yaml').readAsStringSync(),
        contains('- assets/validacao/'));
    expect(SkillReadingCodec.decode(m(jsonDecode(file.readAsStringSync()))),
        isNotNull);
  });

  test('os números, o veredito e o prêmio são os da medição trimestral com '
      'deslistadas', () {
    final reading =
        SkillReadingCodec.decode(m(jsonDecode(file.readAsStringSync())))!;
    final measurement = m(jsonDecode(
        File('docs/validacao/habilidade_trimestral.json').readAsStringSync()));
    final fm = m(m(m(m(measurement['h36'])['trimestral'])['comDeslistadas'])[
        'famaMacBeth']);
    final datum = m(fm['potencialDadoBm']);
    double number(Map<String, dynamic> x, String k) => (x[k] as num).toDouble();

    expect(reading.months, 36);
    expect(reading.cohorts, datum['coortes']);
    expect(reading.conditionalCoefficient, closeTo(number(datum, 'media'), 1e-12));
    expect(reading.overlapT, closeTo(number(datum, 'tSobreposicao'), 1e-12));
    expect(reading.overlapCritical,
        closeTo(number(datum, 'criticoSobreposicao'), 1e-12));
    expect(reading.neweyWestT, closeTo(number(datum, 'tNeweyWest'), 1e-12));
    // O critério mora no núcleo, e a ferramenta o aplica por conta própria: os
    // dois têm de concordar.
    expect(reading.demonstrated, datum['passaR3']);

    // As três ordenações lado a lado (item B1), cada uma contra a medição.
    const pairs = [
      (TransversalOrdering.composite, 'icComposto'),
      (TransversalOrdering.bookToMarket, 'icBookToMarket'),
      (TransversalOrdering.potential, 'icPotencial'),
    ];
    for (final (ordering, key) in pairs) {
      final measured = m(fm[key]);
      final readOrdering = reading.orderings[ordering]!;
      expect(readOrdering.ic, closeTo(number(measured, 'media'), 1e-12), reason: key);
      expect(readOrdering.overlapT, closeTo(number(measured, 'tSobreposicao'), 1e-12),
          reason: key);
      expect(readOrdering.demonstrated, measured['passaR3'], reason: key);
    }
    // A regra do prêmio é a primeira que passa, na ordem fixada antes de medir.
    final first = pairs
        .where((e) => m(fm[e.$2])['passaR3'] == true)
        .map((e) => e.$1)
        .firstOrNull;
    expect(reading.premiumOrdering, first);
  });

  test('sem pacote, ou com lixo, a leitura é nula', () async {
    final without = SkillReadingRepository(
        loadPackage: () async => throw const FileSystemException('sem'));
    expect(await without.reading(), isNull);
    final garbage = SkillReadingRepository(loadPackage: () async => '[1, 2]');
    expect(await garbage.reading(), isNull);
  });
}
