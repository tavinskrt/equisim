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

  test('os números, o veredito e o prêmio são os da medição trimestral com '
      'deslistadas', () {
    final leitura =
        SkillReadingCodec.decode(m(jsonDecode(arquivo.readAsStringSync())))!;
    final medicao = m(jsonDecode(
        File('docs/validacao/habilidade_trimestral.json').readAsStringSync()));
    final fm = m(m(m(m(medicao['h36'])['trimestral'])['comDeslistadas'])[
        'famaMacBeth']);
    final dado = m(fm['potencialDadoBm']);
    double numero(Map<String, dynamic> x, String k) => (x[k] as num).toDouble();

    expect(leitura.months, 36);
    expect(leitura.cohorts, dado['coortes']);
    expect(leitura.conditionalCoefficient, closeTo(numero(dado, 'media'), 1e-12));
    expect(leitura.overlapT, closeTo(numero(dado, 'tSobreposicao'), 1e-12));
    expect(leitura.overlapCritical,
        closeTo(numero(dado, 'criticoSobreposicao'), 1e-12));
    expect(leitura.neweyWestT, closeTo(numero(dado, 'tNeweyWest'), 1e-12));
    // O critério mora no núcleo, e a ferramenta o aplica por conta própria: os
    // dois têm de concordar.
    expect(leitura.demonstrated, dado['passaR3']);

    // As três ordenações lado a lado (item B1), cada uma contra a medição.
    const pares = [
      (TransversalOrdering.composite, 'icComposto'),
      (TransversalOrdering.bookToMarket, 'icBookToMarket'),
      (TransversalOrdering.potential, 'icPotencial'),
    ];
    for (final (ordenacao, chave) in pares) {
      final medida = m(fm[chave]);
      final lida = leitura.orderings[ordenacao]!;
      expect(lida.ic, closeTo(numero(medida, 'media'), 1e-12), reason: chave);
      expect(lida.overlapT, closeTo(numero(medida, 'tSobreposicao'), 1e-12),
          reason: chave);
      expect(lida.demonstrated, medida['passaR3'], reason: chave);
    }
    // A regra do prêmio é a primeira que passa, na ordem fixada antes de medir.
    final primeira = pares
        .where((e) => m(fm[e.$2])['passaR3'] == true)
        .map((e) => e.$1)
        .firstOrNull;
    expect(leitura.premiumOrdering, primeira);
  });

  test('sem pacote, ou com lixo, a leitura é nula', () async {
    final sem = SkillReadingRepository(
        carregarPacote: () async => throw const FileSystemException('sem'));
    expect(await sem.reading(), isNull);
    final lixo = SkillReadingRepository(carregarPacote: () async => '[1, 2]');
    expect(await lixo.reading(), isNull);
  });
}
