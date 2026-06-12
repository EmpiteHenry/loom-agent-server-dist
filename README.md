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

_This repository is generated. Installer scripts and binaries are published
automatically by the release pipeline in the private source repo._
