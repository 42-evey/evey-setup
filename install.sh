#!/bin/bash
# Hermes Stack Installer — runs all phases in sequence
# Usage: curl -sf https://raw.githubusercontent.com/42-evey/evey-setup/main/install.sh | bash
# Or: bash install.sh [install-dir]
# Non-int: bash install.sh --yes --tier full --plugins all
# Env: OPENROUTER_API_KEY=... TIER=full PLUGINS=all
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║     Hermes Stack — Complete Installer    ║"
echo "  ║  hermes-agent + LiteLLM + free models    ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""

# If running from curl pipe, download all files first
if [ ! -f "$SCRIPT_DIR/setup.sh" ]; then
    echo "[install] Downloading setup files..."
    TMPDIR=$(mktemp -d)
    git clone --depth 1 https://github.com/42-evey/evey-setup.git "$TMPDIR/evey-setup" 2>/dev/null
    SCRIPT_DIR="$TMPDIR/evey-setup"
    cd "$SCRIPT_DIR"
fi

# Parse shared flags and env for non-interactive
YES=0
TIER=""
PLUGINS=""
INSTALL_DIR_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=1; shift ;;
    --tier) TIER="$2"; shift 2 || true ;;
    --plugins) PLUGINS="$2"; shift 2 || true ;;
    --*) shift ;;
    *) if [ -z "$INSTALL_DIR_ARG" ]; then INSTALL_DIR_ARG="$1"; fi; shift ;;
  esac
done

export YES TIER PLUGINS
if [ "$YES" = 1 ]; then
  export NON_INTERACTIVE=1
else
  export NON_INTERACTIVE=0
fi

PHASE_ARGS=()
[ -n "$INSTALL_DIR_ARG" ] && PHASE_ARGS+=("$INSTALL_DIR_ARG")
[ "$YES" = 1 ] && PHASE_ARGS+=("--yes")
[ -n "$TIER" ] && PHASE_ARGS+=("--tier" "$TIER")

echo "[install] Phase 1/4 — Foundation (scaffold, .env, clone hermes)"
echo "────────────────────────────────────────────"
bash "$SCRIPT_DIR/setup.sh" "${PHASE_ARGS[@]}"

# Re-read INSTALL_DIR from state written beside scripts (supports custom dir + non-int)
INSTALL_DIR=""
if [ -f "$SCRIPT_DIR/.setup-state" ]; then
    INSTALL_DIR=$(grep '^INSTALL_DIR=' "$SCRIPT_DIR/.setup-state" 2>/dev/null | cut -d= -f2- || true)
fi

echo ""
echo "[install] Phase 2/4 — Services (Docker containers)"
echo "────────────────────────────────────────────"
SVC_ARGS=()
[ "$YES" = 1 ] && SVC_ARGS+=("--yes")
[ -n "$TIER" ] && SVC_ARGS+=("--tier" "$TIER")
bash "$SCRIPT_DIR/setup-services.sh" "${SVC_ARGS[@]}"

echo ""
echo "[install] Phase 3/4 — Plugins"
echo "────────────────────────────────────────────"
PLUG_ARGS=()
[ -n "$INSTALL_DIR" ] && PLUG_ARGS+=("$INSTALL_DIR")
[ "$YES" = 1 ] && PLUG_ARGS+=("--yes")
[ -n "$PLUGINS" ] && PLUG_ARGS+=("--plugins" "$PLUGINS")
bash "$SCRIPT_DIR/install-plugins.sh" "${PLUG_ARGS[@]}"

echo ""
echo "[install] Phase 4/4 — Configuration"
echo "────────────────────────────────────────────"
CFG_ARGS=()
[ -n "$INSTALL_DIR" ] && CFG_ARGS+=("$INSTALL_DIR")
[ "$YES" = 1 ] && CFG_ARGS+=("--yes")
bash "$SCRIPT_DIR/configure.sh" "${CFG_ARGS[@]}"

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║          Installation Complete!          ║"
echo "  ║                                          ║"
echo "  ║  Your agent is running. Talk to it:      ║"
echo "  ║    hermes          (CLI)                 ║"
echo "  ║    Telegram        (if configured)       ║"
echo "  ║                                          ║"
echo "  ║  Dashboard:  http://localhost:8642       ║"
echo "  ║  Docs:       github.com/NousResearch/hermes-agent + 42-evey/hermes-plugins  ║"
echo "  ╚══════════════════════════════════════════╝"
