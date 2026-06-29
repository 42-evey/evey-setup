#!/bin/bash
# ══════════════════════════════════════════════════════════════
# Hermes Plugin Installer
# Interactive menu to install hermes-agent plugins by category
# Source: github.com/42-evey/hermes-plugins (host-specific plugins gated by selection)
# ══════════════════════════════════════════════════════════════
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${GREEN}[plugins]${NC} $1"; }
err()  { echo -e "${RED}[plugins]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[plugins]${NC} $1"; }
info() { echo -e "${CYAN}[plugins]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    source "$SCRIPT_DIR/lib/common.sh"
fi

# ── Determine install directory ──────────────────────────────
# Use resolve_install_dir (respects arg, HERMES_STACK_DIR, .setup-state) to fix non-int from any cwd.
# EVEY_DIR kept only for compat (does not block generic users).
dir_arg=""
if [ -n "${1:-}" ] && [[ "${1:-}" != --* ]]; then
  dir_arg="$1"
fi
if declare -f resolve_install_dir &>/dev/null; then
    INSTALL_DIR="$(resolve_install_dir "$dir_arg")"
else
    INSTALL_DIR="${HERMES_STACK_DIR:-${EVEY_DIR:-$HOME/hermes-stack}}"
fi
PLUGIN_DIR="${INSTALL_DIR}/data/hermes/plugins"
REPO_URL="https://github.com/42-evey/hermes-plugins.git"
CLONE_DIR="${INSTALL_DIR}/.plugin-cache"

# Non-interactive support
YES="${YES:-0}"
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
PLUGINS_SPEC="${PLUGINS:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=1; shift ;;
    --plugins) PLUGINS_SPEC="$2"; shift 2 || true ;;
    *) break ;;
  esac
done
if [ -n "$PLUGINS_SPEC" ]; then
  YES=1  # plugins spec implies non-interactive selection
fi

# ── Category definitions ─────────────────────────────────────
# Format: "plugin-dir-name:description"
CORE_PLUGINS=(
    "evey-bridge:Bridge — bidirectional Claude Code <-> agent (optional, host-specific)"
    "evey-goals:Goals — autonomous goal tracking and pursuit"
    "evey-delegate-model:Delegate Model — smart model routing for delegation"
    "evey-status:Status — stack health and service monitoring"
    "evey-cost-guard:Cost Guard — budget enforcement and spend alerts"
)

OBSERVABILITY_PLUGINS=(
    "evey-telemetry:Telemetry — session metrics, tool stats, error tracking"
    "evey-watchdog:Watchdog — heartbeat monitoring, silence alerts via ntfy"
    "evey-mqtt:MQTT — real-time event pub/sub via Mosquitto"
)

SOCIAL_PLUGINS=(
    "evey-moltbook:Moltbook — AI social network integration"
    "evey-proactive:Proactive — surface insights and findings to users"
    "evey-news:News — curated AI/tech news delivery"
)

MEMORY_PLUGINS=(
    "evey-memory-adaptive:Memory Adaptive — context-aware memory management"
    "evey-memory-consolidate:Memory Consolidate — merge and compress old memories"
    "evey-learner:Learner — extract lessons from interactions"
    "evey-habits:Habits — track user patterns and preferences"
)

QUALITY_PLUGINS=(
    "evey-reflect:Reflect — post-task self-evaluation"
    "evey-validate:Validate — output quality scoring before delivery"
    "evey-council:Council — multi-model consensus on decisions"
    "evey-email-guard:Email Guard — review outbound emails before sending"
)

EXTRA_PLUGINS=(
    "evey-autonomy:Autonomy — autonomous decide/plan/reflect cycle"
    "evey-research:Research — structured web research with sources"
    "evey-scheduler:Scheduler — user schedule management"
    "evey-digest:Digest — weekly summary and report generation"
    "evey-delegation-score:Delegation Score — rate and track delegation quality"
    "evey-identity:Identity — agent self-awareness and persona"
    "evey-session-guard:Session Guard — session timeout and reset management"
    "evey-telegram-ux:Telegram UX — enhanced Telegram formatting"
    "evey-sandbox:Sandbox — safe code execution environment"
    "evey-cache:Cache — response caching for repeated queries"
)

# ── Helper functions ─────────────────────────────────────────

print_category() {
    local category_name="$1"
    shift
    local plugins=("$@")
    echo ""
    echo -e "  ${BOLD}${category_name}${NC}"
    for entry in "${plugins[@]}"; do
        local name="${entry%%:*}"
        local desc="${entry#*:}"
        echo -e "    ${CYAN}${name}${NC} — ${desc}"
    done
}

install_plugins_from_list() {
    local plugins=("$@")
    local installed=0
    local skipped=0

    for entry in "${plugins[@]}"; do
        local name="${entry%%:*}"
        local src="${CLONE_DIR}/${name}"
        local dst="${PLUGIN_DIR}/${name}"

        if [ ! -d "$src" ]; then
            warn "Plugin ${name} not found in repository — skipping"
            ((skipped++))
            continue
        fi

        if [ -d "$dst" ]; then
            info "Updating ${name} (already installed)"
            rm -rf "$dst"
        fi

        cp -r "$src" "$dst"
        log "Installed ${name}"
        ((installed++))
    done

    echo ""
    log "Installed: ${installed}, Skipped: ${skipped}"
}

clone_repo() {
    if [ -d "$CLONE_DIR" ] && [ -d "${CLONE_DIR}/.git" ]; then
        log "Updating plugin cache..."
        git -C "$CLONE_DIR" pull --quiet 2>/dev/null || {
            warn "Pull failed — re-cloning"
            rm -rf "$CLONE_DIR"
            git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
        }
    else
        log "Cloning plugin repository..."
        rm -rf "$CLONE_DIR"
        git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
    fi
}

install_utils() {
    if [ -f "${CLONE_DIR}/evey_utils.py" ]; then
        cp "${CLONE_DIR}/evey_utils.py" "${PLUGIN_DIR}/evey_utils.py"
        log "Installed evey_utils.py (shared utilities)"
    fi
}

# ── Main menu ────────────────────────────────────────────────

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║      Hermes Plugin Installer         ║"
echo "  ║  github.com/42-evey/hermes-plugins   ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

# Validate environment
if [ ! -d "$INSTALL_DIR" ]; then
    err "Install directory not found: ${INSTALL_DIR}"
    err "Set HERMES_STACK_DIR, pass dir arg, or run after setup.sh (uses .setup-state)."
    exit 1
fi

mkdir -p "$PLUGIN_DIR"

# Show categories (only in interactive)
if ! [ "${YES:-0}" = "1" ] && [ -z "$PLUGINS_SPEC" ]; then
  echo -e "${BOLD}Available plugin categories:${NC}"
  echo ""
  echo "  1) Core (recommended)    — bridge, goals, delegate, status, cost-guard"
  echo "  2) Observability         — telemetry, watchdog, mqtt"
  echo "  3) Social                — moltbook, proactive, news"
  echo "  4) Memory                — adaptive, consolidate, learner, habits"
  echo "  5) Quality               — reflect, validate, council, email-guard"
  echo "  6) Extra                 — autonomy, research, scheduler, digest, + more"
  echo "  7) All of the above"
  echo "  8) Show plugin details"
  echo "  9) Exit"
  echo ""
fi

SELECTION=""
if [ -n "$PLUGINS_SPEC" ]; then
    SELECTION="$PLUGINS_SPEC"
    log "Plugins from PLUGINS/--plugins: $SELECTION"
elif [ "${YES:-0}" = "1" ]; then
    SELECTION="1"  # default core for unattended (host-specific e.g. evey-bridge gated; use --plugins all|core,extra... to include)
    log " --yes: defaulting to Core plugins (use --plugins all to install more; bridge is optional for Claude Code)"
else
    while true; do
        echo -en "${CYAN}[plugins]${NC} Select categories (comma-separated, e.g. 1,2,4): "
        read -r SELECTION

        case "$SELECTION" in
            9|q|exit)
                log "Exiting."
                exit 0
                ;;
            8)
                print_category "Core (recommended)" "${CORE_PLUGINS[@]}"
                print_category "Observability" "${OBSERVABILITY_PLUGINS[@]}"
                print_category "Social" "${SOCIAL_PLUGINS[@]}"
                print_category "Memory" "${MEMORY_PLUGINS[@]}"
                print_category "Quality" "${QUALITY_PLUGINS[@]}"
                print_category "Extra" "${EXTRA_PLUGINS[@]}"
                echo ""
                continue
                ;;
            *)
                break
                ;;
        esac
    done
fi

# Normalize "all" and names to numeric (support comma lists)
norm_sel() {
  local s="$1"
  case "$s" in
    all|ALL) echo "7" ;;
    core|Core) echo "1" ;;
    observability) echo "2" ;;
    social) echo "3" ;;
    memory) echo "4" ;;
    quality) echo "5" ;;
    extra|Extra) echo "6" ;;
    *) echo "$s" ;;
  esac
}
if echo "$SELECTION" | grep -q ','; then
  IFS=',' read -ra PARTS <<< "$SELECTION"
  SELECTION=""
  for p in "${PARTS[@]}"; do
    p=$(echo "$p" | tr -d ' ')
    nn=$(norm_sel "$p")
    SELECTION="${SELECTION}${SELECTION:+,}${nn}"
  done
else
  SELECTION=$(norm_sel "$SELECTION")
fi

# Parse comma-separated selections
SELECTED=()
IFS=',' read -ra CHOICES <<< "$SELECTION"
for choice in "${CHOICES[@]}"; do
    choice="$(echo "$choice" | tr -d ' ')"
    case "$choice" in
        1) SELECTED+=("${CORE_PLUGINS[@]}") ;;
        2) SELECTED+=("${OBSERVABILITY_PLUGINS[@]}") ;;
        3) SELECTED+=("${SOCIAL_PLUGINS[@]}") ;;
        4) SELECTED+=("${MEMORY_PLUGINS[@]}") ;;
        5) SELECTED+=("${QUALITY_PLUGINS[@]}") ;;
        6) SELECTED+=("${EXTRA_PLUGINS[@]}") ;;
        7)
            SELECTED+=("${CORE_PLUGINS[@]}")
            SELECTED+=("${OBSERVABILITY_PLUGINS[@]}")
            SELECTED+=("${SOCIAL_PLUGINS[@]}")
            SELECTED+=("${MEMORY_PLUGINS[@]}")
            SELECTED+=("${QUALITY_PLUGINS[@]}")
            SELECTED+=("${EXTRA_PLUGINS[@]}")
            ;;
        *)
            warn "Unknown selection: ${choice} — skipping"
            ;;
    esac
done

# Gate host-specific bits (e.g. evey-bridge for Claude Code) behind explicit flags for generic native-hermes users.
# --yes (no --plugins) defaults omit bridge; explicit --plugins core/all include if selected.
if [ "${YES:-0}" = "1" ] && [ -z "${PLUGINS_SPEC:-}" ]; then
  FILTERED=()
  for entry in "${SELECTED[@]}"; do
    [[ "${entry%%:*}" == "evey-bridge" ]] || FILTERED+=("$entry")
  done
  SELECTED=("${FILTERED[@]}")
fi

if [ ${#SELECTED[@]} -eq 0 ]; then
    err "No plugins selected."
    exit 1
fi

# Deduplicate
UNIQUE_SELECTED=()
declare -A SEEN
for entry in "${SELECTED[@]}"; do
    local_name="${entry%%:*}"
    if [ -z "${SEEN[$local_name]+x}" ]; then
        UNIQUE_SELECTED+=("$entry")
        SEEN[$local_name]=1
    fi
done

echo ""
log "Installing ${#UNIQUE_SELECTED[@]} plugins..."

# Clone/update repo
clone_repo

# Install shared utils first
install_utils

# Install selected plugins
install_plugins_from_list "${UNIQUE_SELECTED[@]}"

# Cleanup
echo ""
log "Plugin installation complete."
info "Plugin directory: ${PLUGIN_DIR}"
info "Restart hermes-agent to load new plugins:"
echo ""
echo "  docker compose restart hermes-agent"
echo ""

# Show what to add to config.yaml platform_toolsets
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Restart hermes-agent to load plugins"
echo "  2. Add plugin toolsets to config.yaml platform_toolsets if needed"
echo "  3. Check plugin README files for configuration options"
echo ""
