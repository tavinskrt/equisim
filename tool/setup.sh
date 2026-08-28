#!/usr/bin/env bash
#
# Prepara uma máquina nova para compilar e executar o Equisim (macOS / Linux).
#
# Faz todos os passos que um clone recém-baixado precisa: verifica o Flutter,
# cria os arquivos de configuração local que o git não versiona (porque guardam
# credencial) e baixa as dependências travadas em pubspec.lock — exatamente as
# mesmas versões da máquina de desenvolvimento.
#
# É idempotente: rodar de novo não sobrescreve nada que já exista.
#
# Uso:
#     ./tool/setup.sh                  # instalação padrão
#     ./tool/setup.sh --com-functions  # inclui as dependências Node do proxy
#     ./tool/setup.sh --verificar      # roda análise estática e testes ao final

set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

COM_FUNCTIONS=0
VERIFICAR=0
for arg in "$@"; do
  case "$arg" in
    --com-functions) COM_FUNCTIONS=1 ;;
    --verificar)     VERIFICAR=1 ;;
    -h|--help)       sed -n '2,20p' "$0"; exit 0 ;;
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

# --- 1. SDK -----------------------------------------------------------------
passo 'Verificando o Flutter'
if ! command -v flutter >/dev/null 2>&1; then
  falhar "Flutter não encontrado no PATH.

Instale a versão estável (3.44 ou mais recente) e reabra o terminal:
    https://docs.flutter.dev/get-started/install

A versão mínima também está declarada em pubspec.yaml, então o próprio
'flutter pub get' recusa um SDK antigo com uma mensagem explícita."
fi
flutter --version

# --- 2. Configuração local --------------------------------------------------
# Estes arquivos guardam credencial e por isso não são versionados. O .env em
# particular está declarado como asset no pubspec.yaml: sem ele, a compilação
# falha antes mesmo de chegar ao código.
passo 'Arquivos de configuração local'

if [ -f .env ]; then
  ok '.env já existe (preservado)'
else
  sed 's/^BRAPI_TOKEN=seu_token_aqui$/BRAPI_TOKEN=/' .env.example > .env
  ok '.env criado a partir de .env.example'
  aviso 'Preencha BRAPI_TOKEN em .env com o token de https://brapi.dev/dashboard'
fi

if [ -f config/local.json ]; then
  ok 'config/local.json já existe (preservado)'
else
  cp config/local.example.json config/local.json
  ok 'config/local.json criado a partir do exemplo'
fi

# --- 3. Dependências Dart ---------------------------------------------------
passo 'Baixando as dependências do aplicativo'
flutter pub get

passo 'Baixando as dependências do núcleo (packages/equisim_core)'
( cd packages/equisim_core && dart pub get )

# --- 4. Cloud Function (opcional) ------------------------------------------
if [ "$COM_FUNCTIONS" -eq 1 ]; then
  passo 'Dependências Node da função de proxy'
  command -v npm >/dev/null 2>&1 || falhar 'npm não encontrado. Instale o Node 20 ou rode sem --com-functions.'
  npm install --prefix functions
fi

# --- 5. Hooks de QA --------------------------------------------------------
# `core.hooksPath` e configuracao LOCAL do clone: nao viaja no git. Sem este
# passo, os hooks versionados em .githooks/ ficariam inertes numa maquina nova.
passo 'Ferramentas de QA e hooks'

# As dependências do agente de QA vivem no package.json da RAIZ, separado do
# de functions/. Sem elas o hook de pre-push não consegue rodar o auditor.
if command -v npm >/dev/null 2>&1; then
  npm install
else
  echo '  npm não encontrado: o auditor Gemini ficará indisponível.'
  echo '  O hook de pre-push detecta isso e libera o push, sem travar o fluxo.'
fi

git config core.hooksPath .githooks
echo '  pre-commit: verificações locais, sem rede (~0,3s)'
echo '  pre-push:   auditoria com o Gemini (requer GEMINI_API_KEY em .env.qa)'

# --- 6. Verificação (opcional) ---------------------------------------------
if [ "$VERIFICAR" -eq 1 ]; then
  passo 'Análise estática';            flutter analyze
  passo 'Testes do aplicativo';        flutter test
  passo 'Testes do núcleo de domínio'; dart test --directory packages/equisim_core
fi

printf '\n%sPronto.%s\n' "$VERDE" "$FIM"
cat <<'FIM_MSG'

Para executar:
    flutter run

O aplicativo sobe sem token, mas as telas que consultam a brapi ficam sem
dados. Escolha uma das formas de credencial descritas no README, seção
"Configuração" — a mais simples é preencher BRAPI_TOKEN em .env.
FIM_MSG
