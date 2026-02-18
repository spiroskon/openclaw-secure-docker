# OpenClaw: Secure Docker Setup on Windows

Install [OpenClaw](https://github.com/openclaw/openclaw) on Windows with Docker, workspace volume isolation, and GitHub Copilot as the LLM provider.

## Prerequisites

- **Docker Desktop** with Docker Compose v2
- **GitHub Copilot subscription** (for model access)
- **Git**
- **Windows 10/11** with WSL2

---

## Quick Start (Recommended)

```powershell
# 1. Clone source + download secure Docker config
git clone https://github.com/openclaw/openclaw openclaw-repo
cd openclaw-repo
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/spiroskon/openclaw-secure-docker/master/docker-compose.yml" -OutFile docker-compose.yml
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/spiroskon/openclaw-secure-docker/master/setup-openclaw.ps1" -OutFile setup-openclaw.ps1

# 2. Run setup script (~10-15 min) — builds image, configures everything, starts gateway
.\setup-openclaw.ps1

# 3. GitHub Copilot auth (only interactive step — opens browser)
docker compose run --rm openclaw-cli models auth login-github-copilot

# 4. Open Control UI (token shown in script output)
# http://127.0.0.1:18789/?token=<your-token>
```

That's it. The setup script handles storage, image build, gateway config, model selection, and browser automation.

---

## Manual Installation (Step by Step)

If you prefer to run each step individually, or the script doesn't work in your environment:

### Step 1: Clone the OpenClaw Source and Get the Secure Docker Config

```powershell
git clone https://github.com/openclaw/openclaw openclaw-repo
cd openclaw-repo
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/spiroskon/openclaw-secure-docker/master/docker-compose.yml" -OutFile docker-compose.yml
```

> **What this does:** The OpenClaw source has the Dockerfile. Our `docker-compose.yml` adds workspace volume isolation and the `openclaw-cli` service.

### Step 2: Create Config Directory and Workspace Volume

OpenClaw needs two things on the host: a config directory (bind-mounted, editable from Windows) and a Docker volume for the workspace (isolated — see [How Workspace Volume Isolation Works](#how-workspace-volume-isolation-works)).

```powershell
# Config directory on your Windows filesystem
$openclaw_home = "$env:USERPROFILE\.openclaw"
New-Item -ItemType Directory -Path $openclaw_home -Force

# Isolated workspace volume (Docker storage, not your filesystem)
docker volume create openclaw-workspace

# Fix volume permissions — container runs as user 'node' (UID 1000), not root
docker run --rm -v openclaw-workspace:/workspace alpine chown -R 1000:1000 /workspace
```

### Step 3: Build the Docker Image

```powershell
docker build -t openclaw:local -f Dockerfile .
```

This takes approximately 5-10 minutes depending on your internet connection.

### Step 4: Configure Gateway (Non-Interactive)

```powershell
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
```

This configures the gateway and auto-generates a token (saved to `~/.openclaw/openclaw.json`).

> **Note:** A gateway connection error at the end is expected — the gateway isn't running yet (that's Step 7).

<details>
<summary>Alternative: interactive wizard (if you prefer manual control)</summary>

```powershell
docker compose run --rm openclaw-cli onboard
```

| Prompt | Choose | Notes |
|--------|--------|-------|
| Security warning | **Yes** | |
| Onboarding mode | **Manual** | Full control over configuration |
| Gateway location | **Local (this machine)** | Running in Docker container |
| Model/auth provider | **Skip** | Copilot auth is done separately in Step 6 |
| Gateway port | **Enter** (18789) | Default |
| Gateway bind | **LAN (0.0.0.0)** | **Required for Docker networking** |
| Gateway auth | **Token** | Auto-generated |
| Tailscale exposure | **Off** | Not configured |
| Channels | **Skip** | Can configure later |
| Skills | **Yes** → **Skip** dependencies | Skip all API key prompts |
| Hooks | **Skip for now** | |
| How to hatch | **Do this later** | No model configured yet |
| Zsh completion | **No** | Not needed in container |

</details>

### Step 5: Set the Default Model

```powershell
docker compose run --rm openclaw-cli models set github-copilot/claude-opus-4.6
```

> **Gotcha**: Model IDs use dots not hyphens: `claude-opus-4.6` works, `claude-opus-4-6` gives "Unknown model".

### Step 6: Authenticate GitHub Copilot

```powershell
docker compose run --rm openclaw-cli models auth login-github-copilot
```

The terminal shows a URL and a one-time code:
1. Open `https://github.com/login/device` in your browser
2. Enter the code and authorize the application
3. Return to the terminal — it completes automatically

> **Important:** Keep the terminal open until authorization completes.

### Step 7: Start the Gateway

```powershell
docker compose up -d
```

Verify they're running:

```powershell
docker compose ps
```

Expected output:
```
NAME                               IMAGE                       STATUS         PORTS
openclaw-repo-openclaw-browser-1   browserless/chrome:latest   Up X seconds   3000/tcp
openclaw-repo-openclaw-gateway-1   openclaw:local              Up X seconds   0.0.0.0:18789-18790->18789-18790/tcp
```

### Step 8: Enable Insecure Auth for HTTP Access

This step is **required** when running in Docker on Windows. Without it, the Control UI will show "disconnected (1008): pairing required".

```powershell
docker compose exec openclaw-gateway node dist/index.js config set gateway.controlUi.allowInsecureAuth true
docker compose restart openclaw-gateway
```

**Why:** When accessing `http://127.0.0.1:18789/` from Windows, the gateway sees the connection coming from the Docker bridge network, not localhost. This setting allows token-only authentication over HTTP.

### Step 9: Access the Control UI

Get your auto-generated gateway token:

```powershell
docker compose exec openclaw-gateway node dist/index.js config get gateway.auth.token
```

Open in your browser:

```
http://127.0.0.1:18789/?token=<TOKEN_FROM_ABOVE>
```

### Step 10: Configure Browser Automation

```powershell
docker compose exec openclaw-gateway node dist/index.js config set browser.enabled true
docker compose exec openclaw-gateway node dist/index.js config set browser.defaultProfile docker
docker compose exec openclaw-gateway node dist/index.js config set browser.profiles.docker '{"cdpUrl": "http://openclaw-browser:3000", "color": "#00AA00"}'
docker compose restart openclaw-gateway
```

**Watch the browser live:** Open http://localhost:3000 — the Browserless debugger UI shows active sessions.

---

## Post-Install: Run the Security Audit

OpenClaw has a built-in security scanner. Run it after setup:

```powershell
docker compose exec openclaw-gateway node dist/index.js security audit
```

Expected output: `2 critical · 1 warn · 1 info` — all expected for a Docker setup. See [COMPARISON.md](COMPARISON.md) for details on each finding.

---

## How Workspace Volume Isolation Works

This setup uses two Docker mounts — this is what makes it different from the official Docker guide:

| Mount | Type | Purpose |
|-------|------|---------|
| `~/.openclaw:/home/node/.openclaw` | Bind mount | Config, credentials, sessions — editable from Windows |
| `openclaw-workspace:/home/node/.openclaw/workspace` | Named volume | Agent's workspace files — isolated in Docker storage |

The named volume **shadows** the workspace path inside the bind mount. The agent's writes (persona files, daily memory, generated content) stay inside Docker. Your Windows filesystem is not exposed.

To access workspace files:
```powershell
docker compose exec openclaw-gateway cat /home/node/.openclaw/workspace/SOUL.md
```

To back up:
```powershell
docker run --rm -v openclaw-workspace:/data -v ~/backup:/backup alpine cp -a /data /backup
```

See the [official workspace docs](https://docs.openclaw.ai/concepts/agent-workspace) for the full file layout.

---

## Useful Commands

| Command | Description |
|---------|-------------|
| `docker compose up -d` | Start all services |
| `docker compose down` | Stop all services |
| `docker compose restart openclaw-gateway` | Restart gateway |
| `docker compose logs -f openclaw-gateway` | Follow gateway logs |
| `docker compose run --rm openclaw-cli <command>` | Run CLI commands |
| `docker compose exec openclaw-gateway node dist/index.js security audit` | Security audit |

---

## Optional: Next Steps

### Web Search (Brave API)

```powershell
docker compose exec openclaw-gateway node dist/index.js config set tools.web.search.apiKey "YOUR_BRAVE_KEY"
docker compose restart openclaw-gateway
```

Get a free key at https://brave.com/search/api/

### Chat Channels (Telegram)

```powershell
docker compose exec openclaw-gateway node dist/index.js channels add --channel telegram --token "YOUR_BOT_TOKEN"
```

Create a bot via [@BotFather](https://t.me/BotFather) on Telegram.

---

## References

- [OpenClaw Official Docs](https://docs.openclaw.ai)
- [OpenClaw Docker Install](https://docs.openclaw.ai/install/docker)
- [OpenClaw Security Docs](https://docs.openclaw.ai/gateway/security)
- [GitHub Copilot](https://github.com/features/copilot)
- [OpenClaw on Azure Container Apps](https://github.com/spiroskon/openclaw-azure-containerapps)

---

## License

MIT
