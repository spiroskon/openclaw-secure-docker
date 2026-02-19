# OpenClaw: Secure Docker Setup on Windows

Install [OpenClaw](https://github.com/openclaw/openclaw) on Windows with Docker, workspace volume isolation, and GitHub Copilot as the LLM provider.

OpenClaw is an open-source AI agent that runs 24/7 — it can browse the web, execute tasks, manage files, and communicate through multiple channels. This guide runs it inside Docker with an isolated workspace volume, so the agent can't write directly to your filesystem.

## Who This Guide Is For

- Developers running OpenClaw on a Windows workstation
- Teams that want safer local experimentation before cloud deployment
- Engineers who already have Docker Desktop and GitHub Copilot access

## Time to Complete

- Quick Start path: **10-15 minutes**
- Manual path (with explanations): **20-35 minutes**

## What Success Looks Like

By the end of this guide, you should be able to:

- Start OpenClaw in Docker with workspace isolation enabled
- Authenticate GitHub Copilot as the model provider
- Open the Control UI with a valid token
- Run `security audit` and understand expected findings

## Prerequisites

- **Docker Desktop** with Docker Compose v2
- **GitHub Copilot subscription** (for model access)
- **Git**
- **Windows 10/11** with WSL2

---

## Quick Start (Recommended)

```powershell
# 0. Clone this repo
git clone https://github.com/spiroskon/openclaw-secure-docker.git
cd openclaw-secure-docker

# 1. Run setup script (~10-15 min) — clones OpenClaw source, builds image, configures gateway
.\setup-openclaw.ps1

# 2. GitHub Copilot auth (only interactive step — opens browser)
#    The setup script created openclaw-repo/ and ran from inside it,
#    but your shell is still in openclaw-secure-docker/.
cd openclaw-repo
docker compose run --rm openclaw-cli models auth login-github-copilot

# 3. Open Control UI (token shown in script output)
# http://127.0.0.1:18789/?token=<your-token>
```

### Quick verification

```powershell
cd openclaw-repo
docker compose ps
docker compose exec openclaw-gateway node openclaw.mjs model status
docker compose exec openclaw-gateway node openclaw.mjs security audit
```

You should see both containers `Up`, a configured `github-copilot/claude-opus-4.6` model, and a security audit summary.

---

## Manual Installation (Step by Step)

If you prefer to run each step individually, or the script doesn't work in your environment:

### Step 1: Clone This Repo and the OpenClaw Source

```powershell
git clone https://github.com/spiroskon/openclaw-secure-docker.git
cd openclaw-secure-docker
git clone https://github.com/openclaw/openclaw openclaw-repo
cd openclaw-repo
Copy-Item -Path "..\docker-compose.yml" -Destination "docker-compose.yml"
```

> **What this does:** Our repo has the secure `docker-compose.yml`. The OpenClaw repo has the Dockerfile and source code. The `Copy-Item` puts our compose file into the OpenClaw source directory where `docker build` and `docker compose` run.

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

### Step 8: Enable Insecure Auth for HTTP Access (Initial Setup)

This simplifies initial setup by allowing token-only authentication for the Control UI. Without it, the browser shows "disconnected (1008): pairing required" and you'd need to approve the device via CLI before accessing the UI.

```powershell
docker compose exec openclaw-gateway node openclaw.mjs config set gateway.controlUi.allowInsecureAuth true
docker compose restart openclaw-gateway
```

**Why:** When accessing `http://127.0.0.1:18789/` from Windows, the gateway sees the connection coming from the Docker bridge network, not localhost. This setting bypasses device identity so the Control UI works immediately with just the token.

After verifying everything works, you can harden this — see [Optional: Enable Device Pairing](#optional-enable-device-pairing).

### Step 9: Access the Control UI

Get your auto-generated gateway token:

```powershell
docker compose exec openclaw-gateway node openclaw.mjs config get gateway.auth.token
```

Open in your browser:

```
http://127.0.0.1:18789/?token=<TOKEN_FROM_ABOVE>
```

### Step 10: Configure Browser Automation

```powershell
docker compose exec openclaw-gateway node openclaw.mjs config set browser.enabled true
docker compose exec openclaw-gateway node openclaw.mjs config set browser.defaultProfile docker
docker compose exec openclaw-gateway node openclaw.mjs config set browser.profiles.docker '{"cdpUrl": "http://openclaw-browser:3000", "color": "#00AA00"}'
docker compose restart openclaw-gateway
```

**Watch the browser live:** Open http://localhost:3000 — the Browserless debugger UI shows active sessions.

---

## Post-Install: Run the Security Audit

OpenClaw has a built-in security scanner. Run it after setup:

```powershell
docker compose exec openclaw-gateway node openclaw.mjs security audit
```

Expected output: `2 critical · 1 warn · 1 info`:

| Finding | Severity | Verdict |
|---------|----------|---------|
| `allowInsecureAuth` enabled | CRITICAL | **Temporary** — needed for initial setup; removable via [device pairing](#optional-enable-device-pairing) |
| State dir world-writable (777) | CRITICAL | **Cosmetic** — Docker named volume appears as 777; actual files are owned by `node` user (uid 1000) with correct permissions |
| No auth rate limiting | WARN | **Accepted** — 256-bit token; brute force infeasible |

All findings are expected for a Docker setup and do not indicate actual security issues.

If you complete the [device pairing](#optional-enable-device-pairing) step below, the `allowInsecureAuth` finding goes away.

---

## Optional: Enable Device Pairing

After verifying everything works, you can disable `allowInsecureAuth` and use proper device pairing instead. This removes the critical audit finding and enables cryptographic device identity for the Control UI.

The trick: CLI commands that talk to the gateway (like `devices list`) need `--url ws://127.0.0.1:18789 --token <TOKEN>` to connect via loopback inside the container. Without this, the CLI connects via the Docker bridge IP and gets rejected.

```powershell
# 1. Get your gateway token
$TOKEN = docker compose exec openclaw-gateway node openclaw.mjs config get gateway.auth.token

# 2. Disable insecure auth
docker compose exec openclaw-gateway node openclaw.mjs config set gateway.controlUi.allowInsecureAuth false
docker compose restart openclaw-gateway

# 3. Open/refresh browser — you'll see "pairing required"
#    This creates a pending device request

# 4. Approve the browser device (via loopback inside the container)
docker compose exec openclaw-gateway node openclaw.mjs devices approve --latest --url ws://127.0.0.1:18789 --token $TOKEN

# 5. Refresh browser — should connect. Device is now paired.
```

**If something goes wrong**, re-enable insecure auth:

```powershell
docker compose exec openclaw-gateway node openclaw.mjs config set gateway.controlUi.allowInsecureAuth true
docker compose restart openclaw-gateway
```

> **Note:** Clearing browser data or switching browsers requires re-pairing (repeat steps 3-4).

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
| `docker compose exec openclaw-gateway node openclaw.mjs security audit` | Security audit |

---

## Optional: Next Steps

### Web Search (Brave API)

```powershell
docker compose exec openclaw-gateway node openclaw.mjs config set tools.web.search.apiKey "YOUR_BRAVE_KEY"
docker compose restart openclaw-gateway
```

Get a free key at https://brave.com/search/api/

### Chat Channels (Telegram)

```powershell
docker compose exec openclaw-gateway node openclaw.mjs channels add --channel telegram --token "YOUR_BOT_TOKEN"
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

## Tested With

| Component | Version |
|-----------|--------|
| OpenClaw | Latest from `main` branch (Feb 2026) |
| Docker Desktop | 4.x with Docker Compose v2 |
| Windows | 10/11 with WSL2 |
| LLM | `github-copilot/claude-opus-4.6` |

---

## License

MIT
