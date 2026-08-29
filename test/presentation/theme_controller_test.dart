import 'package:equisim/controllers/theme_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ThemeController.load', () {
    test('devolve a preferencia salva ja resolvida', () async {
      SharedPreferences.setMockInitialValues({ThemeController.prefsKey: true});

      final controller = await ThemeController.load();

      // O ponto do teste nao e o valor em si -- e o momento. Aqui ele ja esta
      // correto, sem nenhum quadro intermediario. A versao anterior lia a
      // preferencia de dentro do construtor, sem aguardar, entao o
      // controlador nascia no escuro e trocava depois: para quem usa o tema
      // claro, um flash escuro em toda abertura.
      expect(controller.isLightMode, isTrue);
    });

    test('cai no escuro quando nao ha preferencia salva', () async {
      SharedPreferences.setMockInitialValues({});

      final controller = await ThemeController.load();

      expect(controller.isLightMode, isFalse);
    });

    test('nao notifica ouvintes durante a carga', () async {
      SharedPreferences.setMockInitialValues({ThemeController.prefsKey: true});

      final controller = await ThemeController.load();

      var notifications = 0;
      controller.addListener(() => notifications++);

      // Nenhuma notificacao pendente do arranque: o valor ja chegou pronto.
      // Se `load` voltasse a notificar apos a construcao, a arvore
      // reconstruiria uma vez sem necessidade -- e o flash estaria de volta.
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 0);

      addTearDown(controller.dispose);
    });
  });
}
