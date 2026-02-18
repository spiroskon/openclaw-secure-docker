# OpenClaw Secure Docker Setup - Smoke Test Results

**Date:** 2026-02-18
**Environment:** Windows 11, Docker 29.2.1, Docker Compose v5.0.2
**Host:** spkonsta

---

## Summary

| Step | Status | Notes |
|------|--------|-------|
| Prerequisites | PASS | Docker 29.2.1, Compose v5.0.2 |
| Step 1: Clone repo | PASS (with caveat) | See Issue #1 |
| Step 2: Config dir + volume | PASS (with fix) | See Issue #2 |
| Step 3: Create .env | PASS | |
| Step 4: Build Docker image | PASS | Built from openclaw-repo Dockerfile |
| Step 5: Run onboarding wizard | PASS (with workaround) | See Issues #3, #4, #5 |
| Step 6: Update .env with token | PASS | |
| Step 7: Start gateway | PASS | Both containers up |
| Step 8: GitHub Copilot auth | SKIPPED | Requires interactive browser OAuth flow |
| Step 9: Enable insecure auth | PASS | |
| Step 10: Access Control UI | NOT TESTED | Requires browser |
| Step 11: Configure browser automation | PASS | |
| Security audit | PASS | 2 critical, 2 warn, 1 info (expected) |

---

## Issues Encountered

### Issue #1 - Step 1: README does not mention this repository

**Problem:** The README Step 1 says to clone `https://github.com/openclaw/openclaw` into `openclaw-repo`. However, the `openclaw-secure-docker` repository (which contains the `docker-compose.yml` and `.env.example`) is a separate repo. The README does not clarify the relationship between the two repos or instruct the user to also clone `openclaw-secure-docker`.

**What the user actually needs:**
1. Clone `openclaw-secure-docker` (for `docker-compose.yml`, `.env.example`, docs)
2. Clone `openclaw/openclaw` separately (for the `Dockerfile` to build the image)

**Resolution:** Cloned the app repo into `c:\Code\openclaw-repo` and ran `docker build` from there, then used the `docker-compose.yml` from this repo (`openclaw-secure-docker`).

**Suggestion:** Add a note in Step 1 clarifying that the Dockerfile comes from the main openclaw repo, while `docker-compose.yml` comes from this repo.

---

### Issue #2 - Step 2: PowerShell `$env:USERPROFILE` fails in Git Bash

**Problem:** The documented PowerShell command:
```powershell
$openclaw_home = "$env:USERPROFILE\.openclaw"
New-Item -ItemType Directory -Path $openclaw_home -Force
```
When executed via `powershell -Command "..."` from Git Bash, the `$env:USERPROFILE` variable is consumed by the bash shell before reaching PowerShell, resulting in:
```
New-Item : The given path's format is not supported.
```

**Resolution:** Used single quotes to prevent bash variable expansion:
```bash
powershell -Command 'New-Item -ItemType Directory -Path "$env:USERPROFILE\.openclaw" -Force'
```

**Note:** This is only an issue when running PowerShell commands from a bash shell (e.g., Git Bash, WSL). Running directly in PowerShell would work as documented.

---

### Issue #3 - Step 5: Onboarding wizard requires interactive TTY

**Problem:** The command `docker compose run --rm openclaw-cli onboard` launches an interactive TUI wizard that requires arrow-key navigation and keyboard input. This cannot be automated or scripted without TTY support.

**Resolution:** Used the undocumented `--non-interactive` flag with `--accept-risk`:
```bash
docker compose run --rm openclaw-cli onboard \
  --non-interactive \
  --accept-risk \
  --gateway-bind lan \
  --gateway-port 18789 \
  --gateway-auth token \
  --skip-channels \
  --skip-skills
```

**Suggestion:** Document the `--non-interactive` mode for headless/automated deployments.

---

### Issue #4 - Step 5: Workspace volume permission denied (EACCES)

**Problem:** First onboarding attempt failed with:
```
Error: EACCES: permission denied, open '/home/node/.openclaw/workspace/AGENTS.md'
```

The `openclaw-workspace` Docker volume was created with root ownership, but the container runs as user `node` (UID 1000). The Dockerfile sets `USER node` for security hardening, but newly created Docker volumes default to root ownership.

**Resolution:** Fixed permissions on the volume before retrying:
```bash
MSYS_NO_PATHCONV=1 docker run --rm -v openclaw-workspace:/workspace alpine chown -R 1000:1000 /workspace
```

**Note:** The `MSYS_NO_PATHCONV=1` prefix is needed on Git Bash for Windows to prevent path mangling (`/workspace` would otherwise be converted to `C:/Program Files/Git/workspace`).

**Suggestion:** Add a note in Step 2 after `docker volume create openclaw-workspace` to fix permissions:
```bash
docker run --rm -v openclaw-workspace:/workspace alpine chown -R 1000:1000 /workspace
```

---

### Issue #5 - Step 5: Onboarding reports gateway connection error at end

**Problem:** After successfully writing config and workspace files, the non-interactive onboarding exits with:
```
Error: gateway closed (1006 abnormal closure (no close frame)): no close reason
Gateway target: ws://172.19.0.2:18789
```

**Resolution:** This is a non-blocking error. The onboarding tries to verify the gateway is running, but the gateway hasn't been started yet (that's Step 7). The config files were written successfully and the gateway starts fine in Step 7. Exit code is 1, but the setup is functional.

**Suggestion:** The README should note that this error at the end of onboarding is expected and can be ignored.

---

### Issue #6 - Step 4: Dockerfile entrypoint mismatch with docker-compose.yml

**Problem:** The Dockerfile's default CMD uses:
```dockerfile
CMD ["node", "openclaw.mjs", "gateway", "--allow-unconfigured"]
```
But the `docker-compose.yml` command uses:
```yaml
command: ["node", "dist/index.js", "gateway", "--bind", "lan", "--port", "18789"]
```

Both `openclaw.mjs` and `dist/index.js` appear to work, but this inconsistency could cause confusion if users try to run commands from the README examples (which use `dist/index.js`) against a container that only has `openclaw.mjs`.

**Resolution:** No action needed — both entry points exist in the built image. The docker-compose.yml override takes precedence.

---

### Issue #7 - Step 8: GitHub Copilot auth requires interactive browser flow

**Problem:** Step 8 (`docker compose exec openclaw-gateway node dist/index.js models auth login-github-copilot`) initiates a device code OAuth flow that requires opening a browser and entering a code at `https://github.com/login/device`. This cannot be completed non-interactively.

**Resolution:** Skipped this step. The gateway runs without a model provider configured. Users must complete this step manually in a terminal with browser access.

---

## Verification Checklist Results

```
Containers running:         PASS
  - openclaw-gateway:       Up (ports 18789-18790)
  - openclaw-browser:       Up (port 3000)

Security audit:             PASS (2 critical, 2 warn, 1 info - expected)
  - CRITICAL: allowInsecureAuth=true (intentional for Docker HTTP)
  - CRITICAL: state dir mode=777 (Docker volume default)
  - WARN: no auth rate limiting
  - WARN: CDP uses HTTP (expected for internal Docker network)

GitHub Copilot auth:        SKIPPED (requires interactive OAuth)

Workspace volume mounted:   PASS
  Files present: AGENTS.md, BOOTSTRAP.md, HEARTBEAT.md,
                 IDENTITY.md, SOUL.md, TOOLS.md, USER.md

Config file:                PASS
  Location: C:\Users\spkonsta\.openclaw\openclaw.json
  Token generated and saved to .env
```

---

## Final State

The OpenClaw gateway is running in Docker with:
- Gateway accessible at `http://127.0.0.1:18789/?token=4463b68e1c86b3f5b5a7659f002849948f16f04ef29a9b86`
- Browserless Chrome at `http://localhost:3000`
- Workspace isolated in Docker volume `openclaw-workspace`
- Config bind-mounted from `C:\Users\spkonsta\.openclaw`
- Browser automation configured with CDP profile
- No model provider configured (GitHub Copilot auth requires manual completion)
