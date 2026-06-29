#!/bin/bash
# verify.sh — Doctor script for hermes stack (native hermes flow).
# Checks wiring for real users forking (native hermes path).
# Usage: bash verify.sh   (run from stack dir or with HERMES_STACK_DIR)
# Env: INSTALL_DIR=... 
# Prints PASS/FAIL per check. Ends with overall verdict.
# On overall PASS: auto-enables autonomy so agent is not left inert.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
  source "$SCRIPT_DIR/lib/common.sh"
else
  GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'
  YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
  log()  { echo -e "${GREEN}[verify]${NC} $1"; }
  warn() { echo -e "${YELLOW}[verify]${NC} $1"; }
  err()  { echo -e "${RED}[verify]${NC} $1" >&2; }
fi

PASS_MARK="${GREEN}PASS${NC}"
FAIL_MARK="${RED}FAIL${NC}"
CHECKS_PASSED=0
CHECKS_FAILED=0
OVERALL_PASS=1

record() {
  local name="$1" ok="$2" detail="${3:-}"
  if [ "$ok" -eq 1 ]; then
    echo -e "  [${PASS_MARK}] ${name}${detail:+ — $detail}"
    CHECKS_PASSED=$((CHECKS_PASSED+1))
  else
    echo -e "  [${FAIL_MARK}] ${name}${detail:+ — $detail}"
    CHECKS_FAILED=$((CHECKS_FAILED+1))
    OVERALL_PASS=0
  fi
}

# Resolve dir
INSTALL_DIR="${INSTALL_DIR:-}"
if [ -z "$INSTALL_DIR" ]; then
  if [ -f .setup-state ]; then
    INSTALL_DIR="$(grep '^INSTALL_DIR=' .setup-state 2>/dev/null | cut -d= -f2- || true)"
  fi
fi
if [ -z "$INSTALL_DIR" ] && declare -f resolve_install_dir >/dev/null 2>&1; then
  INSTALL_DIR="$(resolve_install_dir)"
fi
if [ -z "$INSTALL_DIR" ]; then
  # if cwd looks like a stack (has data/hermes or docker-compose or .env), use it
  if [ -d "$PWD/data/hermes" ] || [ -f "$PWD/docker-compose.yml" ] || [ -f "$PWD/.env" ]; then
    INSTALL_DIR="$PWD"
  else
    INSTALL_DIR="$HOME/hermes-stack"
  fi
fi

log "Checking installation at: $INSTALL_DIR"
echo ""

# 1. hermes-agent cloned at expected path
if [ -d "$INSTALL_DIR/src/hermes-agent" ] && [ -f "$INSTALL_DIR/src/hermes-agent/cli.py" -o -f "$INSTALL_DIR/src/hermes-agent/hermes" -o -d "$INSTALL_DIR/src/hermes-agent/hermes_cli" ]; then
  COMMIT="$(cd "$INSTALL_DIR/src/hermes-agent" 2>/dev/null && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
  record "hermes-agent cloned" 1 "at src/hermes-agent (commit ${COMMIT})"
else
  record "hermes-agent cloned" 0 "missing src/hermes-agent (run setup.sh)"
fi

# 2. Configs present + valid
CFG_OK=1
if [ ! -f "$INSTALL_DIR/.env" ]; then CFG_OK=0; fi
if [ ! -f "$INSTALL_DIR/config/litellm.yaml" ]; then CFG_OK=0; fi
if [ ! -f "$INSTALL_DIR/data/hermes/config.yaml" ]; then CFG_OK=0; fi
if [ "$CFG_OK" -eq 1 ]; then
  if command -v python3 >/dev/null 2>&1; then
    if python3 -c '
import yaml,sys,os
d = os.environ.get("INSTALL_DIR", ".")
for p in ["config/litellm.yaml", "data/hermes/config.yaml"]:
  fp = os.path.join(d, p)
  try:
    with open(fp) as f: yaml.safe_load(f)
  except Exception as e: print("bad:"+p); sys.exit(1)
print("ok")
' 2>/dev/null | grep -q ok; then
      record "configs present + valid" 1
    else
      record "configs present + valid" 0 "yaml parse error"
    fi
  else
    record "configs present + valid" 1 "(no python3 for deep validation)"
  fi
else
  record "configs present + valid" 0 "missing .env or litellm or hermes/config.yaml"
fi

# 3. Services healthy (docker compose ps)
# Must verify the hermes-agent row itself (not merely name present + any service healthy).
SVC_OK=0
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  if [ -d "$INSTALL_DIR" ]; then cd "$INSTALL_DIR" || true; fi
  PS_OUT=$(docker compose ps 2>/dev/null || true)
  # Isolate hermes-agent service line (handles table or compose v2 formats)
  AGENT_LINE=$(echo "$PS_OUT" | grep -E '(^|[[:space:]])hermes-agent([[:space:]]|$)' | head -1 || true)
  if [ -n "$AGENT_LINE" ] && echo "$AGENT_LINE" | grep -Eq 'healthy|Up|running'; then
    SVC_OK=1
  fi
  cd - >/dev/null 2>&1 || true
fi
if [ "$SVC_OK" -eq 1 ]; then
  record "services healthy (docker compose)" 1
else
  record "services healthy (docker compose)" 0 "hermes-agent not Up/healthy (run 'docker compose ps')"
fi

# 4. Model routing reachable (LiteLLM)
LIT_OK=0
if curl -sf --max-time 5 http://localhost:4000/health/liveliness >/dev/null 2>&1; then
  LIT_OK=1
fi
if [ "$LIT_OK" -eq 1 ]; then
  record "LiteLLM reachable" 1 "http://localhost:4000/health/liveliness"
else
  record "LiteLLM reachable" 0 "curl failed (is stack running?)"
fi

# 5. Plugins installed
PLUG_OK=0
PLUG_COUNT=$(find "$INSTALL_DIR/data/hermes/plugins" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
if [ "$PLUG_COUNT" -gt 0 ]; then
  PLUG_OK=1
fi
record "plugins installed" "$PLUG_OK" "$PLUG_COUNT plugin dir(s) under data/hermes/plugins"

echo ""
if [ "$OVERALL_PASS" -eq 1 ]; then
  echo "overall: PASS (${CHECKS_PASSED} checks)"
else
  echo "overall: FAIL (${CHECKS_PASSED} pass, ${CHECKS_FAILED} fail)"
fi
echo ""

# AUTO-ENABLE AUTONOMY on PASS (native hermes, not inert after good install)
if [ "$OVERALL_PASS" -eq 1 ]; then
  log "Auto-enabling autonomy for native hermes agent..."
  mkdir -p "$INSTALL_DIR/data/hermes/goals" "$INSTALL_DIR/data/hermes/cron"
  if [ ! -s "$INSTALL_DIR/data/hermes/goals/goals.json" ]; then
    echo '[{"id":"bootstrap","title":"Autonomous stack maintenance and goal pursuit","status":"active","created":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}]' > "$INSTALL_DIR/data/hermes/goals/goals.json" 2>/dev/null || true
  fi
  # Gate host-specific (claude-bridge) — do not require; only ensure native paths
  if [ -d "$INSTALL_DIR/data/hermes/plugins" ]; then
    # ensure at least core autonomy friendly bits visible if present (no-op if absent)
    : 
  fi
  # Mark + update config for autonomy if present (idempotent)
  touch "$INSTALL_DIR/data/hermes/.autonomy-enabled"
  if [ -f "$INSTALL_DIR/data/hermes/config.yaml" ]; then
    f="$INSTALL_DIR/data/hermes/config.yaml"
    # bash-only edit: insert under existing agent: or append section. Avoids dup top-level key.
    if ! grep -q 'autonomous:' "$f" 2>/dev/null; then
      if grep -q '^agent:' "$f" 2>/dev/null; then
        sed -i '/^agent:/a\  autonomous: true' "$f" 2>/dev/null || true
      else
        printf '\nagent:\n  autonomous: true\n' >> "$f" 2>/dev/null || true
      fi
    fi
  fi
  log "Autonomy marker + initial goal written. Restart agent to pick up: docker compose restart hermes-agent"
fi

echo "Run 'docker compose ps' and 'docker compose logs -f hermes-agent' for details."
[ "$OVERALL_PASS" -eq 1 ] && exit 0 || exit 1
