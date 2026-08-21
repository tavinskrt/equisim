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
///
/// Deliberadamente **livre de Flutter**: é o que permite ao executor de
/// validação da Fase 5 usar exatamente a mesma camada de dados do aplicativo,
/// em vez de uma reimplementação que poderia divergir em silêncio.
class ApiConfig {
  final BrapiMode mode;
  final String brapiBaseUrl;
  final String? brapiToken;
  final String bcbBaseUrl;

  /// Como a credencial foi obtida — para diagnóstico e alerta.
  final String credentialSource;

  const ApiConfig({
    required this.mode,
    required this.brapiBaseUrl,
    required this.bcbBaseUrl,
    this.brapiToken,
    this.credentialSource = 'não identificada',
  });

  // --- Valores de compilação (`--dart-define-from-file=config/local.json`) ---
  static const String _definedToken = String.fromEnvironment('BRAPI_TOKEN');
  static const String _definedProxy = String.fromEnvironment('BRAPI_PROXY_URL');
  static const String _definedBase = String.fromEnvironment(
    'BRAPI_BASE_URL',
    defaultValue: 'https://brapi.dev/api',
  );

  /// A API SGS do Banco Central é aberta: sem token, sem cadastro.
  static const String bcbDefaultBaseUrl = 'https://api.bcb.gov.br/dados/serie';

  /// Resolve a configuração na seguinte ordem de precedência:
  ///
  /// 1. `BRAPI_PROXY_URL` definido em compilação → modo proxy, sem token;
  /// 2. `BRAPI_TOKEN` definido em compilação → modo direto;
  /// 3. [fallbackToken] → modo direto, marcado como origem insegura.
  ///
  /// O passo 3 recebe o que o chamador conseguir obter de um `.env` ou de
  /// variável de ambiente. Existe para não quebrar o fluxo de desenvolvimento
  /// durante a transição, e a origem fica registrada em [credentialSource]
  /// para que a interface possa alertar.
  factory ApiConfig.resolve({
    String? fallbackToken,
    String? fallbackBaseUrl,
  }) {
    if (_definedProxy.isNotEmpty) {
      return ApiConfig(
        mode: BrapiMode.proxied,
        brapiBaseUrl: _definedProxy,
        bcbBaseUrl: bcbDefaultBaseUrl,
        credentialSource: 'proxy de custódia',
      );
    }

    if (_definedToken.isNotEmpty) {
      return const ApiConfig(
        mode: BrapiMode.direct,
        brapiBaseUrl: _definedBase,
        brapiToken: _definedToken,
        bcbBaseUrl: bcbDefaultBaseUrl,
        credentialSource: 'definição de compilação',
      );
    }

    final token = fallbackToken?.trim();
    if (token != null && token.isNotEmpty) {
      return ApiConfig(
        mode: BrapiMode.direct,
        brapiBaseUrl: fallbackBaseUrl?.trim().isNotEmpty == true
            ? fallbackBaseUrl!.trim()
            : _definedBase,
        brapiToken: token,
        bcbBaseUrl: bcbDefaultBaseUrl,
        credentialSource: 'arquivo .env (embarcado no bundle)',
      );
    }

    return const ApiConfig(
      mode: BrapiMode.direct,
      brapiBaseUrl: _definedBase,
      bcbBaseUrl: bcbDefaultBaseUrl,
      credentialSource: 'ausente',
    );
  }

  bool get hasCredential => mode == BrapiMode.proxied || brapiToken != null;

  /// `true` quando a credencial veio por via que a expõe no bundle.
  bool get credentialIsExposed =>
      mode == BrapiMode.direct && credentialSource.contains('.env');

  /// Descrição segura para log e diagnóstico — nunca expõe o token.
  String get diagnostics => switch (mode) {
        BrapiMode.proxied => 'brapi via proxy ($brapiBaseUrl)',
        BrapiMode.direct => brapiToken == null
            ? 'brapi direta, SEM credencial'
            : 'brapi direta, token ****${brapiToken!.length > 4 ? brapiToken!.substring(brapiToken!.length - 4) : ''} '
                '[$credentialSource]',
      };
}
