import 'dart:convert';
import 'dart:io';

import 'package:equisim/data/repositories/shareholder_control_repository.dart';
import 'package:equisim/di/providers.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// O controle acionário versionado é o que o build leva (item B46).
///
/// Ele só acrescenta a ressalva de controle estatal, e por isso a ausência não
/// muda preço; mas um build sem ele deixaria de declarar o que a medição
/// mandou declarar, e isso reprova a suíte.
void main() {
  final arquivo = File(shareholderControlAsset);

  test('o pacote existe e está declarado como asset', () {
    expect(arquivo.existsSync(), isTrue,
        reason: 'gerar com `dart run tool/controle_empacotar.dart` e versionar');
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/cvm/'));
  });

  test('o pacote é legível, e as estatais conhecidas estão onde devem', () {
    final lido = ShareholderControlHistory.decode(
        jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>);
    expect(lido, isNotNull,
        reason: 'o codec mudou de versão e o pacote não foi regerado');
    ShareholderControl? em(String raiz, DateTime d) =>
        ShareholderControlHistory.at(lido!.porEmissor[raiz]!, d);
    final hoje = DateTime(2026, 9, 14);
    expect(em('PETR', hoje), ShareholderControl.state);
    expect(em('BBAS', hoje), ShareholderControl.state);
    expect(em('ITUB', hoje), ShareholderControl.private);
    // A Sabesp foi privatizada em 22/07/2024: estatal antes, privada depois.
    expect(em('SBSP', DateTime(2024, 6, 30)), ShareholderControl.state);
    expect(em('SBSP', hoje), ShareholderControl.private);
  });

  test('o repositório responde pela raiz do código, e sem pacote diz que não',
      () async {
    final pacote = jsonEncode(ShareholderControlHistory.encode({
      'SBSP': [
        ShareholderControlPeriod(
            since: DateTime(2010), control: ShareholderControl.state),
        ShareholderControlPeriod(
            since: DateTime(2024, 7, 22), control: ShareholderControl.private),
      ],
    }, geradoEm: DateTime(2026, 9, 14)));
    final repo = ShareholderControlRepository(
      carregarPacote: () async => pacote,
      hoje: () => DateTime(2026, 9, 14),
    );
    expect(await repo.isStateControlled(Ticker.parse('SBSP3')), isFalse);
    expect(
        await repo.isStateControlled(Ticker.parse('SBSP3'),
            asOf: DateTime(2023, 12, 31)),
        isTrue);
    expect(await repo.isStateControlled(Ticker.parse('PETR4')), isFalse);

    final semPacote = ShareholderControlRepository(
      carregarPacote: () async => throw const FileSystemException('ausente'),
    );
    expect(await semPacote.isStateControlled(Ticker.parse('PETR4')), isFalse);
  });
}
