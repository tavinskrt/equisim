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
  final file = File(shareholderControlAsset);

  test('o pacote existe e está declarado como asset', () {
    expect(file.existsSync(), isTrue,
        reason: 'gerar com `dart run tool/controle_empacotar.dart` e versionar');
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/cvm/'));
  });

  test('o pacote é legível, e as estatais conhecidas estão onde devem', () {
    final parsed = ShareholderControlHistory.decode(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    expect(parsed, isNotNull,
        reason: 'o codec mudou de versão e o pacote não foi regerado');
    ShareholderControl? at(String root, DateTime d) =>
        ShareholderControlHistory.at(parsed!.byIssuer[root]!, d);
    final today = DateTime(2026, 9, 14);
    expect(at('PETR', today), ShareholderControl.state);
    expect(at('BBAS', today), ShareholderControl.state);
    expect(at('ITUB', today), ShareholderControl.private);
    // A Sabesp foi privatizada em 22/07/2024: estatal antes, privada depois.
    expect(at('SBSP', DateTime(2024, 6, 30)), ShareholderControl.state);
    expect(at('SBSP', today), ShareholderControl.private);
  });

  test('o repositório responde pela raiz do código, e sem pacote diz que não',
      () async {
    final package = jsonEncode(ShareholderControlHistory.encode({
      'SBSP': [
        ShareholderControlPeriod(
            since: DateTime(2010), control: ShareholderControl.state),
        ShareholderControlPeriod(
            since: DateTime(2024, 7, 22), control: ShareholderControl.private),
      ],
    }, generatedAt: DateTime(2026, 9, 14)));
    final repo = ShareholderControlRepository(
      loadPackage: () async => package,
      today: () => DateTime(2026, 9, 14),
    );
    expect(await repo.isStateControlled(Ticker.parse('SBSP3')), isFalse);
    expect(
        await repo.isStateControlled(Ticker.parse('SBSP3'),
            asOf: DateTime(2023, 12, 31)),
        isTrue);
    expect(await repo.isStateControlled(Ticker.parse('PETR4')), isFalse);

    final noPackage = ShareholderControlRepository(
      loadPackage: () async => throw const FileSystemException('ausente'),
    );
    expect(await noPackage.isStateControlled(Ticker.parse('PETR4')), isFalse);
  });
}
