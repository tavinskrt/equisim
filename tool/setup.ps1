#Requires -Version 5.1
<#
.SYNOPSIS
    Prepara uma máquina nova para compilar e executar o Equisim.

.DESCRIPTION
    Roda todos os passos de instalação que um clone recém-baixado precisa:
    verifica o Flutter, cria os arquivos de configuração locais que o git não
    versiona (porque guardam credencial) e baixa as dependências travadas em
    pubspec.lock — as mesmas versões da máquina de desenvolvimento.

    O script é idempotente: rodar de novo não sobrescreve nada que já exista.

.PARAMETER ComFunctions
    Instala também as dependências Node da função de proxy (functions/).
    Só é necessário para quem for publicar a Cloud Function.

.PARAMETER Verificar
    Ao final, roda a análise estática e a suíte de testes.

.PARAMETER PularChecagens
    Ignora a verificação de suporte a links simbólicos.

.EXAMPLE
    .\tool\setup.ps1

.EXAMPLE
    .\tool\setup.ps1 -Verificar
#>
param(
    [switch]$ComFunctions,
    [switch]$Verificar,
    [switch]$PularChecagens
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

# --- 1. SDK -----------------------------------------------------------------
Passo 'Verificando o Flutter'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Falhar @"
Flutter não encontrado no PATH.

Instale a versão estável (3.44 ou mais recente) e reabra o terminal:
    https://docs.flutter.dev/get-started/install/windows

A versão mínima também está declarada em pubspec.yaml, então o próprio
'flutter pub get' recusa um SDK antigo com uma mensagem explícita.
"@
}
flutter --version
Exigir-Sucesso 'flutter --version'

# --- 2. Symlinks (exclusivo do Windows) -------------------------------------
# O 'pub get' de um projeto com plugins cria links simbólicos em
# windows/flutter/ephemeral/.plugin_symlinks. Criar link simbólico no Windows
# exige privilégio: sem ele, o pub get morre com "Building with plugins
# requires symlink support" — e num clone novo isso acontece antes de qualquer
# outra coisa. A checagem aqui só antecipa o erro com instrução de conserto.
if (-not $PularChecagens) {
    Passo 'Verificando suporte a links simbólicos'
    $sonda = Join-Path $env:TEMP ("equisim_symlink_" + [guid]::NewGuid().ToString('N'))
    $podeCriarSymlink = $false
    try {
        New-Item -ItemType SymbolicLink -Path $sonda -Target $env:TEMP -ErrorAction Stop | Out-Null
        $podeCriarSymlink = $true
    } catch {
        $podeCriarSymlink = $false
    }
    if (Test-Path $sonda) { try { (Get-Item $sonda).Delete() } catch { } }

    if ($podeCriarSymlink) {
        Ok 'links simbólicos permitidos'
    } else {
        Falhar @"
Esta máquina não permite criar links simbólicos, e o Flutter precisa deles para
projetos com plugins (aqui: Firebase, path_provider, shared_preferences).

Resolva de UMA destas formas:

  1. Ligue o Modo de Desenvolvedor (recomendado, uma vez só):
         start ms-settings:developers
     Ative "Modo de desenvolvedor", reabra o terminal e rode este script de novo.

  2. Ou abra o PowerShell como Administrador e rode este script por lá.

Se tiver certeza de que o ambiente funciona mesmo assim, repita com
-PularChecagens para ignorar esta verificação.
"@
    }
}

# --- 3. Configuração local --------------------------------------------------
# Estes arquivos guardam credencial e por isso não são versionados. O .env em
# particular está declarado como asset no pubspec.yaml: sem ele, a compilação
# falha antes mesmo de chegar ao código.
Passo 'Arquivos de configuração local'

if (Test-Path '.env') {
    Ok '.env já existe (preservado)'
} else {
    # Leitura e escrita por .NET, e não por Get-Content/Set-Content: o
    # PowerShell 5.1 lê arquivo UTF-8 sem BOM como ANSI e devolveria os
    # acentos do comentário corrompidos, além de plantar um BOM na saída.
    $utf8SemBom = New-Object System.Text.UTF8Encoding($false)
    $exemplo = [System.IO.File]::ReadAllText((Join-Path $raiz '.env.example'), $utf8SemBom)
    [System.IO.File]::WriteAllText(
        (Join-Path $raiz '.env'),
        $exemplo.Replace('BRAPI_TOKEN=seu_token_aqui', 'BRAPI_TOKEN='),
        $utf8SemBom)
    Ok '.env criado a partir de .env.example'
    Aviso 'Preencha BRAPI_TOKEN em .env com o token de https://brapi.dev/dashboard'
}

if (Test-Path 'config/local.json') {
    Ok 'config/local.json já existe (preservado)'
} else {
    Copy-Item 'config/local.example.json' 'config/local.json'
    Ok 'config/local.json criado a partir do exemplo'
}

# --- 4. Dependências Dart ---------------------------------------------------
Passo 'Baixando as dependências do aplicativo'
flutter pub get
Exigir-Sucesso 'flutter pub get'

Passo 'Baixando as dependências do núcleo (packages/equisim_core)'
Push-Location 'packages/equisim_core'
try {
    dart pub get
    Exigir-Sucesso 'dart pub get'
} finally {
    Pop-Location
}

# --- 5. Cloud Function (opcional) ------------------------------------------
if ($ComFunctions) {
    Passo 'Dependências Node da função de proxy'
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Falhar 'npm não encontrado. Instale o Node 20 ou rode sem -ComFunctions.'
    }
    npm install --prefix functions
    Exigir-Sucesso 'npm install'
}

# --- 6. Verificação (opcional) ---------------------------------------------
if ($Verificar) {
    Passo 'Análise estática'
    flutter analyze
    Exigir-Sucesso 'flutter analyze'

    Passo 'Testes do aplicativo'
    flutter test
    Exigir-Sucesso 'flutter test'

    Passo 'Testes do núcleo de domínio'
    dart test --directory packages/equisim_core
    Exigir-Sucesso 'dart test'
}

Write-Host "`nPronto." -ForegroundColor Green
Write-Host @"

Para executar:
    flutter run

O aplicativo sobe sem token, mas as telas que consultam a brapi ficam sem
dados. Escolha uma das formas de credencial descritas no README, secao
"Configuracao" - a mais simples e preencher BRAPI_TOKEN em .env.
"@
