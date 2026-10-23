/** Como o cliente alcança a brapi. */
export enum BrapiMode {
  /**
   * Chamada direta com o token embarcado no bundle.
   *
   * O token é extraível por quem abre o bundle: no Vite, toda variável
   * `VITE_*` é **substituída no código-fonte** durante o build e fica legível
   * no JavaScript servido. Aceitável em desenvolvimento; para distribuição,
   * use [BrapiMode.proxied].
   */
  direct = 'direct',

  /**
   * Chamada via função de nuvem que injeta o token no servidor.
   *
   * Única forma real de proteger a credencial, e resolve o CORS no navegador
   * sem entregar o cabeçalho `Authorization` a um proxy público de terceiro.
   */
  proxied = 'proxied',
}

/** Valores lidos do ambiente de build. */
export interface ApiEnvironment {
  /** Endereço do proxy de custódia (`VITE_BRAPI_PROXY_URL`). */
  proxyUrl?: string | null;
  /** Token da brapi (`VITE_BRAPI_TOKEN`) — exposto no bundle. */
  token?: string | null;
  /** Raiz da brapi (`VITE_BRAPI_BASE_URL`). */
  baseUrl?: string | null;
}

/**
 * Configuração de acesso às APIs externas.
 *
 * Deliberadamente **livre de navegador**: é o que permite às ferramentas de
 * `tool/`, que rodam no Node, usar exatamente a mesma camada de dados do
 * aplicativo, em vez de uma reimplementação que poderia divergir em silêncio.
 */
export class ApiConfig {
  /** Como a brapi é alcançada — direta ou por proxy de custódia. */
  readonly mode: BrapiMode;

  /** Raiz da API brapi, ou do proxy quando [mode] é [BrapiMode.proxied]. */
  readonly brapiBaseUrl: string;

  /**
   * Token da brapi. `null` em modo proxy, onde o servidor o injeta, e também
   * quando nenhuma credencial foi encontrada.
   *
   * **Nunca inclua este valor em log.** O log sanitizado o mascara.
   */
  readonly brapiToken: string | null;

  /** Raiz da API SGS do Banco Central. */
  readonly bcbBaseUrl: string;

  /** Como a credencial foi obtida — para diagnóstico e alerta. */
  readonly credentialSource: string;

  constructor(args: {
    mode: BrapiMode;
    brapiBaseUrl: string;
    bcbBaseUrl: string;
    brapiToken?: string | null;
    credentialSource?: string;
  }) {
    this.mode = args.mode;
    this.brapiBaseUrl = args.brapiBaseUrl;
    this.bcbBaseUrl = args.bcbBaseUrl;
    this.brapiToken = args.brapiToken ?? null;
    this.credentialSource = args.credentialSource ?? 'não identificada';
  }

  /** Raiz padrão da brapi. */
  static readonly brapiDefaultBaseUrl = 'https://brapi.dev/api';

  /** A API SGS do Banco Central é aberta: sem token, sem cadastro. */
  static readonly bcbDefaultBaseUrl = 'https://api.bcb.gov.br/dados/serie';

  /**
   * Resolve a configuração na seguinte ordem de precedência:
   *
   * 1. `proxyUrl` definido → modo proxy, sem token;
   * 2. `token` definido → modo direto, marcado como origem exposta no bundle;
   * 3. nada → modo direto sem credencial.
   *
   * A origem fica registrada em [credentialSource] para que a interface possa
   * alertar quando a credencial viaja no JavaScript servido.
   */
  static resolve(env: ApiEnvironment = {}): ApiConfig {
    const proxy = env.proxyUrl?.trim() ?? '';
    const base = env.baseUrl?.trim() ?? '';
    const brapiBaseUrl = base.length > 0 ? base : ApiConfig.brapiDefaultBaseUrl;
    if (proxy.length > 0) {
      return new ApiConfig({
        mode: BrapiMode.proxied,
        brapiBaseUrl: proxy,
        bcbBaseUrl: ApiConfig.bcbDefaultBaseUrl,
        credentialSource: 'proxy de custódia',
      });
    }
    const token = env.token?.trim() ?? '';
    if (token.length > 0) {
      return new ApiConfig({
        mode: BrapiMode.direct,
        brapiBaseUrl,
        brapiToken: token,
        bcbBaseUrl: ApiConfig.bcbDefaultBaseUrl,
        credentialSource: 'variável VITE_BRAPI_TOKEN (embarcada no bundle)',
      });
    }
    return new ApiConfig({
      mode: BrapiMode.direct,
      brapiBaseUrl,
      bcbBaseUrl: ApiConfig.bcbDefaultBaseUrl,
      credentialSource: 'ausente',
    });
  }

  /**
   * `true` quando há como autenticar — token presente ou proxy que o injeta.
   *
   * Não garante que a credencial seja **válida**: só que existe. A validade
   * só se descobre na primeira resposta `401`.
   */
  get hasCredential(): boolean {
    return this.mode === BrapiMode.proxied || this.brapiToken !== null;
  }

  /** `true` quando a credencial veio por via que a expõe no bundle. */
  get credentialIsExposed(): boolean {
    return this.mode === BrapiMode.direct && this.credentialSource.includes('bundle');
  }
}
