# loom-agent-server — install binaries

Public release binaries for **loom-agent-server**. The source code lives in a
separate **private** repository; this repo holds only the installer scripts and
the compiled release assets, so anyone can install without access to the source.

## Install

**macOS / Linux**
```bash
curl -fsSL https://raw.githubusercontent.com/EmpiteHenry/loom-agent-server-dist/main/bootstrap.sh | bash
```

**Windows (PowerShell)**
```powershell
irm https://raw.githubusercontent.com/EmpiteHenry/loom-agent-server-dist/main/install.ps1 | iex
```

The installer detects your OS/CPU, downloads the matching binary from the latest
release here, and runs an interactive setup (port, API key, public URL, autostart
service).

> **Windows note:** the HTTP server runs natively, but agents run inside tmux,
> which Windows lacks. Run the installer inside WSL2 (Ubuntu) for full
> functionality.

---

## Before you start

| Requirement | Notes |
|---|---|
| **`LOOM…` license key** | **Required.** The server verifies it offline and refuses to start without a valid, unexpired key. Get it from your vendor. |
| LLM CLI logged in | `claude` / `codex` / `gemini`, installed **and authenticated** in the same environment that runs the server (i.e. inside Ubuntu on the WSL2 path). |
| Admin rights (Windows) | Needed once, to enable WSL features for the WSL2 path. |
| Internet access | The installer downloads the binary from this repo's GitHub releases. |

---

## Full setup on Windows with WSL2 (recommended — agents work)

The native Windows server can't spawn agents (no `tmux`). For full functionality,
install inside WSL2.

### 1. Install WSL2 + Ubuntu (one-time, needs admin + reboot)

Open **PowerShell as Administrator** and run:

```powershell
wsl --install -d Ubuntu
```

This enables the **Windows Subsystem for Linux** and **Virtual Machine Platform**
features, sets WSL2 as the default, and downloads Ubuntu. **Reboot** when prompted.

> On older Windows 10 builds the in-box `wsl.exe` is the legacy version (it won't
> recognize `wsl --version` / `--status`). `wsl --install -d Ubuntu` still works.
> If `wsl --install` isn't recognized at all, enable the features manually
> (elevated), reboot, then install Ubuntu from the Microsoft Store:
> ```powershell
> dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
> dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
> ```

### 2. First-run Ubuntu setup

Launch **Ubuntu** from the Start menu. On first run it prompts you to create a
**UNIX username and password** (local to WSL — choose anything). Confirm it's
WSL **version 2**:

```powershell
wsl --list --verbose      # VERSION column should read 2
```

### 3. Install an LLM CLI inside Ubuntu (and log in)

> ⚠️ Windows `claude.exe` / `codex.exe` do **not** run inside Linux. Install a CLI
> **inside Ubuntu** and authenticate it there.

Example for Claude Code inside Ubuntu:

```bash
curl -fsSL https://claude.ai/install.sh | bash     # or per official install docs
claude            # run once to log in / authenticate
```

### 4. Run the installer inside Ubuntu

```bash
curl -fsSL https://raw.githubusercontent.com/EmpiteHenry/loom-agent-server-dist/main/bootstrap.sh | bash
```

`bootstrap.sh` (via the bundled `install.sh`) will: detect OS/CPU and download the
matching binary, let you pick the default agent model, choose an install dir and
add it to PATH, **prompt for the `LOOM…` license key** and validate it offline,
generate/reuse the **HMAC API key**, ask for the **port** (default `8080`) and
optional public URL, then optionally set up autostart and a Cloudflare tunnel.

Environment variables understood by `bootstrap.sh`:

| Var | Purpose |
|---|---|
| `VERSION` | Pin a release tag (default: latest) |
| `PORT` | Listen port passed to the installer |
| `PUBLIC_URL` | Externally-reachable origin |
| `ASSUME_YES=1` | Non-interactive, accept defaults |
| `FROM_SOURCE=1` | Build from source (needs Go 1.26+, access to the private source repo) |

### 5. Verify

```bash
curl http://localhost:8080/healthz      # expect 200 / OK
```

---

## Native Windows only (server runs, NO agents)

Use only if you just need the HTTP API. Run the one-liner above; `install.ps1`
will detect arch, download `loom-agent-server-windows-<arch>.exe`, install to
`%LOCALAPPDATA%\Programs\loom-agent-server`, **prompt for the `LOOM…` license key**,
generate/reuse the HMAC API key, ask for port/public URL, and optionally register
a logon scheduled task + Cloudflare tunnel.

Run manually if you skip autostart:

```powershell
$env:LOOM_API_KEY     = Get-Content "$env:USERPROFILE\.loom-api-key"
$env:LOOM_LICENSE_KEY = Get-Content "$env:USERPROFILE\.loom-agent-server\license"
& "$env:LOCALAPPDATA\Programs\loom-agent-server\loom-agent-server.exe" serve --dev --port 8080
```

> **Limitation:** agent-spawning needs `tmux`, which native Windows lacks. The HTTP
> server runs, but creating agents will not work here. Use the WSL2 path for that.

---

## Key files & runtime env

| Path | What |
|---|---|
| `~/.loom-agent-server/license` | License key |
| `~/.loom-agent-server/installer.conf` | `LOOM_DEFAULT_MODEL=…` |
| `~/.loom-api-key` | HMAC API key (share with web/iOS clients as `Authorization: Bearer <key>`) |
| `%LOCALAPPDATA%\Programs\loom-agent-server\` | Windows install dir |

| Env var | Purpose |
|---|---|
| `LOOM_LICENSE_KEY` | The `LOOM…` license |
| `LOOM_API_KEY` | HMAC key for request auth (empty = auth disabled, localhost only) |
| `LOOM_PUBLIC_BASE_URL` | Public origin, if exposed |

---

## Troubleshooting

- **"license check failed"** — key is invalid/expired or not written to the license
  file. Re-run the installer and paste a valid `LOOM…` key.
- **Agents won't start on Windows** — expected; native Windows has no `tmux`. Use
  the WSL2 path.
- **`wsl --version` shows usage text** — you're on the legacy in-box WSL.
  `wsl --install -d Ubuntu` still works; reboot afterward.
- **LLM CLI "not found" inside Ubuntu** — Windows `.exe` CLIs don't run in Linux;
  install and log into a CLI *inside* Ubuntu.
- **Health check fails** — confirm the port is free and check the server log.

## Security notes

- The `LOOM…` license and the HMAC API key are secrets. Don't commit them or paste
  them where they'll be retained; rotate if exposed.
- With no API key set, HMAC auth is disabled — only safe for localhost.
- Cloudflare quick-tunnel URLs are public and random; keep the API key enabled when
  exposing the server.

---

_This repository is generated. Installer scripts and binaries are published
automatically by the release pipeline in the private source repo._
