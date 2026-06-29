#!/bin/bash
# customize.sh — Identity customization entrypoint (Task 002)
# Usage examples:
#   bash customize.sh                              # human interactive (prompts, fills identity)
#   bash customize.sh --workspace .. --identity my.toml
#   bash customize.sh --non-interactive --identity /abs/my.toml --workspace /path/ws
#   bash customize.sh --revert --workspace ..
# Sources lib/identity.sh for engine + common.sh for helpers.
# MODES: human (interactive), setup-driven (ws/identity.toml), agent (--non-interactive --identity)
# Engine ensures all layers (incl mqtt-topic/tool-prefix/manifest/machine-path) recorded via classify/sweep (specific structural before broad).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common for log/ask/safe_ask/is_yes + resolve if present
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
  source "$SCRIPT_DIR/lib/common.sh"
else
  GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; NC='\033[0m'
  log()  { echo -e "${GREEN}[customize]${NC} $1"; }
  warn() { echo -e "${YELLOW}[customize]${NC} $1"; }
  err()  { echo -e "${RED}[customize]${NC} $1" >&2; }
  ask()  {
    local p="$1" d="${2:-}"
    if [ -n "$d" ]; then echo -en "${CYAN}[customize]${NC} ${p} [${d}]: "; else echo -en "${CYAN}[customize]${NC} ${p}: "; fi
    read -r REPLY; [ -z "$REPLY" ] && REPLY="$d"
  }
  is_yes() { [ "${YES:-0}" = "1" ] || [ "${NON_INTERACTIVE:-0}" = "1" ]; }
  safe_ask() { if is_yes; then REPLY="${2:-}"; else ask "$@"; fi; }
fi

# Source the ENGINE (required)
if [ -f "$SCRIPT_DIR/lib/identity.sh" ]; then
  source "$SCRIPT_DIR/lib/identity.sh"
else
  err "lib/identity.sh not found (must be co-located)"
  exit 1
fi

# Use customize tag for logs (override common's hermes-setup for this entrypoint)
log()  { echo -e "${GREEN}[customize]${NC} $1"; }

# ── Defaults + arg parse ─────────────────────────────────────
WORKSPACE=""
IDENTITY_FILE=""
REPOS_CSV=""
REVERT=0
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
YES="${YES:-0}"

print_help() {
  cat <<H
customize.sh — rebrand Evey stack sources (evey-setup + plugins + bridge + pipeline)
Stages: SCAN (seed tokens) -> CLASSIFY (layers) -> REWRITE (case+structural) -> LEDGER -> VERIFY

Usage:
  bash customize.sh [options]

Options:
  --workspace DIR         Workspace containing member repos (default: dirname of git toplevel)
  --repos a,b,c           Limit to these repos (default: all 4 members)
  --identity FILE         Target identity.toml (required for non-interactive/agent)
  --non-interactive       Agent/CI mode (no prompts)
  --yes                   Alias for non-interactive
  --revert                Replay .identity-ledger.json to restore original byte-identical sources
  --help                  This help

MODES:
  human: prompts (copies example, fills via asks, runs)
  setup-driven: if identity.toml exists at workspace root, uses it
  agent: --non-interactive --identity FILE

After successful run: grep -rIil evey (members minus infra) == 0
--revert => clean git diff
re-run => "already customized, no changes"

H
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) print_help; exit 0 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --repos) REPOS_CSV="$2"; shift 2 ;;
    --identity) IDENTITY_FILE="$2"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --yes|-y) YES=1; NON_INTERACTIVE=1; shift ;;
    --revert) REVERT=1; shift ;;
    --*) err "unknown flag: $1"; exit 2 ;;
    *) break ;;
  esac
done

if [ "$YES" = "1" ]; then NON_INTERACTIVE=1; fi
export NON_INTERACTIVE YES

# ── Resolve workspace default (dirname $(git rev-parse --show-toplevel)) ─
resolve_workspace() {
  if [ -n "$WORKSPACE" ]; then
    echo "$WORKSPACE"
    return
  fi
  local top
  if command -v git >/dev/null 2>&1; then
    top=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  fi
  if [ -n "$top" ]; then
    dirname "$top"
  else
    pwd
  fi
}

WORKSPACE="$(resolve_workspace)"
[ -d "$WORKSPACE" ] || { err "workspace dir not found: $WORKSPACE"; exit 1; }

if [ -z "$REPOS_CSV" ]; then
  REPOS_CSV="$(identity_default_members)"
fi

# ── Revert mode (early) ───────────────────────────────────────
if [ "$REVERT" = 1 ]; then
  log "Reverting using ledger at $WORKSPACE ..."
  identity_revert "$WORKSPACE"
  log "revert done (check git diff --stat in member repos)"
  exit 0
fi

# ── Determine IDENTITY_FILE (modes) ───────────────────────────
# setup-driven: existing ws/identity.toml
# human: prompt fill
# agent: must have --identity

if [ -z "$IDENTITY_FILE" ]; then
  if [ -f "$WORKSPACE/identity.toml" ]; then
    IDENTITY_FILE="$WORKSPACE/identity.toml"
    log "setup-driven: using $IDENTITY_FILE"
  fi
fi

if [ "$NON_INTERACTIVE" != "1" ] && [ -z "$IDENTITY_FILE" ]; then
  # human interactive mode: fill from example
  log "Human mode — preparing identity"
  local_ex="$WORKSPACE/identity.toml"
  if [ ! -f "$local_ex" ]; then
    cp "$(identity_example_path)" "$local_ex"
    log "  copied identity.toml.example -> identity.toml (edit prompts follow)"
  fi
  IDENTITY_FILE="$local_ex"

  # interactive fill (use safe_ask which respects YES but here interactive)
  # load current (example) but we prompt and overwrite
  identity_load_toml "$(identity_example_path)" >/dev/null 2>&1 || true

  echo ""
  echo "Fill target identity (press Enter for example values if any):"
  safe_ask "owner.name (Title Case)" "${ID_OWNER_NAME:-Your Name}"
  n_name="$REPLY"
  safe_ask "owner.slug (lowercase, for dirs/plugins)" "${ID_OWNER_SLUG:-yourslug}"
  n_slug="$REPLY"
  safe_ask "owner.handle" "${ID_OWNER_HANDLE:-42-yourslug}"
  n_handle="$REPLY"
  safe_ask "owner.email" "${ID_OWNER_EMAIL:-you@yourslug.example}"
  n_email="$REPLY"
  safe_ask "owner.domain" "${ID_OWNER_DOMAIN:-yourslug.example}"
  n_domain="$REPLY"
  safe_ask "owner.donate (full url)" "${ID_OWNER_DONATE:-https://yourslug.example/donate.html}"
  n_donate="$REPLY"
  safe_ask "agent.peer (e.g. partner)" "${ID_AGENT_PEER:-partner}"
  n_peer="$REPLY"
  safe_ask "paths.root" "${ID_PATHS_ROOT:-/mnt/v/yourslug}"
  n_root="$REPLY"

  # write the filled
  cat > "$IDENTITY_FILE" <<EOF
[owner]
name = "$n_name"
slug = "$n_slug"
handle = "$n_handle"
email = "$n_email"
domain = "$n_domain"
donate = "$n_donate"

[agent]
peer = "$n_peer"

[paths]
root = "$n_root"
EOF
  log "  wrote filled identity.toml"
fi

if [ -z "$IDENTITY_FILE" ] || [ ! -f "$IDENTITY_FILE" ]; then
  err "identity file required. Use --identity FILE or run interactively."
  exit 2
fi

# ── Run the engine ────────────────────────────────────────────
log "workspace: $WORKSPACE"
log "repos: $REPOS_CSV"
log "identity: $IDENTITY_FILE"
echo ""

# Pre-check for already (via verify)
if identity_verify "$WORKSPACE" "$REPOS_CSV" "$(identity_seed_path)" >/dev/null 2>&1 ; then
  if [ -f "$WORKSPACE/.identity-ledger.json" ]; then
    log "already customized, no changes"
    exit 0
  fi
fi

identity_run "$WORKSPACE" "$IDENTITY_FILE" "$REPOS_CSV"
rc=$?

if [ $rc -eq 0 ]; then
  log "done. Run 'grep -rIil evey ...' (members minus infra) should return nothing."
  # final verify inside run already asserted zero or exited nonzero
fi

exit $rc
