<#
.SYNOPSIS
  install.ps1 — interactive installer / one-line bootstrap for loom-agent-server on Windows.

.DESCRIPTION
  The Windows counterpart to install.sh + bootstrap.sh. Works two ways:

    1. One-liner (downloads the binary from GitHub, then installs):
         irm https://raw.githubusercontent.com/EmpiteHenry/loom-agent-server-dist/main/install.ps1 | iex

    2. From an unzipped release bundle (loom-agent-server.exe sits next to this script):
         powershell -ExecutionPolicy Bypass -File .\install.ps1

  It checks deps, picks an install dir on PATH, generates an HMAC API key, asks
  for port / public URL, and optionally registers a logon scheduled task so the
  server autostarts.

  NOTE: agents run inside tmux, which Windows lacks natively. The HTTP server
  runs fine, but agent-spawning needs WSL2 (Ubuntu) — see the caveat printed at
  the end. For full functionality, run this installer INSIDE a WSL2 shell using
  install.sh / bootstrap.sh instead.

.PARAMETER Version   Release tag to pull (default: latest)
.PARAMETER Repo      Public release repo (default: EmpiteHenry/loom-agent-server-dist)
.PARAMETER Port      Listen port (default: prompt, 8080)
.PARAMETER PublicUrl Externally-reachable origin (optional)
.PARAMETER AssumeYes Non-interactive: accept all defaults
#>
[CmdletBinding()]
param(
    [string]$Version   = "latest",
    [string]$Repo      = "EmpiteHenry/loom-agent-server-dist",
    [string]$SourceRepo = "EmpiteHenry/loom-agent-server",
    [string]$Port      = "",
    [string]$PublicUrl = "",
    [switch]$AssumeYes
)

$ErrorActionPreference = "Stop"
$Bin = "loom-agent-server.exe"

function Bold($m) { Write-Host $m -ForegroundColor White }
function Ok($m)   { Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [! ] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "  [x] $m" -ForegroundColor Red; exit 1 }
function Ask($prompt, $default) {
    if ($AssumeYes) { return $default }
    $suffix = if ($default) { " [$default]" } else { "" }
    $a = Read-Host "$prompt$suffix"
    if ([string]::IsNullOrWhiteSpace($a)) { return $default } else { return $a }
}
function YesNo($prompt, $default = "Y") {
    if ($AssumeYes) { return ($default -match '^[Yy]') }
    $hint = if ($default -match '^[Yy]') { "Y/n" } else { "y/N" }
    $a = Read-Host "$prompt [$hint]"
    if ([string]::IsNullOrWhiteSpace($a)) { $a = $default }
    return ($a -match '^[Yy]')
}

function Banner {
    $M = "Magenta"; $C = "Cyan"; $D = "DarkGray"
    Write-Host ""
    Write-Host "   ___ __  __ ___ ___ _____ ___ " -ForegroundColor $M -NoNewline
    Write-Host "      _    ___   ___  __  __" -ForegroundColor $C
    Write-Host "  | __|  \/  | _ \_ _|_   _| __|" -ForegroundColor $M -NoNewline
    Write-Host "     | |  / _ \ / _ \|  \/  |" -ForegroundColor $C
    Write-Host "  | _|| |\/| |  _/| |  | | | _| " -ForegroundColor $M -NoNewline
    Write-Host "     | |_| (_) | (_) | |\/| |" -ForegroundColor $C
    Write-Host "  |___|_|  |_|_| |___| |_| |___|" -ForegroundColor $M -NoNewline
    Write-Host "     |____\___/ \___/|_|  |_|" -ForegroundColor $C
    Write-Host ""
    Write-Host "     EMPITE LOOM - agent-server installer (Windows)" -ForegroundColor $D
    Write-Host "   --------------------------------------------------------" -ForegroundColor $D
    Write-Host ""
}

Clear-Host
Banner

# ── 1. arch detect ──────────────────────────────────────────────────────────
$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    "AMD64" { "amd64" }
    "ARM64" { "arm64" }
    default { Die "unsupported CPU arch '$($env:PROCESSOR_ARCHITECTURE)'" }
}
Ok "platform: windows/$arch"

# ── 2. locate or download the binary ────────────────────────────────────────
$localBin = Join-Path $PSScriptRoot $Bin
$src = $null
if ($PSScriptRoot -and (Test-Path $localBin)) {
    $src = $localBin
    Ok "found bundled $Bin"
} else {
    Bold "Downloading $Bin ($Version)"
    if ($Version -eq "latest") {
        $base = "https://github.com/$Repo/releases/latest/download"
    } else {
        $base = "https://github.com/$Repo/releases/download/$Version"
    }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "loom-$([System.Guid]::NewGuid().ToString('N')).exe"
    $url = "$base/loom-agent-server-windows-$arch.exe"
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
        $src = $tmp
        Ok "downloaded from releases"
    } catch {
        Die "could not download $url`n      Publish a 'loom-agent-server-windows-$arch.exe' asset on the release, or build locally with: GOOS=windows GOARCH=$arch go build -o $Bin ./cmd/loom-agent-server"
    }
}

# ── 3. dependencies ─────────────────────────────────────────────────────────
Bold "Checking runtime dependencies"
$haveLLM = $false
foreach ($c in @("claude","codex","gemini")) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { Ok "LLM CLI: $c"; $haveLLM = $true }
}
if (-not $haveLLM) { Warn "no LLM CLI (claude/codex/gemini) on PATH — install & log into one before creating agents" }

# ── 3b. Default agent model (radio picker) ──────────────────────────────────
function Choose-Model {
    $clis    = @("claude","codex","gemini")
    $names   = @("Claude Code","Codex CLI","Gemini CLI")
    $vendors = @("Anthropic","OpenAI","Google")
    $sel = 0
    for ($i = 0; $i -lt $clis.Count; $i++) {
        if (Get-Command $clis[$i] -ErrorAction SilentlyContinue) { $sel = $i; break }
    }
    if ($AssumeYes) { return $clis[$sel] }
    while ($true) {
        Write-Host ""
        Write-Host "  Select the default agent model:" -ForegroundColor White
        for ($i = 0; $i -lt $clis.Count; $i++) {
            $mark = if ($i -eq $sel) { "(*)" } else { "( )" }
            $installed = [bool](Get-Command $clis[$i] -ErrorAction SilentlyContinue)
            $st  = if ($installed) { "detected" } else { "not installed" }
            $col = if ($i -eq $sel) { "Cyan" } else { "Gray" }
            Write-Host ("    {0}  {1}) {2,-12} {3,-9}  {4}" -f $mark, ($i+1), $names[$i], $vendors[$i], $st) -ForegroundColor $col
        }
        $k = Read-Host "  press 1-3 to choose, Enter to confirm"
        if ([string]::IsNullOrWhiteSpace($k)) { break }
        if ($k -match '^[1-3]$') { $sel = [int]$k - 1 }
    }
    return $clis[$sel]
}

$model = Choose-Model
$confDir = Join-Path $env:USERPROFILE ".loom-agent-server"
New-Item -ItemType Directory -Force -Path $confDir | Out-Null
Set-Content -Path (Join-Path $confDir "installer.conf") -Value "LOOM_DEFAULT_MODEL=$model"
Ok "default agent model: $model  (saved -> $confDir\installer.conf)"
if (-not (Get-Command $model -ErrorAction SilentlyContinue)) { Warn "$model is not on PATH yet — install & log into it before creating agents" }
if (Get-Command wsl -ErrorAction SilentlyContinue) { Ok "wsl present (needed for tmux-based agents)" }
else { Warn "wsl NOT found — agents need tmux via WSL2. Install: wsl --install" }

# ── 4. install location ─────────────────────────────────────────────────────
Bold "Install location"
$defaultDest = Join-Path $env:LOCALAPPDATA "Programs\loom-agent-server"
$dest = Ask "Install into which dir" $defaultDest
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$target = Join-Path $dest $Bin
if ((Test-Path $target) -and -not (YesNo "$target exists — overwrite?" "Y")) { Die "aborted" }
Copy-Item -Force $src $target
Ok "installed -> $target"

# add to user PATH if missing
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$dest*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$dest", "User")
    Ok "added $dest to your user PATH (restart terminals to pick it up)"
}

# ── 5. API key (HMAC) ───────────────────────────────────────────────────────
Bold "API key (HMAC auth)"
Write-Host "The server signs every request with a shared key. Empty = auth disabled (localhost only)."
$keyFile = Join-Path $env:USERPROFILE ".loom-api-key"
$key = ""
if ((Test-Path $keyFile) -and ((Get-Item $keyFile).Length -gt 0) -and (YesNo "Reuse existing key at $keyFile?" "Y")) {
    $key = (Get-Content $keyFile -Raw).Trim()
    Ok "reusing $keyFile"
} elseif (YesNo "Generate a new API key?" "Y") {
    $key = (& $target gen-key).Trim()
    Set-Content -Path $keyFile -Value $key -NoNewline
    Ok "wrote $keyFile"
    Write-Host ""
    Bold "  >>> Put this SAME key in your web client / iOS app settings:"
    Write-Host "      $key"
    Write-Host ""
} else {
    Warn "no key — server will start with HMAC DISABLED"
}

# ── 6. network ──────────────────────────────────────────────────────────────
Bold "Network"
if (-not $Port) { $Port = Ask "Port to listen on" "8080" }
if (-not $PublicUrl) { $PublicUrl = Ask "Public base URL (optional)" "" }

# ── 7. autostart via scheduled task ─────────────────────────────────────────
Bold "Run the server"
$registered = $false
if (YesNo "Register a logon scheduled task that autostarts the server?" "Y") {
    $envPrefix = "`$env:LOOM_API_KEY='$key'; "
    if ($PublicUrl) { $envPrefix += "`$env:LOOM_PUBLIC_BASE_URL='$PublicUrl'; " }
    $cmd = "$envPrefix& '$target' serve --dev --port $Port *> '$env:USERPROFILE\loom-agent-server.log'"
    $action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"$cmd`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    try {
        Register-ScheduledTask -TaskName "loom-agent-server" -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
        Start-ScheduledTask -TaskName "loom-agent-server"
        Ok "scheduled task 'loom-agent-server' registered & started"
        Write-Host "      logs:    Get-Content `$env:USERPROFILE\loom-agent-server.log -Wait"
        Write-Host "      restart: Restart-ScheduledTask -TaskName loom-agent-server"
        $registered = $true
    } catch {
        Warn "could not register scheduled task: $($_.Exception.Message)"
    }
}

# ── 8. smoke test ───────────────────────────────────────────────────────────
if ($registered) {
    Start-Sleep -Seconds 2
    try {
        Invoke-WebRequest -Uri "http://127.0.0.1:$Port/healthz" -UseBasicParsing -TimeoutSec 3 | Out-Null
        Ok "server is up on :$Port (/healthz OK)"
    } catch { Warn "couldn't reach /healthz yet — check the log" }
}

# ── 9. done ─────────────────────────────────────────────────────────────────
Write-Host ""
Bold "Done."
if (-not $registered) {
    Write-Host "Start it manually with:"
    $manual = "& '$target' serve --dev --port $Port"
    Write-Host "  `$env:LOOM_API_KEY = Get-Content `"$keyFile`""
    Write-Host "  $manual"
}
Write-Host ""
Warn "Windows caveat: agents run inside tmux. Native Windows has no tmux, so"
Warn "agent-spawning won't work here. For full functionality run inside WSL2:"
Write-Host "      wsl --install            # one-time, then reboot"
Write-Host "      # inside the Ubuntu shell:"
Write-Host "      curl -fsSL https://raw.githubusercontent.com/$Repo/main/bootstrap.sh | bash"
Write-Host ""
Write-Host "See INSTALL.md / README.md for the full API and client setup."
