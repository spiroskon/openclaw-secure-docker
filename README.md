# OpenClaw: Secure Docker Setup on Windows

OpenClaw has 200K+ GitHub stars. Most users run `curl -fsSL https://openclaw.bot/install.sh | bash` and move on. Here are four things that meaningfully improve your security posture — all officially supported but often overlooked.

## The Security Context

Recent security research found:
- [1,800+ exposed OpenClaw instances on Shodan](https://www.theregister.com/2026/01/27/clawdbot_moltbot_security_concerns/) with leaked API keys and chat histories
- [One-click RCE vulnerability](https://depthfirst.com/post/1-click-rce-to-steal-your-moltbot-data-and-keys) via WebSocket hijacking (patched, but default install had full system access)
- [Malicious skills](https://www.aikido.dev/blog/fake-clawdbot-vscode-extension-malware) executing arbitrary code with zero user awareness

The default native install gives OpenClaw full access to your filesystem. If the model hallucinates a dangerous command or a skill is compromised, there's no barrier.

These four practices limit the blast radius.

## Prerequisites

- **Docker Desktop** with Docker Compose v2
- **GitHub Copilot subscription** (for model access)
- **Git** for cloning the repository
- **Windows 10/11** with WSL2

Verified versions: Docker 29.1.5, Docker Compose v5.0.1.

---

## 1. Docker Setup Exists (Use It)

**What most users miss:** OpenClaw has official Docker support. Most blindly use the one-liner native install.

**Why it matters:** Container isolation means if something goes wrong, the damage is contained to the container — not your entire system.

**Official docs:** [docs/install/docker.md](https://docs.openclaw.ai/install/docker)

### Step 1: Clone the OpenClaw Source and Get the Secure Docker Config

This guide uses two things: the OpenClaw source code (for building the Docker image) and the `docker-compose.yml` from this repository (for the secure volume setup). Clone both:

```powershell
# Clone the OpenClaw source (contains Dockerfile)
git clone https://github.com/openclaw/openclaw openclaw-repo

# Download the secure docker-compose.yml and .env template into the repo
cd openclaw-repo
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/spiroskon/openclaw-secure-docker/master/docker-compose.yml" -OutFile docker-compose.yml
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/spiroskon/openclaw-secure-docker/master/.env.example" -OutFile .env.example
```

> **What this does:** You now have the OpenClaw source + Dockerfile from the official repo, plus our `docker-compose.yml` with workspace volume isolation and the `openclaw-cli` service. All commands from here run inside `openclaw-repo/`.

### Step 2: Create Config Directory and Workspace Volume

OpenClaw needs two things on the host: a config directory (bind-mounted, editable from Windows) and a Docker volume for the workspace (isolated — see [Section 4](#4-add-workspace-volume-isolation)).

```powershell
# Config directory on your Windows filesystem
$openclaw_home = "$env:USERPROFILE\.openclaw"
New-Item -ItemType Directory -Path $openclaw_home -Force

# Isolated workspace volume (Docker storage, not your filesystem)
docker volume create openclaw-workspace

# Fix volume permissions — container runs as user 'node' (UID 1000), not root
docker run --rm -v openclaw-workspace:/workspace alpine chown -R 1000:1000 /workspace
```

### Step 3: Create the `.env` File

Create a `.env` file in the repository root:

```powershell
@"
OPENCLAW_CONFIG_DIR=C:/Users/$env:USERNAME/.openclaw
OPENCLAW_GATEWAY_TOKEN=
"@ | Out-File -FilePath .env -Encoding utf8
```

> **Note:** Uses forward slashes for Docker compatibility. The `$env:USERNAME` fills in automatically.

### Step 4: Build the Docker Image

```powershell
docker build -t openclaw:local -f Dockerfile .
```

This takes approximately 5-10 minutes depending on your internet connection.

### Step 5: Run Onboarding + GitHub Copilot Auth

One command configures everything — gateway settings, workspace, and GitHub Copilot authentication:

```powershell
docker compose run --rm openclaw-cli onboard `
  --non-interactive `
  --accept-risk `
  --mode local `
  --flow manual `
  --auth-choice github-copilot `
  --gateway-port 18789 `
  --gateway-bind lan `
  --gateway-auth token `
  --skip-channels `
  --skip-skills `
  --skip-daemon `
  --skip-health
```

During this step, the GitHub Copilot device flow will start:
1. The terminal shows a URL and a one-time code
2. Open `https://github.com/login/device` in your browser
3. Enter the code and authorize the application
4. Return to the terminal — it completes automatically

> **Important:** Keep the terminal open until authorization completes.

> **Note:** The wizard may show a gateway connection error at the end — this is expected. The gateway isn't running yet (that's Step 7). The config and auth tokens were written successfully.

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
| Model/auth provider | **GitHub Copilot** | Device flow runs inline |
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

#### Save the Generated Token

At the end of onboarding, the wizard displays a gateway token. **Save this token** — you'll need it for the `.env` file and browser access.

### Step 6: Set the Default Model

```powershell
docker compose run --rm openclaw-cli models set github-copilot/claude-opus-4.6
```

> **Gotcha**: Model IDs use dots not hyphens: `claude-opus-4.6` works, `claude-opus-4-6` gives "Unknown model".

### Step 7: Update `.env` with Generated Token

```powershell
@"
OPENCLAW_CONFIG_DIR=C:/Users/$env:USERNAME/.openclaw
OPENCLAW_GATEWAY_TOKEN=<PASTE_YOUR_TOKEN_HERE>
"@ | Out-File -FilePath .env -Encoding utf8
```

### Step 8: Start the Gateway

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

### Step 9: Enable Insecure Auth for HTTP Access

This step is **required** when running in Docker on Windows. Without it, the Control UI will show "disconnected (1008): pairing required".

```powershell
docker compose exec openclaw-gateway node dist/index.js config set gateway.controlUi.allowInsecureAuth true
docker compose restart openclaw-gateway
```

**Why:** When accessing `http://127.0.0.1:18789/` from Windows, the gateway sees the connection coming from the Docker bridge network, not localhost. This setting allows token-only authentication over HTTP.

### Step 10: Access the Control UI

Open in your browser:

```
http://127.0.0.1:18789/?token=<YOUR_GENERATED_TOKEN>
```

### Step 11: Configure Browser Automation

```powershell
docker compose exec openclaw-gateway node dist/index.js config set browser.enabled true
docker compose exec openclaw-gateway node dist/index.js config set browser.defaultProfile docker
docker compose exec openclaw-gateway node dist/index.js config set browser.profiles.docker '{"cdpUrl": "http://openclaw-browser:3000", "color": "#00AA00"}'
docker compose restart openclaw-gateway
```

**Watch the browser live:** Open http://localhost:3000 — the Browserless debugger UI shows active sessions.

---

## 2. Run the Security Audit (Most Don't Know This Exists)

**What most users miss:** OpenClaw has a built-in security audit command. It's documented but buried.

**Why it matters:** It catches misconfigurations, permission issues, and attack surface problems.

```bash
# Inside the container (Docker setup)
docker compose exec openclaw-gateway node dist/index.js security audit

# Options
# --deep  — more thorough scan
# --fix   — auto-fix some issues
```

**Example output:**
```
Summary: 2 critical · 1 warn · 1 info

CRITICAL
- gateway.control_ui.insecure_auth: allowInsecureAuth=true
- fs.state_dir.perms_world_writable: /home/node/.openclaw mode=777

WARN
- browser.remote_cdp_http: Remote CDP uses HTTP

INFO
- Attack surface summary: groups=0, tools.elevated=enabled
```

Run this after every install. Understand the findings. Fix what matters for your environment.

---

## 3. Use GitHub Copilot as Your Model Provider

**What most users miss:** GitHub Copilot isn't just for code completion — it's an LLM API provider that works with OpenClaw out of the box.

| Concern | Typical Providers | GitHub Copilot |
|---------|-------------------|----------------|
| Trust | Various companies, unclear data handling | Microsoft/GitHub, enterprise-grade |
| Credentials | Long-lived API keys (easy to leak) | OAuth refresh tokens |
| Model access | Pay each provider separately | One subscription, multiple frontier models |
| Enterprise | Often not approved | Already in many enterprises |

**Available models:** Claude (Anthropic), GPT-4 (OpenAI), and others — all through one GitHub subscription.

**Setup:** Handled automatically in [Step 5](#step-5-run-onboarding--github-copilot-auth) via `--auth-choice github-copilot`. The device flow runs inline — a browser opens, you complete the OAuth flow, done. Tokens refresh automatically.

---

## 4. Add Workspace Volume Isolation

OpenClaw stores two kinds of data inside the container, both under `/home/node/.openclaw`:

| Path | Contains | Needs host access? |
|------|----------|-------------------|
| `/home/node/.openclaw/` | Config (`openclaw.json`), credentials, auth tokens, sessions | **Yes** — you need to edit config from Windows |
| `/home/node/.openclaw/workspace/` | Agent's working files — persona, memory, notes, generated content | **No** — only the agent uses these |

**What the official docs do:** Bind-mount both to your host filesystem. The agent reads and writes directly to your Windows disk.

**What we do instead:** Two mounts — a bind mount for config (so you can edit it), and a **Docker named volume** for the workspace (so the agent's writes stay inside Docker):

```yaml
volumes:
  - ${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw          # bind mount → your Windows disk
  - openclaw-workspace:/home/node/.openclaw/workspace    # named volume → Docker storage
```

The named volume **shadows** the workspace path inside the bind mount. Docker resolves the more specific mount first, so `/home/node/.openclaw/workspace` points to the isolated Docker volume, while everything else under `/home/node/.openclaw/` (config, credentials, sessions) remains on your Windows filesystem.

**What's in the workspace** — the onboarding wizard seeds these files, and the agent reads them every session ([workspace docs](https://docs.openclaw.ai/concepts/agent-workspace)):

| File | Purpose |
|------|---------|
| `SOUL.md` | Persona, tone, and boundaries |
| `USER.md` | Who the user is and how to address them |
| `IDENTITY.md` | Agent's name, vibe, and emoji |
| `AGENTS.md` | Operating instructions and how to use memory |
| `TOOLS.md` | Notes about local tools and conventions |
| `HEARTBEAT.md` | Optional checklist for heartbeat runs |
| `memory/` | Daily memory log (`YYYY-MM-DD.md`), one file per day |

**Setup:**
```bash
docker volume create openclaw-workspace
```

The `docker-compose.yml` in this repository already uses this pattern. See [COMPARISON.md](COMPARISON.md) for the full Docker vs native security comparison.

**Tradeoff:** To access workspace files, you need `docker compose exec`:
```bash
docker compose exec openclaw-gateway ls /home/node/.openclaw/workspace
docker compose exec openclaw-gateway cat /home/node/.openclaw/workspace/SOUL.md
```

**Backup:**
```bash
docker run --rm -v openclaw-workspace:/data -v ~/backup:/backup alpine cp -a /data /backup
```

---

## Verification Checklist

After setup, verify:

```bash
# Containers running
docker compose ps

# Security audit
docker compose exec openclaw-gateway node dist/index.js security audit

# GitHub Copilot authenticated
docker compose exec openclaw-gateway node dist/index.js models status

# Workspace is volume (not bind mount)
docker compose exec openclaw-gateway stat -f /home/node/.openclaw/workspace
```

---

## What This Doesn't Protect Against

Be honest about limitations:

| Risk | Status | Notes |
|------|--------|-------|
| Prompt injection | ❌ Inherent | Industry-wide unsolved. No setup prevents it. |
| Data exfiltration | ❌ Inherent | Agent has network access by design. |
| Credential theft (if host compromised) | ❌ Inherent | Config is bind-mounted for editing. |
| Container escape | ⚠️ Unlikely | Containers aren't a security boundary, but raise the bar. |

This setup limits blast radius and adds defense in depth. It doesn't make OpenClaw "secure" in an absolute sense.

---

## Persistent Storage

All OpenClaw data is stored on your Windows PC through Docker volume mounts.

### Volume Mappings

| Container Path | Host Path |
|----------------|-----------|
| `/home/node/.openclaw` | `C:\Users\<USER>\.openclaw` |
| `/home/node/.openclaw/workspace` | Docker volume `openclaw-workspace` |

### What Is Persisted

| Data | Persisted? |
|------|------------|
| Configuration & token | ✅ Yes |
| Chat sessions | ✅ Yes |
| GitHub Copilot auth | ✅ Yes |
| Channel credentials | ✅ Yes |
| Workspace files | ✅ Yes (in Docker volume) |

---

## Useful Commands

| Command | Description |
|---------|-------------|
| `docker compose up -d` | Start all services (gateway + browser) |
| `docker compose down` | Stop all services |
| `docker compose restart openclaw-gateway` | Restart the gateway |
| `docker compose logs -f openclaw-gateway` | Follow gateway logs |
| `docker compose run --rm openclaw-cli <command>` | Run CLI commands |
| `docker compose exec openclaw-gateway node dist/index.js security audit` | Run security audit |

---

## Quick Reference

| Practice | Command/Action |
|----------|----------------|
| Use Docker | `./docker-setup.sh` or manual compose |
| Run security audit | `openclaw security audit --deep` |
| Use GitHub Copilot | `openclaw models auth login-github-copilot` |
| Isolate workspace | Named volume for `/home/node/.openclaw/workspace` |

---

## Final Configuration Summary

```json5
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "github-copilot/claude-opus-4.6"
      }
    }
  },
  "gateway": {
    "mode": "local",
    "port": 18789,
    "bind": "lan",
    "auth": {
      "mode": "token",
      "token": "<YOUR_TOKEN>"
    },
    "controlUi": {
      "allowInsecureAuth": true
    }
  },
  "browser": {
    "enabled": true,
    "defaultProfile": "docker",
    "profiles": {
      "docker": {
        "cdpUrl": "http://openclaw-browser:3000",
        "color": "#00AA00"
      }
    }
  }
}
```

---

## Optional: Next Steps

### Web Search (Brave API)

Without this, OpenClaw cannot search the web for current information.

1. Get a free API key at https://brave.com/search/api/
2. Configure:
```powershell
docker compose exec openclaw-gateway node dist/index.js config set tools.web.search.apiKey "YOUR_BRAVE_KEY"
docker compose restart openclaw-gateway
```

### Chat Channels

Add a messaging channel for mobile access. **Telegram** is the fastest:

1. Message [@BotFather](https://t.me/BotFather) on Telegram
2. Create bot with `/newbot`, copy the token
3. Add channel:
```powershell
docker compose exec openclaw-gateway node dist/index.js channels add --channel telegram --token "YOUR_BOT_TOKEN"
```

---

## References

- [OpenClaw Official Docs](https://docs.openclaw.ai)
- [OpenClaw Docker Install](https://docs.openclaw.ai/install/docker)
- [OpenClaw Security Docs](https://docs.openclaw.ai/gateway/security)
- [GitHub Copilot](https://github.com/features/copilot)
- [OpenClaw on Azure Container Apps](https://github.com/spiroskon/openclaw-azure-containerapps) — deploy OpenClaw on Azure

### Security Articles
- [The Register: OpenClaw WebSocket RCE](https://www.theregister.com/2026/01/27/clawdbot_moltbot_security_concerns/)
- [VentureBeat: 1,800 Exposed Instances](https://venturebeat.com/security/clawdbot-exploits-48-hours-what-broke)
- [ZDNET: Malicious Skills](https://www.zdnet.com/article/clawdbot-moltbot-openclaw-security-nightmare/)

---

## License

MIT
