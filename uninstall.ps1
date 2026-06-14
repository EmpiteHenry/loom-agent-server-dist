<#
.SYNOPSIS
  uninstall.ps1 — remove loom-agent-server from this Windows machine.

.DESCRIPTION
  The mirror of install.ps1. Stops & unregisters the logon scheduled task,
  deletes the installed binary, removes its dir from your user PATH, and
  optionally deletes the API key. Self-contained — run it as a one-liner:

    irm https://raw.githubusercontent.com/EmpiteHenry/loom-agent-server-dist/main/uninstall.ps1 | iex

  Non-interactive:
    powershell -File .\uninstall.ps1 -AssumeYes          # keep the key
    powershell -File .\uninstall.ps1 -AssumeYes -Purge   # also delete the key

.PARAMETER AssumeYes Non-interactive: accept the defaults
.PARAMETER Purge     With -AssumeYes, also delete the API key
#>
[CmdletBinding()]
param(
    [switch]$AssumeYes,
    [switch]$Purge
)

$ErrorActionPreference = "Stop"
$Bin = "loom-agent-server.exe"

function Bold($m) { Write-Host $m -ForegroundColor White }
function Ok($m)   { Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [! ] $m" -ForegroundColor Yellow }
function YesNo($prompt, $default = "Y") {
    if ($AssumeYes) { return ($default -match '^[Yy]') }
    $hint = if ($default -match '^[Yy]') { "Y/n" } else { "y/N" }
    $a = Read-Host "$prompt [$hint]"
    if ([string]::IsNullOrWhiteSpace($a)) { $a = $default }
    return ($a -match '^[Yy]')
}

Bold "loom-agent-server uninstaller (Windows)"
Write-Host ""

# ── 1. Stop & remove the scheduled task ──────────────────────────────────────
$task = Get-ScheduledTask -TaskName "loom-agent-server" -ErrorAction SilentlyContinue
if ($task) {
    try { Stop-ScheduledTask -TaskName "loom-agent-server" -ErrorAction SilentlyContinue } catch {}
    Unregister-ScheduledTask -TaskName "loom-agent-server" -Confirm:$false
    Ok "removed scheduled task 'loom-agent-server'"
} else {
    Warn "no scheduled task found"
}

# ── 2. Stop any running server process ───────────────────────────────────────
$procs = Get-Process -Name "loom-agent-server" -ErrorAction SilentlyContinue
if ($procs) {
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    Ok "stopped running loom-agent-server process(es)"
}

# Tear down a Cloudflare tunnel started by install.ps1, if any.
$tunPid = Join-Path $env:USERPROFILE "loom-tunnel.pid"
if (Test-Path $tunPid) {
    try { Stop-Process -Id ([int](Get-Content $tunPid)) -Force -ErrorAction SilentlyContinue } catch {}
    Remove-Item $tunPid,"$env:USERPROFILE\loom-tunnel.url","$env:USERPROFILE\loom-tunnel.log","$env:USERPROFILE\loom-tunnel.log.err" -Force -ErrorAction SilentlyContinue
    Ok "stopped Cloudflare tunnel"
}

# ── 3. Remove the installed binary ───────────────────────────────────────────
Bold "Removing the binary"
$removed = $false
$candidates = @(
    (Join-Path $env:LOCALAPPDATA "Programs\loom-agent-server")
)
# Also resolve whatever's on PATH right now.
$onPath = Get-Command $Bin -ErrorAction SilentlyContinue
if ($onPath) { $candidates += (Split-Path $onPath.Source) }

$candidates = $candidates | Select-Object -Unique
foreach ($dir in $candidates) {
    $target = Join-Path $dir $Bin
    if (Test-Path $target) {
        Remove-Item -Force $target
        Ok "removed $target"
        $removed = $true
        # Drop an empty install dir + strip it from user PATH.
        if ((Test-Path $dir) -and -not (Get-ChildItem $dir -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -Force -Recurse $dir -ErrorAction SilentlyContinue
        }
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($userPath -like "*$dir*") {
            $newPath = ($userPath -split ';' | Where-Object { $_ -and $_ -ne $dir }) -join ';'
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
            Ok "removed $dir from your user PATH (restart terminals)"
        }
    }
}
if (-not $removed) { Warn "no installed $Bin found in the usual dirs or on PATH" }

# ── 4. Optional: API key ─────────────────────────────────────────────────────
$keyFile = Join-Path $env:USERPROFILE ".loom-api-key"
$purgeKey = $false
if ($AssumeYes) { $purgeKey = $Purge.IsPresent }
elseif ((Test-Path $keyFile) -and (YesNo "Also delete the API key at $keyFile?" "N")) { $purgeKey = $true }
if ($purgeKey -and (Test-Path $keyFile)) {
    Remove-Item -Force $keyFile
    Ok "removed $keyFile"
}

# ── 5. Done ──────────────────────────────────────────────────────────────────
Write-Host ""
Bold "Done."
if ((-not $purgeKey) -and (Test-Path $keyFile)) {
    Write-Host "Kept your API key at $keyFile (delete it manually if you want it gone)."
}
$logFile = Join-Path $env:USERPROFILE "loom-agent-server.log"
if (Test-Path $logFile) { Write-Host "A log file remains at $logFile — remove it if you like." }
Write-Host "loom-agent-server has been removed."
