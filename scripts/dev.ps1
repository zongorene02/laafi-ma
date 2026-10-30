<#
.SYNOPSIS
    Démarre l'environnement de développement local de Laafi Ma (sans Docker).

.DESCRIPTION
    Laafi Ma compte trois parties : l'API Python (core-service), la console
    d'administration React (admin) et l'application Flutter (frontend). Ce
    script est la façon officielle de les lancer en local.

    L'API et la console tournent dans des fenêtres masquées, avec leurs
    journaux écrits dans un fichier à côté de leur code. L'application
    Flutter reste au premier plan (rechargement à chaud).

.PARAMETER Services
    Ce qu'il faut démarrer, parmi core, admin, app. Par défaut : core seul.

.PARAMETER NoModels
    Démarre l'API SANS charger NLLB/Whisper/MMS (LOAD_MODELS_ON_STARTUP=false).
    Indispensable sur une machine à 8 Go de RAM quand on ne travaille pas sur
    la voix : l'assistant texte en français, la base de connaissances,
    l'espace agent, l'annuaire et les statistiques fonctionnent ; la voix et
    le mooré/dioula répondent 503.

.EXAMPLE
    .\scripts\dev.ps1
    Démarre l'API avec ses modèles (1 à 3 minutes de chargement).

.EXAMPLE
    .\scripts\dev.ps1 -Services core,admin -NoModels
    Démarre l'API sans modèles et la console d'administration.

.EXAMPLE
    .\scripts\dev.ps1 -Stop
    Arrête tout ce qui a été démarré par ce script.
#>

[CmdletBinding()]
param(
    [ValidateSet('core', 'admin', 'app')]
    [string[]]$Services = @('core'),

    [switch]$NoModels,

    [switch]$Stop
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$coreDir = Join-Path $root 'backend\services\core-service'

# Ports occupés par chaque partie — sert à la fois à les arrêter (-Stop) et à
# prévenir avant de lancer une partie dont le port est déjà pris.
$ports = @{
    'core'  = 8000
    'admin' = 5173
    'app'   = 5000
}

function Stop-OnPort([int]$Port, [string]$Label) {
    $connections = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if (-not $connections) { return $false }
    foreach ($pid_ in ($connections.OwningProcess | Select-Object -Unique)) {
        Stop-Process -Id $pid_ -Force -ErrorAction SilentlyContinue
    }

    # `Stop-Process` rend la main avant que Windows n'ait libere le socket
    # d'ecoute : sans cette attente, un `-Stop` suivi d'un redemarrage
    # immediat voyait le port encore occupe et gardait l'ancien processus.
    for ($i = 0; $i -lt 40; $i++) {
        if (-not (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 250
    }
    Write-Host "  arrete : $Label (port $Port)"
    return $true
}

if ($Stop) {
    Write-Host "Arret des services..."
    $stopped = $false
    foreach ($name in $ports.Keys) {
        if (Stop-OnPort $ports[$name] $name) { $stopped = $true }
    }
    if (-not $stopped) { Write-Host "  (rien ne tournait)" }
    return
}

function Start-Core {
    $port = $ports['core']
    if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
        Write-Host "  core : deja demarre sur le port $port, ignore"
        return
    }

    $python = Join-Path $coreDir 'venv\Scripts\python.exe'
    if (-not (Test-Path $python)) {
        Write-Warning "core : environnement Python absent ($python). Voir backend\services\core-service\README.md."
        return
    }

    # Schema a jour avant de demarrer (idempotent).
    Push-Location $coreDir
    try { & $python -m alembic upgrade head } finally { Pop-Location }

    # `-RedirectStandardInput` sur un fichier VIDE : une bibliotheque qui
    # appelle `input()` au demarrage bloquerait sinon indefiniment un
    # processus lance en arriere-plan, sans le moindre message.
    $emptyStdin = Join-Path $coreDir 'empty_stdin.txt'
    if (-not (Test-Path $emptyStdin)) { New-Item -ItemType File $emptyStdin | Out-Null }

    # La variable d'environnement est heritee par le processus lance juste
    # apres, et prime sur le .env (voir app/config.py).
    $previous = $env:LOAD_MODELS_ON_STARTUP
    if ($NoModels) { $env:LOAD_MODELS_ON_STARTUP = 'false' }
    try {
        $arguments = @('-u', '-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', "$port")
        Start-Process -FilePath $python -ArgumentList $arguments -WorkingDirectory $coreDir `
            -RedirectStandardInput $emptyStdin `
            -RedirectStandardOutput (Join-Path $coreDir 'core_stdout.log') `
            -RedirectStandardError (Join-Path $coreDir 'core_stderr.log') `
            -WindowStyle Hidden
    } finally {
        $env:LOAD_MODELS_ON_STARTUP = $previous
    }
    Write-Host "  core : demarre sur http://127.0.0.1:$port (journaux : $coreDir\core_stderr.log)"
    if ($NoModels) {
        Write-Host "    (sans modeles IA : voix et moore/dioula indisponibles)"
    } else {
        Write-Host "    (le chargement des modeles IA prend 1 a 3 minutes : /health repond des qu'ils sont prets)"
    }
}

Write-Host "Demarrage : $($Services -join ', ')"

foreach ($service in $Services) {
    switch ($service) {
        'core' { Start-Core }
        'admin' {
            $adminDir = Join-Path $root 'admin'
            if (-not (Test-Path (Join-Path $adminDir 'node_modules'))) {
                Write-Host "  admin : installation des dependances (npm ci)..."
                Start-Process -FilePath 'npm.cmd' -ArgumentList 'ci' -WorkingDirectory $adminDir -Wait -NoNewWindow
            }
            Start-Process -FilePath 'npm.cmd' -ArgumentList 'run', 'dev' -WorkingDirectory $adminDir -WindowStyle Hidden
            Write-Host "  admin : demarre sur http://127.0.0.1:$($ports['admin'])"
        }
        'app' {
            # `flutter run` reste au PREMIER PLAN volontairement : c'est lui qui
            # fournit le rechargement a chaud (touche r) et les erreurs de
            # l'application.
            Write-Host "  app : lancement de Flutter dans cette fenetre (Ctrl+C pour arreter)"
            Push-Location (Join-Path $root 'frontend')
            try { & flutter run -d chrome --web-port $ports['app'] } finally { Pop-Location }
        }
    }
}

Write-Host ""
Write-Host "Pour tout arreter : .\scripts\dev.ps1 -Stop"
