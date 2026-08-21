import 'dart:async';

import 'package:equisim/di/providers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usuário de mentira: só o `uid` é consultado.
class _FakeUser implements User {
  @override
  final String uid;

  _FakeUser(this.uid);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// `FirebaseAuth` de mentira, com a sessão corrente separada do fluxo.
///
/// A separação é o ponto do teste: no aplicativo real `authStateChanges()` só
/// emite no microtask seguinte à assinatura, enquanto `currentUser` já
/// responde. O controlador aqui permite reproduzir exatamente essa janela.
class _FakeAuth implements FirebaseAuth {
  final StreamController<User?> controller;

  @override
  User? currentUser;

  _FakeAuth({required this.controller, this.currentUser});

  @override
  Stream<User?> authStateChanges() => controller.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('currentUserIdProvider', () {
    late StreamController<User?> controller;

    setUp(() => controller = StreamController<User?>.broadcast());
    tearDown(() => controller.close());

    ProviderContainer containerFor(_FakeAuth auth) {
      final container = ProviderContainer(overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('identifica a sessão antes do fluxo emitir', () {
      // Regressão: era aqui que "salvar estudo" concluía não haver ninguém
      // logado. O `StreamProvider` recém-criado está em `AsyncLoading`, e a
      // leitura caía para `null` mesmo com a sessão ativa.
      final auth = _FakeAuth(
        controller: controller,
        currentUser: _FakeUser('usuario-1'),
      );
      final container = containerFor(auth);

      expect(container.read(currentUserIdProvider), 'usuario-1');
    });

    test('sem sessão continua devolvendo nulo', () {
      final container = containerFor(_FakeAuth(controller: controller));
      expect(container.read(currentUserIdProvider), isNull);
    });

    test('o fluxo manda depois de emitir — logout derruba a sessão', () async {
      final auth = _FakeAuth(
        controller: controller,
        currentUser: _FakeUser('usuario-1'),
      );
      final container = containerFor(auth);
      // Mantém o provider vivo para que o fluxo continue assinado.
      final subscription = container.listen(
        currentUserIdProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      controller.add(_FakeUser('usuario-1'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(currentUserIdProvider), 'usuario-1');

      // O `signOut` real limpa `currentUser` e emite; aqui, só a emissão,
      // para provar que é o fluxo que decide depois de haver valor.
      controller.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(currentUserIdProvider), isNull);
    });
  });
}
