import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Como o cliente alcança a brapi.
enum BrapiMode {
  /// Chamada direta com o token embarcado no binário.
  ///
  /// O token é extraível por engenharia reversa — `--dart-define` tira o
  /// segredo do controle de versão e do bundle web, mas **não** o protege de
  /// quem tem o binário. Aceitável em desenvolvimento; para distribuição, use
  /// [BrapiMode.proxied].
  direct,

  /// Chamada via função de nuvem que injeta o token no servidor.
  ///
  /// Única forma real de proteger a credencial, e resolve o CORS no alvo web
  /// sem entregar o header `Authorization` a um proxy público de terceiro.
  proxied,
}

/// Configuração de acesso às APIs externas.
class ApiConfig {
  final BrapiMode mode;
  final String brapiBaseUrl;
  final String? brapiToken;
  final String bcbBaseUrl;

  const ApiConfig({
    required this.mode,
    required this.brapiBaseUrl,
    required this.bcbBaseUrl,
    this.brapiToken,
  });

  // --- Valores de compilação (`--dart-define-from-file=config/local.json`) ---
  static const String _definedToken = String.fromEnvironment('BRAPI_TOKEN');
  static const String _definedProxy = String.fromEnvironment('BRAPI_PROXY_URL');
  static const String _definedBase = String.fromEnvironment(
    'BRAPI_BASE_URL',
    defaultValue: 'https://brapi.dev/api',
  );

  /// A API SGS do Banco Central é aberta: sem token, sem cadastro.
  static const String bcbDefaultBaseUrl =
      'https://api.bcb.gov.br/dados/serie';

  /// Resolve a configuração na seguinte ordem de precedência:
  ///
  /// 1. `BRAPI_PROXY_URL` definido em compilação → modo proxy, sem token;
  /// 2. `BRAPI_TOKEN` definido em compilação → modo direto;
  /// 3. `.env` carregado como asset → modo direto, **com aviso**.
  ///
  /// O passo 3 existe para não quebrar o fluxo de desenvolvimento durante a
  /// transição, mas emite alerta: o `.env` declarado como asset viaja dentro
  /// do bundle e, no alvo web, é servido publicamente.
  factory ApiConfig.resolve() {
    if (_definedProxy.isNotEmpty) {
      return ApiConfig(
        mode: BrapiMode.proxied,
        brapiBaseUrl: _definedProxy,
        bcbBaseUrl: bcbDefaultBaseUrl,
      );
    }

    if (_definedToken.isNotEmpty) {
      return const ApiConfig(
        mode: BrapiMode.direct,
        brapiBaseUrl: _definedBase,
        brapiToken: _definedToken,
        bcbBaseUrl: bcbDefaultBaseUrl,
      );
    }

    final envToken = _fromDotenv('BRAPI_TOKEN');
    if (envToken != null) {
      debugPrint(
        '⚠️  Token da brapi lido de .env (asset embarcado no bundle). '
        'Para build de distribuição use --dart-define-from-file=config/local.json '
        'ou, preferencialmente, configure BRAPI_PROXY_URL.',
      );
      return ApiConfig(
        mode: BrapiMode.direct,
        brapiBaseUrl: _fromDotenv('BRAPI_BASE_URL') ?? _definedBase,
        brapiToken: envToken,
        bcbBaseUrl: bcbDefaultBaseUrl,
      );
    }

    debugPrint(
      '⚠️  Nenhuma credencial da brapi encontrada. As chamadas seguirão sem '
      'autenticação e a maior parte dos endpoints responderá 401.',
    );
    return const ApiConfig(
      mode: BrapiMode.direct,
      brapiBaseUrl: _definedBase,
      bcbBaseUrl: bcbDefaultBaseUrl,
    );
  }

  static String? _fromDotenv(String key) {
    try {
      final value = dotenv.env[key];
      return (value != null && value.trim().isNotEmpty) ? value.trim() : null;
    } catch (_) {
      // dotenv não inicializado (testes, ou asset ausente).
      return null;
    }
  }

  bool get hasCredential => mode == BrapiMode.proxied || brapiToken != null;

  /// Descrição segura para log e diagnóstico — nunca expõe o token.
  String get diagnostics => switch (mode) {
        BrapiMode.proxied => 'brapi via proxy ($brapiBaseUrl)',
        BrapiMode.direct => brapiToken == null
            ? 'brapi direta, SEM credencial'
            : 'brapi direta, token ****${brapiToken!.length > 4 ? brapiToken!.substring(brapiToken!.length - 4) : ''}',
      };
}
