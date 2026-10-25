#Requires -Version 5.1
<#
.SYNOPSIS
    Prepara uma máquina nova para compilar e executar o Equisim.

.DESCRIPTION
    Roda todos os passos de instalação que um clone recém-baixado precisa:
    verifica o Node, cria o arquivo de configuração local que o git não
    versiona (porque guarda credencial) e baixa as dependências travadas em
    package-lock.json — as mesmas versões da máquina de desenvolvimento.

    O script é idempotente: rodar de novo não sobrescreve nada que já exista.

.PARAMETER ComFunctions
    Instala também as dependências Node da função de proxy (functions/).
    Só é necessário para quem for publicar a Cloud Function.

.PARAMETER Verificar
    Ao final, roda a verificação de tipos e a suíte de testes.

.EXAMPLE
    .\tool\setup.ps1

.EXAMPLE
    .\tool\setup.ps1 -Verificar
#>
param(
    [switch]$ComFunctions,
    [switch]$Verificar
)

$ErrorActionPreference = 'Stop'

# Tudo é resolvido a partir da raiz do repositório, não do diretório de onde o
# script foi chamado.
$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz

function Passo($texto)  { Write-Host "`n==> $texto" -ForegroundColor Cyan }
function Ok($texto)     { Write-Host "    OK  $texto" -ForegroundColor Green }
function Aviso($texto)  { Write-Host "    !   $texto" -ForegroundColor Yellow }
function Falhar($texto) { Write-Host "`nERRO: $texto" -ForegroundColor Red; exit 1 }

function Exigir-Sucesso($comando) {
    if ($LASTEXITCODE -ne 0) { Falhar "'$comando' terminou com código $LASTEXITCODE." }
}

Write-Host "Equisim - preparação do ambiente" -ForegroundColor White
Write-Host "Raiz: $raiz"

# --- 1. Node ----------------------------------------------------------------
# Dois pisos. O aplicativo compila com o do Vite (20.19, ou 22.12 na linha 22).
# As ferramentas de medição de tool/ leem o cache da validação pelo
# `node:sqlite`, que o Node só oferece sem bandeira a partir do 22.13.
Passo 'Verificando o Node'
if (-not (Get-Command node -ErrorAction SilentlyContinue) -or -not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Falhar @"
Node não encontrado no PATH.

Instale a versão LTS (22 ou mais recente) e reabra o terminal:
    https://nodejs.org/pt-br/download
"@
}
$versao = [version]((node --version).TrimStart('v'))
Write-Host "    node v$versao, npm $(npm --version)"
$antigoParaVite = ($versao -lt [version]'20.19.0') -or ($versao.Major -eq 21) -or
    ($versao.Major -eq 22 -and $versao -lt [version]'22.12.0')
if ($antigoParaVite) {
    Falhar @"
Node v$versao é antigo para o Vite, que pede 20.19+ ou 22.12+.
    https://nodejs.org/pt-br/download
"@
}
if ($versao -lt [version]'22.13.0') {
    Aviso 'O aplicativo roda, mas as ferramentas de tool/ pedem Node 22.13+ (node:sqlite).'
} else {
    Ok 'aplicativo e ferramentas de medição'
}

# --- 2. Configuração local --------------------------------------------------
# O .env guarda o BRAPI_TOKEN das ferramentas e as variáveis VITE_* do
# aplicativo. Não é versionado. Atenção: tudo o que estiver numa VITE_* é
# embarcado no bundle do site — em produção o token fica no proxy.
Passo 'Arquivo de configuração local'

if (Test-Path '.env') {
    Ok '.env já existe (preservado)'
} else {
    # Cópia byte a byte, e não Get-Content/Set-Content: o PowerShell 5.1 lê
    # arquivo UTF-8 sem BOM como ANSI e devolveria os acentos do comentário
    # corrompidos, além de plantar um BOM na saída.
    Copy-Item '.env.example' '.env'
    Ok '.env criado a partir de .env.example'
    Aviso 'Para as ferramentas: preencha BRAPI_TOKEN em .env (https://brapi.dev/dashboard)'
    Aviso 'Para o aplicativo em desenvolvimento: VITE_BRAPI_TOKEN, ou VITE_BRAPI_PROXY_URL'
}

# --- 3. Dependências --------------------------------------------------------
# `npm ci`, e não `npm install`: instala exatamente o package-lock.json e
# recusa um lockfile que não bate com o package.json, em vez de reescrevê-lo.
Passo 'Baixando as dependências (aplicativo, ferramentas e QA)'
npm ci
Exigir-Sucesso 'npm ci'

# --- 4. Cloud Function (opcional) ------------------------------------------
if ($ComFunctions) {
    Passo 'Dependências Node da função de proxy'
    npm ci --prefix functions
    Exigir-Sucesso 'npm ci --prefix functions'
}

# --- 5. Hooks de QA --------------------------------------------------------
# `core.hooksPath` é configuração LOCAL do clone: não viaja no git. Sem este
# passo, os hooks versionados em .githooks/ ficariam inertes numa máquina nova.
Passo 'Hooks de QA'
git config core.hooksPath .githooks
Write-Host '  pre-commit: verificacoes locais, sem rede (~0,3s)'
Write-Host '  pre-push:   auditoria com o Gemini (requer GEMINI_API_KEY em .env.qa)'

# --- 6. Verificação (opcional) ---------------------------------------------
if ($Verificar) {
    Passo 'Verificação de tipos'
    npm run typecheck
    Exigir-Sucesso 'npm run typecheck'

    Passo 'Testes (núcleo, paridade, dados, telas e ferramentas)'
    npm test
    Exigir-Sucesso 'npm test'
}

Write-Host "`nPronto." -ForegroundColor Green
Write-Host @"

Para executar:
    npm run dev          # http://localhost:5173

Sem Firebase configurado, o aplicativo abre em modo local, com os dados no
navegador. Sem credencial da brapi, as telas que consultam cotacao ficam sem
dados: veja o README, secao "Configuracao".

Ferramentas de medicao:
    npm run tool         # lista as ferramentas; o mapa esta em tool/README.md
"@
