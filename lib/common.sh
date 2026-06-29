#!/bin/bash
# Shared helpers for evey-setup scripts
# Source this: source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${GREEN}[hermes-setup]${NC} $1"; }
warn() { echo -e "${YELLOW}[hermes-setup]${NC} $1"; }
err()  { echo -e "${RED}[hermes-setup]${NC} $1" >&2; }
ask()  {
    local prompt="$1" default="${2:-}"
    if [ -n "$default" ]; then
        echo -en "${CYAN}[hermes-setup]${NC} ${prompt} [${default}]: "
    else
        echo -en "${CYAN}[hermes-setup]${NC} ${prompt}: "
    fi
    read -r REPLY
    [ -z "$REPLY" ] && REPLY="$default"
}

# Non-interactive mode support (set YES=1 or NON_INTERACTIVE=1 before calls, or via --yes in callers)
is_yes() {
    [ "${YES:-0}" = "1" ] || [ "${NON_INTERACTIVE:-0}" = "1" ]
}

safe_ask() {
    local prompt="$1" default="${2:-}"
    if is_yes; then
        REPLY="$default"
        return 0
    fi
    ask "$prompt" "$default"
}

gen_key() {
    openssl rand -hex "$1" 2>/dev/null || head -c $(( $1 * 2 )) /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c $(( $1 * 2 ))
}

# Resolve INSTALL_DIR: arg > env > read from .setup-state > default
resolve_install_dir() {
    local dir="${1:-${HERMES_STACK_DIR:-}}"
    local script_dir
    local caller_src="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    script_dir="$(cd "$(dirname "$caller_src")" && pwd)"

    # Try reading from state file left by setup.sh
    if [ -z "$dir" ] && [ -f "$script_dir/.setup-state" ]; then
        dir="$(grep '^INSTALL_DIR=' "$script_dir/.setup-state" 2>/dev/null | cut -d= -f2-)"
    fi

    if [ -z "$dir" ]; then
        dir="$HOME/hermes-stack"
    fi

    echo "$dir"
}

check_port() {
    local port=$1 name=$2
    if command -v ss &>/dev/null; then
        if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
            err "Port $port ($name) is already in use."
            return 1
        fi
    elif command -v netstat &>/dev/null; then
        if netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
            err "Port $port ($name) is already in use."
            return 1
        fi
    fi
    return 0
}
