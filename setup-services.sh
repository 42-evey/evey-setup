#!/bin/bash
# Hermes Agent Stack Setup — Phase 2: Services
# Pick service tier, generate docker-compose, start containers
#
# Usage: bash setup-services.sh [base|services|full]
# Prev:  bash setup.sh
# Next:  bash install-plugins.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Non-interactive
YES="${YES:-0}"
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
TIER="${TIER:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=1; shift ;;
    --tier) TIER="$2"; shift 2 || true ;;
    *) break ;;
  esac
done

# ── Banner ──
echo ""
echo -e "${BOLD}"
echo "  ============================================"
echo "   Hermes Agent Stack Setup — Phase 2 of 4"
echo "            Service Deployment"
echo "  ============================================"
echo -e "${NC}"

# ══════════════════════════════════════════════
# RESOLVE INSTALL DIR
# ══════════════════════════════════════════════

INSTALL_DIR="$(resolve_install_dir)"

if [ ! -d "$INSTALL_DIR" ] || [ ! -f "$INSTALL_DIR/.env" ]; then
    err "No installation found at $INSTALL_DIR"
    err "Run setup.sh first to create the foundation."
    exit 1
fi

log "Install directory: $INSTALL_DIR"
echo ""

# ══════════════════════════════════════════════
# TIER SELECTION
# ══════════════════════════════════════════════

if [ -n "$TIER" ]; then
    log "Tier: $TIER (from --tier or TIER env)"
elif [ -n "${1:-}" ]; then
    TIER="$1"
    log "Tier: $TIER (from argument)"
else
    if is_yes; then
        TIER="base"
        log " --yes: defaulting to base tier (override with --tier or TIER=)"
    else
        log "Choose your stack tier:"
        echo ""
        echo "  1) base     — hermes-agent + LiteLLM + Ollama (3 services)"
        echo "                Minimum viable stack. Good for testing."
        echo ""
        echo "  2) services — base + MQTT, SearXNG, Qdrant, ntfy (7 services)"
        echo "                Adds search, vector memory, notifications."
        echo ""
        echo "  3) full     — services + n8n, Langfuse, Uptime Kuma (12+ services)"
        echo "                Complete stack with workflows, cost tracking, monitoring."
        echo ""
        safe_ask "Stack tier (1/2/3)" "1"
        case "$REPLY" in
            1|base)     TIER="base" ;;
            2|services) TIER="services" ;;
            3|full)     TIER="full" ;;
            *)          TIER="base"; warn "Invalid choice, defaulting to base" ;;
        esac
    fi
fi

log "Selected tier: $TIER"
echo ""

# ══════════════════════════════════════════════
# PORT CHECKS
# ══════════════════════════════════════════════

log "Checking port availability..."

PORT_CONFLICT=0
check_port 4000 "LiteLLM"    || PORT_CONFLICT=1
check_port 8642 "Hermes API"  || PORT_CONFLICT=1
check_port 11434 "Ollama"     || PORT_CONFLICT=1

if [ "$TIER" = "services" ] || [ "$TIER" = "full" ]; then
    check_port 1883 "MQTT"    || PORT_CONFLICT=1
    check_port 8888 "SearXNG" || PORT_CONFLICT=1
    check_port 6333 "Qdrant"  || PORT_CONFLICT=1
    check_port 2586 "ntfy"    || PORT_CONFLICT=1
fi

if [ "$TIER" = "full" ]; then
    check_port 5678 "n8n"         || PORT_CONFLICT=1
    check_port 3100 "Langfuse"    || PORT_CONFLICT=1
    check_port 3001 "Uptime Kuma" || PORT_CONFLICT=1
fi

if [ "$PORT_CONFLICT" -eq 1 ]; then
    warn "Some ports are in use. Services on those ports may fail to start."
    if is_yes; then
        warn " --yes: continuing despite port conflicts"
    else
        safe_ask "Continue anyway? (y/N)" "N"
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
else
    log "  All ports available"
fi

echo ""

# ══════════════════════════════════════════════
# COPY DOCKER-COMPOSE TEMPLATE
# ══════════════════════════════════════════════

log "Setting up docker-compose.yml (tier: $TIER)..."

TEMPLATE_DIR="$SCRIPT_DIR/templates"

if [ -f "$TEMPLATE_DIR/docker-compose.${TIER}.yml" ]; then
    cp "$TEMPLATE_DIR/docker-compose.${TIER}.yml" "$INSTALL_DIR/docker-compose.yml"
    log "  Copied from local templates"
else
    # Fallback: download from repo
    REPO_RAW="https://raw.githubusercontent.com/42-evey/evey-setup/main/templates"
    if curl -sf "$REPO_RAW/docker-compose.${TIER}.yml" -o "$INSTALL_DIR/docker-compose.yml"; then
        log "  Downloaded template from repo"
    else
        err "Could not find docker-compose template for tier '$TIER'."
        err "Make sure templates/docker-compose.${TIER}.yml exists."
        exit 1
    fi
fi

# ══════════════════════════════════════════════
# GPU DETECTION
# ══════════════════════════════════════════════

HAS_GPU=0
if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    log "GPU detected: $GPU_NAME"
    HAS_GPU=1
else
    warn "No NVIDIA GPU detected. Ollama will run on CPU (slower)."
    # Remove GPU deploy block so compose doesn't fail
    if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        # Use python for reliable multi-line YAML editing, fall back to sed
        if command -v python3 &>/dev/null; then
            python3 -c "
import re, sys
with open('$INSTALL_DIR/docker-compose.yml', 'r') as f:
    content = f.read()
# Remove deploy blocks with GPU reservations
content = re.sub(r'\n    deploy:\n      resources:\n        reservations:\n          devices:\n            - driver: nvidia\n              count: all\n              capabilities: \[gpu\]\n', '\n', content)
with open('$INSTALL_DIR/docker-compose.yml', 'w') as f:
    f.write(content)
" 2>/dev/null && log "  Removed GPU requirement from docker-compose.yml" || true
        fi
    fi
fi

echo ""

# ══════════════════════════════════════════════
# CONFIRM & START
# ══════════════════════════════════════════════

echo -e "${BOLD}  Service Summary${NC}"
echo "  -------------------------------------------"
echo "  Tier:       $TIER"
echo "  Compose:    $INSTALL_DIR/docker-compose.yml"
echo "  GPU:        $([ $HAS_GPU -eq 1 ] && echo "yes" || echo "no (CPU mode)")"
echo ""
echo "  Services:"
echo "    - hermes-agent     (port 8642)"
echo "    - hermes-litellm   (port 4000)"
echo "    - hermes-ollama    (port 11434)"
if [ "$TIER" = "services" ] || [ "$TIER" = "full" ]; then
    echo "    - hermes-mqtt      (port 1883)"
    echo "    - hermes-searxng   (port 8888)"
    echo "    - hermes-qdrant    (port 6333)"
    echo "    - hermes-ntfy      (port 2586)"
fi
if [ "$TIER" = "full" ]; then
    echo "    - hermes-n8n       (port 5678)"
    echo "    - hermes-n8n-db"
    echo "    - hermes-langfuse  (port 3100)"
    echo "    - hermes-langfuse-db"
    echo "    - hermes-uptimekuma (port 3001)"
fi
echo "  -------------------------------------------"
echo ""

if is_yes; then
    log " --yes: starting stack automatically"
    REPLY="Y"
else
    safe_ask "Start the stack now? (Y/n)" "Y"
fi
if [[ "$REPLY" =~ ^[Nn]$ ]]; then
    log "docker-compose.yml is ready. To start later:"
    echo ""
    echo "  cd $INSTALL_DIR && docker compose up -d --build"
    echo ""
    echo -e "  ${BOLD}Next: bash install-plugins.sh${NC}"
    exit 0
fi

# ══════════════════════════════════════════════
# BUILD & START
# ══════════════════════════════════════════════

log "Building and starting services..."
cd "$INSTALL_DIR"
docker compose up -d --build 2>&1 | tail -20

echo ""
log "Waiting for services to become healthy..."

# Wait up to 90 seconds for LiteLLM
TRIES=0
MAX_TRIES=18
while [ $TRIES -lt $MAX_TRIES ]; do
    if curl -sf http://localhost:4000/health/liveliness > /dev/null 2>&1; then
        break
    fi
    TRIES=$(( TRIES + 1 ))
    sleep 5
done

echo ""

# ══════════════════════════════════════════════
# HEALTH REPORT
# ══════════════════════════════════════════════

log "Health check:"

check_health() {
    local url=$1 name=$2 port=$3
    if curl -sf "$url" > /dev/null 2>&1; then
        log "  $name $(printf '%.*s' $((24 - ${#name})) '........................') OK (port $port)"
    else
        warn "  $name $(printf '%.*s' $((24 - ${#name})) '........................') starting"
    fi
}

check_health "http://localhost:4000/health/liveliness" "LiteLLM" "4000"
check_health "http://localhost:8642/health" "Hermes Agent" "8642"

if [ "$TIER" = "services" ] || [ "$TIER" = "full" ]; then
    check_health "http://localhost:8888" "SearXNG" "8888"
fi

if [ "$TIER" = "full" ]; then
    check_health "http://localhost:5678/healthz" "n8n" "5678"
    check_health "http://localhost:3100" "Langfuse" "3100"
    check_health "http://localhost:3001" "Uptime Kuma" "3001"
fi

# ══════════════════════════════════════════════
# DONE
# ══════════════════════════════════════════════

# Save tier to state
if [ -f "$SCRIPT_DIR/.setup-state" ]; then
    echo "TIER=${TIER}" >> "$SCRIPT_DIR/.setup-state"
fi

echo ""
echo -e "${BOLD}"
echo "  ============================================"
echo "     Phase 2 Complete — Services Running"
echo "  ============================================"
echo -e "${NC}"
echo "  Agent API:    http://localhost:8642"
echo "  LiteLLM:      http://localhost:4000"
echo "  Brain model:  MiMo-V2-Pro (free via OpenRouter)"
echo ""

if [ "$TIER" = "services" ] || [ "$TIER" = "full" ]; then
    echo "  SearXNG:      http://localhost:8888"
    echo "  ntfy:         http://localhost:2586"
fi
if [ "$TIER" = "full" ]; then
    echo "  n8n:          http://localhost:5678"
    echo "  Langfuse:     http://localhost:3100"
    echo "  Uptime Kuma:  http://localhost:3001"
fi

echo ""
echo "  Useful commands:"
echo "    cd $INSTALL_DIR"
echo "    docker compose logs -f hermes-agent    # watch agent logs"
echo "    docker compose ps                      # service status"
echo "    docker exec hermes-ollama ollama pull hermes3:8b  # pull local model"
echo ""
echo -e "  ${BOLD}Next: bash install-plugins.sh${NC}"
echo "  Add autonomy plugins, skills, and hooks."
echo ""
