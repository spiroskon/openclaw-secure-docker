# ---------------------------------------------------------------------------
# setup-openclaw.ps1 — Build and configure OpenClaw in Docker
#
# What this does:
#   1. Creates config directory and workspace volume
#   2. Generates a gateway token and writes .env
#   3. Builds the Docker image from source
#   4. Runs non-interactive onboard (gateway config + workspace)
#   5. Sets the default model to GitHub Copilot Claude Opus 4.6
#   6. Starts the gateway and browser containers
#   7. Enables Control UI token access
#
# After this script: run Copilot auth (the only interactive step)
#   docker compose run --rm openclaw-cli models auth login-github-copilot
#
# Usage (from the openclaw-repo directory):
#   .\setup-openclaw.ps1
# ---------------------------------------------------------------------------

$ErrorActionPreference = "Stop"

Write-Host "`n=== Step 1/5: Preparing storage ===" -ForegroundColor Cyan

# Config directory
$openclawHome = "$env:USERPROFILE\.openclaw"
New-Item -ItemType Directory -Path $openclawHome -Force | Out-Null
Write-Host "  Config dir: $openclawHome"

# Workspace volume
docker volume create openclaw-workspace | Out-Null
docker run --rm -v openclaw-workspace:/workspace alpine chown -R 1000:1000 /workspace 2>$null
Write-Host "  Workspace volume: openclaw-workspace (permissions fixed)"

Write-Host "`n=== Step 2/5: Generating token and .env ===" -ForegroundColor Cyan

$bytes = New-Object byte[] 24
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$GatewayToken = [BitConverter]::ToString($bytes).Replace('-', '').ToLower()

$configDir = $openclawHome.Replace('\', '/')
@"
OPENCLAW_CONFIG_DIR=$configDir
OPENCLAW_GATEWAY_TOKEN=$GatewayToken
"@ | Set-Content -Path .env -Encoding utf8

Write-Host "  Token generated and saved to .env"

Write-Host "`n=== Step 3/5: Building Docker image ===" -ForegroundColor Cyan
Write-Host "  This takes ~5-10 minutes..."

docker build -t openclaw:local -f Dockerfile .
if ($LASTEXITCODE -ne 0) { throw "Docker build failed" }

Write-Host "`n=== Step 4/5: Configuring gateway ===" -ForegroundColor Cyan

# Non-interactive onboard with pre-generated token
docker compose run --rm openclaw-cli onboard `
    --non-interactive `
    --accept-risk `
    --mode local `
    --flow manual `
    --auth-choice skip `
    --gateway-port 18789 `
    --gateway-bind lan `
    --gateway-auth token `
    --gateway-token $GatewayToken `
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

Write-Host "`n=== Setup complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "  ┌─────────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
Write-Host "  │  GATEWAY TOKEN:                                                │" -ForegroundColor Yellow
Write-Host "  │  $GatewayToken                          │" -ForegroundColor Yellow
Write-Host "  └─────────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
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
