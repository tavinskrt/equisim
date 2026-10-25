/// <reference types="vite/client" />

/**
 * As variáveis de ambiente que o aplicativo lê.
 *
 * **Toda `VITE_*` é embarcada no bundle** e fica legível no JavaScript servido.
 * Segredo de ferramenta (a `GEMINI_API_KEY`, por exemplo) mora em `.env.qa`,
 * que nem é lido pelo Vite. Ver `.env.example`.
 */
interface ImportMetaEnv {
  /** Proxy de custódia da brapi — o caminho de produção. */
  readonly VITE_BRAPI_PROXY_URL?: string;
  /** Token da brapi direto no bundle: só para desenvolvimento. */
  readonly VITE_BRAPI_TOKEN?: string;
  /** Raiz alternativa da brapi. */
  readonly VITE_BRAPI_BASE_URL?: string;
  /** `true` força o modo local, sem Firebase. */
  readonly VITE_EQUISIM_LOCAL?: string;
  /** `true` liga o painel de logs num build de produção; `false` o desliga no desenvolvimento. */
  readonly VITE_EQUISIM_AUDIT?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
