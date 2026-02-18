# Security: Docker vs Native Install

> This compares our Docker + named volume setup against the default "easiest install" that most users run.

## Default Native Install (What Most Users Do)

```bash
# One-liner install
curl -fsSL https://openclaw.bot/install.sh | bash

# Then run wizard
openclaw onboard --install-daemon
```

Or on Windows PowerShell:
```powershell
iwr -useb https://openclaw.ai/install.ps1 | iex
```

**What this does (no Docker):**
- Installs OpenClaw globally via npm
- Runs directly on host OS
- Workspace at `~/.openclaw/workspace` — directly on your filesystem
- All tools (exec, read, write) run on bare metal
- No container isolation whatsoever

---

## Security Comparison

| Aspect | Native Install (Default) | This Docker Setup |
|--------|--------------------------|-------------------|
| Process isolation | ❌ None — runs on host | ✅ Container isolation |
| Workspace isolation | ❌ None — writes to `~/.openclaw/workspace` on host | ✅ Docker named volume |
| Exec/shell commands | ❌ Run directly on host OS | ✅ Run inside container |
| If agent "goes rogue" | ❌ Full access to user's files | ✅ Limited to container + volume |
| Config access | Full access | Bind-mounted (intentional for editing) |
| Complexity | Simple one-liner | Requires Docker + docker-compose |

---

## Why This Matters

Most users running the one-liner install have OpenClaw with **full access to their home directory**. If the model hallucinates a dangerous command or tries to access sensitive files, there's no barrier.

This Docker + named volume setup provides **meaningful isolation** without the complexity of OpenClaw's sandbox feature:

- **Container isolation**: OpenClaw processes can't directly touch Windows
- **Workspace in Docker volume**: Agent's creative writes are contained
- **Config bind-mounted**: You retain easy access to edit settings
- **No Docker socket exposure**: Avoids the sandbox feature's security tradeoff

---

## Issues Reported in Security Articles

| Issue | Default Install | Docker Setup |
|-------|-----------------|--------------|
| One-click RCE via WebSocket | If exploited → full Windows access | If exploited → container only |
| 1,800+ exposed instances (Shodan) | Vulnerable if misconfigured | Token auth, not internet-exposed |
| Leaked API keys via filesystem | Keys in `~/.openclaw/` readable | Config bind-mounted (partial risk) |
| Shell commands on host | `exec` runs on Windows | Runs inside Linux container |
| Arbitrary file read | Agent reads `C:\Users\*` | Container has no access |
| Arbitrary file write | Agent writes anywhere | Writes only to volume |
| Malicious skills | Full system access | Container-contained |
| Prompt injection | Inherent, unsolvable | Inherent, unsolvable |

---

## Summary: Solvable vs Inherent

**Reduced by Docker setup (7):**
1. RCE blast radius → container
2. Shell commands on host → container
3. Arbitrary file read → container
4. Arbitrary file write → volume
5. Exposed instance → token auth, not internet-exposed
6. Malicious skills blast radius → container
7. Untrusted API providers → GitHub Copilot (OAuth, enterprise-grade)

**Inherent to agentic AI (2):**
1. Prompt injection (industry-wide unsolved)
2. Data exfiltration via agent's network access (if you want network features)

---

## Config/Credentials Reality

- Config is still bind-mounted to Windows — credentials and chat history are accessible from the host
- This is a known tradeoff for convenience (you need to edit config)
- OAuth tokens (GitHub Copilot) are better than static API keys but are still stored locally
- The workspace (where the agent writes files daily) is the part we isolate

---

## Conclusion

This setup is a **reasonable middle ground**: isolated where it matters (workspace), accessible where needed (config), and simple to operate.

For the full setup guide, see the [README](README.md).
