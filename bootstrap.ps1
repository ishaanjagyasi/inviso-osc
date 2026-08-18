# One-step install for Inviso with OSC control, on Windows.
#
# Downloads the repo, sets everything up, and runs the site. Safe to re-run:
# an existing clone is updated rather than replaced.
#
#   .\bootstrap.ps1 [target-directory]
#
# The repo is private, so this needs either the GitHub CLI (gh auth login) or
# git credentials with access to it.

param([string]$Target = "$PWD\inviso-osc")

$ErrorActionPreference = 'Stop'

$Repo = 'ishaanjagyasi/inviso-osc'

function Info($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "==> $msg" -ForegroundColor Red; exit 1 }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Fail 'git is not installed. Get it from https://git-scm.com/download/win'
}

if (Test-Path "$Target\.git") {
    Info "Found an existing clone at $Target, updating..."
    git -C $Target pull --ff-only
    if ($LASTEXITCODE -ne 0) { Fail "Could not update $Target. Resolve local changes and re-run." }
}
else {
    if (Test-Path $Target) { Fail "$Target already exists and is not a git clone." }

    Info "Cloning $Repo into $Target..."

    # gh handles auth for private repos without needing a stored git credential.
    $useGh = $false
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        gh auth status 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $useGh = $true }
    }

    if ($useGh) {
        gh repo clone $Repo $Target
    }
    else {
        git clone "https://github.com/$Repo.git" $Target
    }

    if ($LASTEXITCODE -ne 0) {
        Fail "Clone failed. The repo is private: run 'gh auth login', or set up a GitHub credential, then re-run."
    }
}

if (-not (Test-Path "$Target\setup.ps1")) {
    Fail "setup.ps1 missing from $Target; the clone looks incomplete."
}

Info 'Handing over to setup.ps1...'
& "$Target\setup.ps1"
