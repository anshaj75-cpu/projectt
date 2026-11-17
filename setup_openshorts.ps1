<#
.SYNOPSIS
  One-click setup for the OpenShorts project on Windows.

.DESCRIPTION
  This script:
    1. Ensures an Ubuntu WSL2 distro is installed (via winget).
    2. Starts Docker Desktop and waits for its daemon to become healthy.
    3. Copies .env.example → .env if missing.
    4. Installs npm dependencies (including esbuild approval).
    5. Starts the Vite dev server (http://localhost:5173).
    6. Builds and starts the Docker‑Compose stack (backend + renderer).
    7. Shows the URLs you need and a short troubleshooting guide.

.NOTES
  • Run **as Administrator** (necessary for WSL install & Docker start).
  • Requires an internet connection.
  • The script is idempotent – you can re‑run it after fixing any step.
#>

# -------------------------------------------------
# Helper functions
# -------------------------------------------------
function Write-Info   { param([string]$msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Warn   { param([string]$msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Error  { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Wait-ForDocker {
    param([int]$timeoutSec = 180)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
        try {
            docker info > $null 2>&1
            if ($LASTEXITCODE -eq 0) { return $true }
        } catch {}
        Write-Info "Waiting for Docker daemon… ($([int]$sw.Elapsed.TotalSeconds)s)"
        Start-Sleep -Seconds 3
    }
    return $false
}

# -------------------------------------------------
# 1️⃣ Ensure Ubuntu (WSL2) is installed
# -------------------------------------------------
Write-Info "Checking for an Ubuntu WSL distro..."
$ubuntu = wsl -l -q | Where-Object { $_ -match '^Ubuntu' }
if (-not $ubuntu) {
    Write-Warn "Ubuntu not found – installing via winget..."
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Write-Error "Please re‑run this script as Administrator to install Ubuntu."
        exit 1
    }
    winget install -e --id Canonical.Ubuntu --silent
    if ($LASTEXITCODE -ne 0) { Write-Error "Ubuntu install failed. Abort."; exit 1 }
    Write-Info "Ubuntu installed – launching once for first‑run setup..."
    wsl -d Ubuntu -u root echo "Ubuntu ready"
} else {
    Write-Info "Ubuntu WSL distro already present."
}

# -------------------------------------------------
# 2️⃣ Start Docker Desktop (if not already running)
# -------------------------------------------------
$dockerRunning = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
if (-not $dockerRunning) {
    Write-Info "Launching Docker Desktop..."
    $dockerExe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (-not (Test-Path $dockerExe)) { Write-Error "Docker Desktop not found at $dockerExe"; exit 1 }
    Start-Process -FilePath $dockerExe -PassThru | Out-Null
    Start-Sleep -Seconds 8
} else {
    Write-Info "Docker Desktop already running."
}

# -------------------------------------------------
# 3️⃣ Wait for Docker daemon to be reachable
# -------------------------------------------------
Write-Info "Waiting for Docker daemon (may take ~30 s)..."
if (-not (Wait-ForDocker)) { Write-Error "Docker daemon never became reachable. Check Docker Desktop UI for errors."; exit 1 }
Write-Info "Docker daemon is ready."

# -------------------------------------------------
# 4️⃣ Ensure .env exists
# -------------------------------------------------
if (-not (Test-Path ".env")) {
    Write-Info "Creating .env from .env.example"
    Copy-Item -Path ".env.example" -Destination ".env"
} else {
    Write-Info ".env already exists – leaving as‑is."
}

# -------------------------------------------------
# 5️⃣ Install UI npm dependencies & approve scripts
# -------------------------------------------------
Push-Location "dashboard"
Write-Info "Running npm install (this may take a few minutes)..."
npm install
if ($LASTEXITCODE -ne 0) { Write-Error "npm install failed."; Pop-Location; exit 1 }
if (Test-Path "node_modules/.bin/esbuild") {
    Write-Info "Approving pending npm scripts (esbuild postinstall)..."
    npm approve-scripts --allow-scripts-pending
} else {
    Write-Warn "esbuild binary not found – skipping approve‑scripts step."
}
Pop-Location

# -------------------------------------------------
# 6️⃣ Launch the Vite dev server in background
# -------------------------------------------------
Write-Info "Starting Vite dev server (http://localhost:5173)..."
Start-Process powershell -ArgumentList @(
    "-NoExit",
    "-Command",
    "Set-Location '$PWD\dashboard'; `$env:VITE_PROXY_TARGET='http://localhost:8000'; npm run dev"
) -WindowStyle Normal

# -------------------------------------------------
# 7️⃣ Build & start Docker‑Compose stack (backend + renderer)
# -------------------------------------------------
Write-Info "Building and launching Docker‑Compose services..."
docker compose up --build -d
if ($LASTEXITCODE -ne 0) { Write-Error "docker compose failed – see the console output above."; exit 1 }
Write-Info "Docker‑Compose services are up."

# -------------------------------------------------
# 8️⃣ Final summary & FAQ
# -------------------------------------------------
Write-Host @"
===== OpenShorts is ready! =====

UI (dev)            : http://localhost:5173
UI (Docker)         : http://localhost:5175   (production-style container)
FastAPI backend     : http://localhost:8000/docs
Remotion renderer   : http://localhost:3100

Open the UI, go to Settings -> API Keys, paste your Gemini key (and any other keys you need), then start a Clip job.

If you need to stop everything later:
   docker compose down   # stop containers
   Close the Vite PowerShell window (or press Ctrl-C).

--- Common troubleshooting ---
Docker daemon fails – ensure WSL 2 integration is enabled in Docker Desktop (Settings -> Resources -> WSL Integration).
Port 8000 already in use – stop the conflicting process or change BACKEND_PORT in .env and restart.
FFmpeg not found – install via winget install ffmpeg or add its folder to PATH.

Happy clipping! 🎬
"@ -ForegroundColor Green
