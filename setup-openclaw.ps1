# ---------------------------------------------------------------------------
# setup-openclaw.ps1 — Install OpenClaw in Docker from scratch
#
# What this does:
#   1. Clones OpenClaw source + copies secure docker-compose.yml
#   2. Creates config directory and workspace volume
#   3. Builds the Docker image from source
#   4. Configures gateway, sets model, starts containers
#   5. Enables Control UI access and browser automation
#
# After this script: run Copilot auth (the only interactive step)
#   cd openclaw-repo
#   docker compose run --rm openclaw-cli models auth login-github-copilot
#
# Usage:
#   .\setup-openclaw.ps1
# ---------------------------------------------------------------------------

$ErrorActionPreference = "Stop"

Write-Host "`n=== Step 1/5: Cloning OpenClaw source ===" -ForegroundColor Cyan

if (Test-Path "openclaw-repo") {
    Write-Host "  openclaw-repo/ already exists, skipping clone"
} else {
    git clone https://github.com/openclaw/openclaw openclaw-repo
    if ($LASTEXITCODE -ne 0) { throw "Git clone failed" }
}

Set-Location openclaw-repo

# Copy docker-compose.yml from our repo (parent directory) into the OpenClaw source
Copy-Item -Path "..\docker-compose.yml" -Destination "docker-compose.yml" -Force
Write-Host "  docker-compose.yml copied"

Write-Host "`n=== Step 2/5: Preparing storage ===" -ForegroundColor Cyan

# Config directory
$openclawHome = "$env:USERPROFILE\.openclaw"
New-Item -ItemType Directory -Path $openclawHome -Force | Out-Null
Write-Host "  Config dir: $openclawHome"

# Workspace volume
docker volume create openclaw-workspace | Out-Null
docker run --rm -v openclaw-workspace:/workspace alpine chown -R 1000:1000 /workspace 2>$null
Write-Host "  Workspace volume: openclaw-workspace (permissions fixed)"

Write-Host "`n=== Step 3/5: Building Docker image ===" -ForegroundColor Cyan
Write-Host "  This takes ~5-10 minutes..."

docker build -t openclaw:local -f Dockerfile .
if ($LASTEXITCODE -ne 0) { throw "Docker build failed" }

Write-Host "`n=== Step 4/5: Configuring gateway ===" -ForegroundColor Cyan

# Non-interactive onboard — token auto-generated and saved to config
docker compose run --rm openclaw-cli onboard `
    --non-interactive `
    --accept-risk `
    --mode local `
    --flow manual `
    --auth-choice skip `
    --gateway-port 18789 `
    --gateway-bind lan `
    --gateway-auth token `
    --skip-channels `
    --skip-skills `
    --skip-daemon `
    --skip-health

# Set default model
docker compose run --rm openclaw-cli models set github-copilot/claude-opus-4.6

Write-Host "`n=== Step 5/5: Starting gateway ===" -ForegroundColor Cyan

docker compose up -d

# Wait for gateway to start
Start-Sleep -Seconds 5

# Enable Control UI token access
docker compose exec openclaw-gateway node dist/index.js config set gateway.controlUi.allowInsecureAuth true
docker compose restart openclaw-gateway

Start-Sleep -Seconds 5

# Configure browser automation
docker compose exec openclaw-gateway node dist/index.js config set browser.enabled true
docker compose exec openclaw-gateway node dist/index.js config set browser.defaultProfile docker
docker compose exec openclaw-gateway node dist/index.js config set browser.profiles.docker '{"cdpUrl": "http://openclaw-browser:3000", "color": "#00AA00"}'
docker compose restart openclaw-gateway

# Read the auto-generated token from config
$GatewayToken = docker compose exec openclaw-gateway node dist/index.js config get gateway.auth.token 2>$null | Select-String -Pattern '^[0-9a-f]+$' | ForEach-Object { $_.Line.Trim() }

Write-Host "`n=== Setup complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "  GATEWAY TOKEN: $GatewayToken" -ForegroundColor Yellow
Write-Host ""
Write-Host "Control UI: http://127.0.0.1:18789/?token=$GatewayToken"
Write-Host ""
Write-Host "=== One manual step remaining: GitHub Copilot auth ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Run:" -ForegroundColor Yellow
Write-Host "   docker compose run --rm openclaw-cli models auth login-github-copilot" -ForegroundColor White
Write-Host "   (open browser, enter code, authorize)"
Write-Host ""
Write-Host "2. Open Control UI:" -ForegroundColor Yellow
Write-Host "   http://127.0.0.1:18789/?token=$GatewayToken"
