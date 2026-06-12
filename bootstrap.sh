#!/usr/bin/env bash
# bootstrap.sh — one-line remote installer for loom-agent-server (macOS / Linux).
#
# The OpenCode-style entry point. Detects your OS + CPU, downloads the matching
# release bundle from GitHub, unpacks it to a temp dir, and hands off to the
# interactive install.sh inside the bundle (deps check, API key, port, service).
#
# Usage (the one-liner you share):
#   curl -fsSL https://raw.githubusercontent.com/EmpiteHenry/loom-agent-server-dist/main/bootstrap.sh | bash
#
# Binaries are served from a PUBLIC releases-only repo, so no token is needed.
# The source repo stays private; FROM_SOURCE=1 builds from it (requires repo access).
#
# Knobs (env vars):
#   REPO=owner/name       public repo to pull release binaries from (default below)
#   SOURCE_REPO=owner/name  private source repo for FROM_SOURCE builds (default below)
#   VERSION=v1.2.0        pin a release tag (default: latest)
#   ASSUME_YES=1          non-interactive install (passed through to install.sh)
#   PORT / PUBLIC_URL     forwarded to install.sh
#   FROM_SOURCE=1         skip release download; build from source with Go instead
#
set -euo pipefail

REPO="${REPO:-EmpiteHenry/loom-agent-server-dist}"
SOURCE_REPO="${SOURCE_REPO:-EmpiteHenry/loom-agent-server}"
VERSION="${VERSION:-latest}"
BIN="loom-agent-server"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

bold "loom-agent-server bootstrap"

# ── detect platform ────────────────────────────────────────────────────────
OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS" in
    Darwin) GOOS=darwin ;;
    Linux)  GOOS=linux ;;
    *) die "unsupported OS '$OS' — on Windows use install.ps1 instead (see README)";;
esac
case "$ARCH" in
    x86_64|amd64) GOARCH=amd64 ;;
    arm64|aarch64) GOARCH=arm64 ;;
    *) die "unsupported CPU arch '$ARCH'";;
esac
ok "platform: $GOOS/$GOARCH"

need() { command -v "$1" >/dev/null 2>&1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/loom-bootstrap.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# ── path A: build from source (no published release needed) ────────────────
build_from_source() {
    bold "Building from source"
    need go || die "FROM_SOURCE set but 'go' is not on PATH — install Go 1.26+ first"
    need git || die "git not on PATH"
    ok "go $(go version | awk '{print $3}')"
    git clone --depth 1 "https://github.com/$SOURCE_REPO.git" "$WORK/src" >/dev/null 2>&1 \
        || die "git clone failed for $SOURCE_REPO (private repo — ensure your git is authenticated)"
    ( cd "$WORK/src" && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o "$WORK/src/$BIN" ./cmd/loom-agent-server )
    ok "built $BIN"
    cd "$WORK/src"
    ASSUME_YES="${ASSUME_YES:-}" PORT="${PORT:-}" PUBLIC_URL="${PUBLIC_URL:-}" bash ./install.sh
    exit 0
}
[[ "${FROM_SOURCE:-}" == "1" ]] && build_from_source

# ── path B: download a release bundle from GitHub ──────────────────────────
fetch() { # fetch <url> <out>
    local url="$1" out="$2"
    if need curl; then
        curl -fsSL "$url" -o "$out"
    else
        wget -qO "$out" "$url"
    fi
}

need curl || need wget || die "need curl or wget on PATH"

if [[ "$VERSION" == "latest" ]]; then
    BASE="https://github.com/$REPO/releases/latest/download"
else
    BASE="https://github.com/$REPO/releases/download/$VERSION"
fi

bold "Downloading release ($VERSION) from $REPO"

# Pull the version-less alias asset for this OS/arch (public repo — no token).
ASSET=""
for ext in tar.gz zip; do
    url="$BASE/${BIN}-${GOOS}-${GOARCH}.${ext}"
    if fetch "$url" "$WORK/bundle.$ext" 2>/dev/null; then ASSET="$WORK/bundle.$ext"; break; fi
done

if [[ -z "$ASSET" ]]; then
    warn "no prebuilt bundle found for $GOOS/$GOARCH at $BASE"
    warn "falling back to building from source"
    build_from_source
fi
ok "downloaded $(basename "$ASSET")"

# ── unpack + hand off to the interactive installer ─────────────────────────
mkdir -p "$WORK/bundle"
case "$ASSET" in
    *.tar.gz) tar xzf "$ASSET" -C "$WORK/bundle" ;;
    *.zip)    need unzip || die "unzip not on PATH (needed for .zip bundle)"; unzip -q "$ASSET" -d "$WORK/bundle" ;;
esac
# install.sh sits either at the root or one dir deep (staging folder).
INSTALLER="$(find "$WORK/bundle" -maxdepth 2 -name install.sh | head -1)"
[[ -n "$INSTALLER" ]] || die "bundle did not contain install.sh"
ok "unpacked → handing off to install.sh"
echo
cd "$(dirname "$INSTALLER")"
exec bash ./install.sh
