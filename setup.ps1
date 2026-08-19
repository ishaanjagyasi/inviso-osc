# Sets up and runs Inviso with OSC control on Windows.
# Works from wherever the repo was cloned. Run: .\setup.ps1
#
# The app needs Node 16: it builds with webpack 2, which breaks on Node 17+
# because OpenSSL 3 removed the md4 hash it uses for module ids.

$ErrorActionPreference = 'Stop'

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$NodeVersion = '16'

Set-Location $RepoDir

function Info($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Warn($msg) { Write-Host "==> $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "==> $msg" -ForegroundColor Red; exit 1 }

# --- Node 16 -----------------------------------------------------------------

function Get-NodeMajor {
    try { (node -v) -replace '^v(\d+).*', '$1' } catch { $null }
}

if ((Get-NodeMajor) -eq $NodeVersion) {
    Info "Node $(node -v) already active."
}
else {
    if (Get-Command nvm -ErrorAction SilentlyContinue) {
        Info "Found nvm-windows, selecting Node $NodeVersion..."
        nvm install $NodeVersion | Out-Null
        nvm use $NodeVersion | Out-Null

        if ((Get-NodeMajor) -ne $NodeVersion) {
            Fail "Could not activate Node $NodeVersion. Try running this terminal as Administrator."
        }
    }
    else {
        Warn "Node $NodeVersion is required and nvm-windows was not found."
        Warn "Install it from https://github.com/coreybutler/nvm-windows/releases"
        Fail "Then re-run this script."
    }

    Info "Using Node $(node -v)."
}

# --- Dependencies ------------------------------------------------------------

# node_modules is committed upstream, so its presence proves nothing about
# whether it matches package.json. Always let npm reconcile the two; it is
# quick when there is nothing to do.
# --legacy-peer-deps because sass-loader 6 declares a peer of node-sass 4
# while the project pins node-sass 8. The conflict predates this work and is
# harmless: nothing imports .scss through webpack, so sass-loader never runs.
Info 'Checking app dependencies...'
npm install --legacy-peer-deps
if ($LASTEXITCODE -ne 0) { Fail "npm install failed in $RepoDir." }

if (-not (Test-Path 'osc-bridge\node_modules')) {
    Info 'Installing relay dependencies...'
    Push-Location 'osc-bridge'
    npm install
    $code = $LASTEXITCODE
    Pop-Location
    if ($code -ne 0) { Fail 'npm install failed in osc-bridge.' }
}
else {
    Info 'Relay dependencies already installed.'
}

# node-sass ships no prebuilt binary for some platforms, so compile it locally
# when the prebuilt one will not load.
node -e "require('node-sass')" 2>$null
if ($LASTEXITCODE -ne 0) {
    Info 'Building node-sass for this platform...'
    npm rebuild node-sass --build-from-source
    if ($LASTEXITCODE -ne 0) {
        Fail 'node-sass build failed. Install the Visual Studio Build Tools, then re-run.'
    }
}

# --- Run ---------------------------------------------------------------------

$relay = $null
$inUse = Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue

if ($inUse) {
    Info 'Relay already running on port 8081, leaving it alone.'
}
else {
    Info 'Starting OSC relay...'
    $relay = Start-Process node -ArgumentList 'index.js' -WorkingDirectory "$RepoDir\osc-bridge" -PassThru -NoNewWindow
}

try {
    Info 'Starting Inviso at http://localhost:8080'
    Info 'Click OSC in the top bar to enable it and set your UDP port.'
    npm run dev
}
finally {
    if ($relay -and -not $relay.HasExited) { Stop-Process -Id $relay.Id -Force }
}
