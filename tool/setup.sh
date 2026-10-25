#!/usr/bin/env bash
#
# Prepara uma máquina nova para compilar e executar o Equisim (macOS / Linux).
#
# Faz todos os passos que um clone recém-baixado precisa: verifica o Node, cria
# o arquivo de configuração local que o git não versiona (porque guarda
# credencial) e baixa as dependências travadas em package-lock.json —
# exatamente as mesmas versões da máquina de desenvolvimento.
#
# É idempotente: rodar de novo não sobrescreve nada que já exista.
#
# Uso:
#     ./tool/setup.sh                  # instalação padrão
#     ./tool/setup.sh --com-functions  # inclui as dependências Node do proxy
#     ./tool/setup.sh --verificar      # roda a verificação de tipos e os testes ao final

set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

COM_FUNCTIONS=0
VERIFICAR=0
for arg in "$@"; do
  case "$arg" in
    --com-functions) COM_FUNCTIONS=1 ;;
    --verificar)     VERIFICAR=1 ;;
    -h|--help)       sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "Argumento desconhecido: $arg" >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then
  AZUL=$'\033[36m'; VERDE=$'\033[32m'; AMARELO=$'\033[33m'; VERMELHO=$'\033[31m'; FIM=$'\033[0m'
else
  AZUL=''; VERDE=''; AMARELO=''; VERMELHO=''; FIM=''
fi

passo()  { printf '\n%s==> %s%s\n' "$AZUL" "$1" "$FIM"; }
ok()     { printf '    %sOK  %s%s\n' "$VERDE" "$1" "$FIM"; }
aviso()  { printf '    %s!   %s%s\n' "$AMARELO" "$1" "$FIM"; }
falhar() { printf '\n%sERRO: %s%s\n' "$VERMELHO" "$1" "$FIM" >&2; exit 1; }

echo "Equisim - preparação do ambiente"
echo "Raiz: $RAIZ"

# --- 1. Node ----------------------------------------------------------------
# Dois pisos. O aplicativo compila com o do Vite (20.19, ou 22.12 na linha 22).
# As ferramentas de medição de tool/ leem o cache da validação pelo
# `node:sqlite`, que o Node só oferece sem bandeira a partir do 22.13.
passo 'Verificando o Node'
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  falhar "Node não encontrado no PATH.

Instale a versão LTS (22 ou mais recente) e reabra o terminal:
    https://nodejs.org/pt-br/download"
fi
VERSAO="$(node --version)"
MAIOR="$(node -p 'process.versions.node.split(".")[0]')"
MENOR="$(node -p 'process.versions.node.split(".")[1]')"
echo "    node $VERSAO, npm $(npm --version)"
if [ "$MAIOR" -lt 20 ] || { [ "$MAIOR" -eq 20 ] && [ "$MENOR" -lt 19 ]; } \
  || { [ "$MAIOR" -eq 21 ]; } || { [ "$MAIOR" -eq 22 ] && [ "$MENOR" -lt 12 ]; }; then
  falhar "Node $VERSAO é antigo para o Vite, que pede 20.19+ ou 22.12+.
    https://nodejs.org/pt-br/download"
fi
if [ "$MAIOR" -lt 22 ] || { [ "$MAIOR" -eq 22 ] && [ "$MENOR" -lt 13 ]; }; then
  aviso "O aplicativo roda, mas as ferramentas de tool/ pedem Node 22.13+ (node:sqlite)."
else
  ok 'aplicativo e ferramentas de medição'
fi

# --- 2. Configuração local --------------------------------------------------
# O .env guarda o BRAPI_TOKEN das ferramentas e as variáveis VITE_* do
# aplicativo. Não é versionado. Atenção: tudo o que estiver numa VITE_* é
# embarcado no bundle do site — em produção o token fica no proxy.
passo 'Arquivo de configuração local'

if [ -f .env ]; then
  ok '.env já existe (preservado)'
else
  cp .env.example .env
  ok '.env criado a partir de .env.example'
  aviso 'Para as ferramentas: preencha BRAPI_TOKEN em .env (https://brapi.dev/dashboard)'
  aviso 'Para o aplicativo em desenvolvimento: VITE_BRAPI_TOKEN, ou VITE_BRAPI_PROXY_URL'
fi

# --- 3. Dependências --------------------------------------------------------
# `npm ci`, e não `npm install`: instala exatamente o package-lock.json e
# recusa um lockfile que não bate com o package.json, em vez de reescrevê-lo.
passo 'Baixando as dependências (aplicativo, ferramentas e QA)'
npm ci

# --- 4. Cloud Function (opcional) ------------------------------------------
if [ "$COM_FUNCTIONS" -eq 1 ]; then
  passo 'Dependências Node da função de proxy'
  npm ci --prefix functions
fi

# --- 5. Hooks de QA --------------------------------------------------------
# `core.hooksPath` é configuração LOCAL do clone: não viaja no git. Sem este
# passo, os hooks versionados em .githooks/ ficariam inertes numa máquina nova.
# O bit de execução também: o git os grava sem ele, e no macOS e no Linux um
# hook sem o bit é ignorado com um aviso.
passo 'Hooks de QA'
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/pre-push
echo '  pre-commit: verificações locais, sem rede (~0,3s)'
echo '  pre-push:   auditoria com o Gemini (requer GEMINI_API_KEY em .env.qa)'

# --- 6. Verificação (opcional) ---------------------------------------------
if [ "$VERIFICAR" -eq 1 ]; then
  passo 'Verificação de tipos';                          npm run typecheck
  passo 'Testes (núcleo, paridade, dados, telas e ferramentas)'; npm test
fi

printf '\n%sPronto.%s\n' "$VERDE" "$FIM"
cat <<'FIM_MSG'

Para executar:
    npm run dev          # http://localhost:5173

Sem Firebase configurado, o aplicativo abre em modo local, com os dados no
navegador. Sem credencial da brapi, as telas que consultam cotação ficam sem
dados: veja o README, seção "Configuração".

Ferramentas de medição:
    npm run tool         # lista as ferramentas; o mapa está em tool/README.md
FIM_MSG
