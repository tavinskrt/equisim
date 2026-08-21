import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as legacy;
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'controllers/login_controller.dart';
import 'controllers/theme_controller.dart';
import 'presentation/shared/theme_bridge.dart';
import 'views/login_page.dart';
import 'views/forgot_password_page.dart';
import 'views/sign_up_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // O .env é opcional: a credencial pode vir de --dart-define ou do proxy.
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    debugPrint('ℹ️  .env ausente; usando credencial de compilação ou proxy.');
  }

  // Sem try/catch, uma falha aqui deixa o aplicativo numa tela cinza sem
  // explicação. O erro é levado à interface, que ao menos consegue dizer o
  // que aconteceu.
  Object? initializationError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error, stack) {
    initializationError = error;
    debugPrint('❌ Falha ao inicializar o Firebase: $error\n$stack');
  }

  // Instância única de tema, compartilhada pelas duas árvores de estado.
  // As telas de autenticação continuam lendo por Provider; as telas novas leem
  // por Riverpod. Criar uma instância em cada árvore produziria dois temas
  // divergentes — daí a injeção explícita nas duas.
  final themeController = ThemeController();

  runApp(
    ProviderScope(
      overrides: [
        themeControllerProvider.overrideWithValue(themeController),
      ],
      child: _ThemeSync(
        controller: themeController,
        child: EquisimApp(
          themeController: themeController,
          initializationError: initializationError,
        ),
      ),
    ),
  );
}

/// Espelha o estado do controlador legado no provider observado pelas telas
/// novas, mantendo uma única fonte de verdade para o tema.
class _ThemeSync extends ConsumerStatefulWidget {
  final ThemeController controller;
  final Widget child;

  const _ThemeSync({required this.controller, required this.child});

  @override
  ConsumerState<_ThemeSync> createState() => _ThemeSyncState();
}

class _ThemeSyncState extends ConsumerState<_ThemeSync> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final isLight = widget.controller.isLightMode;
    if (ref.read(isLightModeProvider) != isLight) {
      ref.read(isLightModeProvider.notifier).state = isLight;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class EquisimApp extends StatelessWidget {
  final ThemeController themeController;
  final Object? initializationError;

  const EquisimApp({
    super.key,
    required this.themeController,
    this.initializationError,
  });

  @override
  Widget build(BuildContext context) {
    return legacy.MultiProvider(
      providers: [
        legacy.ChangeNotifierProvider(create: (_) => LoginController()),
        legacy.ChangeNotifierProvider.value(value: themeController),
      ],
      child: MaterialApp(
        title: 'Equisim',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        ),
        home: initializationError == null
            ? const LoginPage()
            : _StartupFailure(error: initializationError!),
        routes: {
          '/forgot-password': (context) => const ForgotPasswordPage(),
          '/sign-up': (context) => const SignUpPage(),
        },
      ),
    );
  }
}

/// Tela de falha na inicialização, no lugar da tela cinza silenciosa.
class _StartupFailure extends StatelessWidget {
  final Object error;

  const _StartupFailure({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40, color: Colors.redAccent),
              const SizedBox(height: 16),
              const Text(
                'Não foi possível iniciar',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'A conexão com os serviços de autenticação falhou. '
                'Verifique sua internet e a configuração do Firebase.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
