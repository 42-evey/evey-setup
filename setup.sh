#!/bin/bash
# Hermes Agent Stack Setup — Phase 1: Foundation
# Prerequisites, directory scaffold, .env generation, config files
#
# Usage: bash setup.sh [install-dir]
# Next:  bash setup-services.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
# identity engine (sourced for shared funcs; customize.sh is primary user)
if [ -f "$SCRIPT_DIR/lib/identity.sh" ]; then
  source "$SCRIPT_DIR/lib/identity.sh"
fi

# ── Non-interactive flags (env or --yes take precedence; interactive default)
YES="${YES:-0}"
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=1; shift ;;
    --tier|--plugins) shift 2 || shift || true ;; # passed to later phases
    *) break ;;
  esac
done

# ── Banner ──
echo ""
echo -e "${BOLD}"
echo "  ============================================"
echo "   Hermes Agent Stack Setup — Phase 1 of 4"
echo "          Foundation & Configuration"
echo "  ============================================"
echo -e "${NC}"

# ══════════════════════════════════════════════
# PREREQUISITES
# ══════════════════════════════════════════════

log "Checking prerequisites..."

# Docker binary
if ! command -v docker &>/dev/null; then
    err "Docker not found. Install Docker first: https://docs.docker.com/get-docker/"
    exit 1
fi

# Docker version >= 24
DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0")
DOCKER_MAJOR=$(echo "$DOCKER_VERSION" | cut -d. -f1)
if [ "$DOCKER_MAJOR" -lt 24 ] 2>/dev/null; then
    err "Docker version $DOCKER_VERSION is too old. Need >= 24.0."
    err "Update: https://docs.docker.com/engine/install/"
    exit 1
fi
log "  Docker $DOCKER_VERSION"

# Docker Compose v2
if docker compose version &>/dev/null; then
    COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "unknown")
    log "  Docker Compose $COMPOSE_VERSION"
elif docker-compose version &>/dev/null; then
    err "docker-compose v1 detected. Need Docker Compose v2 (docker compose)."
    err "Update: https://docs.docker.com/compose/install/"
    exit 1
else
    err "Docker Compose not found. Install docker-compose-plugin."
    exit 1
fi

# Docker daemon running
if ! docker info &>/dev/null; then
    err "Docker daemon is not running. Start Docker first."
    exit 1
fi
log "  Docker daemon is running"

# Git
if ! command -v git &>/dev/null; then
    err "git not found. Install git first."
    exit 1
fi
log "  git found"

# Disk space (need >= 5GB free)
if command -v df &>/dev/null; then
    FREE_KB=$(df -k "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "$FREE_KB" ] && [ "$FREE_KB" -lt 5242880 ] 2>/dev/null; then
        FREE_GB=$(( FREE_KB / 1048576 ))
        err "Only ${FREE_GB}GB free disk space. Need at least 5GB."
        exit 1
    fi
    if [ -n "$FREE_KB" ]; then
        FREE_GB=$(( FREE_KB / 1048576 ))
        log "  ${FREE_GB}GB free disk space"
    fi
fi

echo ""

# ══════════════════════════════════════════════
# INSTALL DIRECTORY
# ══════════════════════════════════════════════

if [ -n "${1:-}" ] && [[ "$1" != --* ]]; then
    INSTALL_DIR="$1"
    log "Install directory: $INSTALL_DIR (from argument)"
else
    if is_yes; then
        INSTALL_DIR="$HOME/hermes-stack"
    else
        safe_ask "Install directory" "$HOME/hermes-stack"
        INSTALL_DIR="$REPLY"
    fi
fi

# Check for existing install
if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/.env" ]; then
    warn "Existing installation found at $INSTALL_DIR"
    if is_yes; then
        log " --yes: overwriting configs (data preserved)"
    else
        safe_ask "Overwrite configs? Data directories will be preserved (y/N)" "N"
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
            log "Aborted. Existing install preserved."
            exit 0
        fi
    fi
fi

echo ""

# ══════════════════════════════════════════════
# API KEYS
# ══════════════════════════════════════════════

log "API key setup"
echo ""

if [ -n "${OPENROUTER_API_KEY:-}" ]; then
    OPENROUTER_KEY="$OPENROUTER_API_KEY"
    log "  OpenRouter key from OPENROUTER_API_KEY env"
elif is_yes; then
    OPENROUTER_KEY=""
    warn "No OPENROUTER_API_KEY — will be empty in .env (add before starting)"
else
    safe_ask "OpenRouter API key (get one free at openrouter.ai/keys)" ""
    OPENROUTER_KEY="$REPLY"
fi
if [ -z "$OPENROUTER_KEY" ]; then
    warn "No OpenRouter key — brain model will not work until you add one to .env"
fi

echo ""
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
    TELEGRAM_TOKEN="$TELEGRAM_BOT_TOKEN"
else
    if is_yes; then
        TELEGRAM_TOKEN=""
    else
        safe_ask "Telegram bot token (from @BotFather, or Enter to skip)" ""
        TELEGRAM_TOKEN="$REPLY"
    fi
fi

if [ -n "${DISCORD_BOT_TOKEN:-}" ]; then
    DISCORD_TOKEN="$DISCORD_BOT_TOKEN"
else
    if is_yes; then
        DISCORD_TOKEN=""
    else
        safe_ask "Discord bot token (from discord.com/developers/applications, or Enter to skip)" ""
        DISCORD_TOKEN="$REPLY"
    fi
fi

echo ""

# ══════════════════════════════════════════════
# GENERATE SECRETS
# ══════════════════════════════════════════════

log "Generating secure keys..."

LITELLM_KEY="sk-litellm-$(gen_key 16)"
API_KEY="sk-api-$(gen_key 8)"
# Pre-generate full-tier secrets (cheap, user may upgrade tier later)
N8N_DB_PASS="$(gen_key 16)"
LANGFUSE_DB_PASS="$(gen_key 16)"
NEXTAUTH_SECRET="$(gen_key 32)"
LANGFUSE_SALT="$(gen_key 16)"
LANGFUSE_PUB="pk-lf-$(gen_key 12)"
LANGFUSE_SEC="sk-lf-$(gen_key 16)"

log "  Keys generated"

echo ""

# ══════════════════════════════════════════════
# SCAFFOLD DIRECTORY STRUCTURE
# ══════════════════════════════════════════════

log "Scaffolding $INSTALL_DIR ..."

mkdir -p "$INSTALL_DIR"

# Config directories
mkdir -p "$INSTALL_DIR/config"
mkdir -p "$INSTALL_DIR/config/mosquitto"
mkdir -p "$INSTALL_DIR/config/searxng"

# Data directories — hermes agent
mkdir -p "$INSTALL_DIR/data/hermes/plugins"
mkdir -p "$INSTALL_DIR/data/hermes/skills"
mkdir -p "$INSTALL_DIR/data/hermes/cron"
mkdir -p "$INSTALL_DIR/data/hermes/memories"
mkdir -p "$INSTALL_DIR/data/hermes/workspace"

# Data directories — services (create all, even if tier is base — no harm)
mkdir -p "$INSTALL_DIR/data/mqtt"
mkdir -p "$INSTALL_DIR/data/qdrant"
mkdir -p "$INSTALL_DIR/data/ntfy"
mkdir -p "$INSTALL_DIR/data/n8n"
mkdir -p "$INSTALL_DIR/data/uptimekuma"

# Build & source directories
mkdir -p "$INSTALL_DIR/dockerfiles"
mkdir -p "$INSTALL_DIR/scripts"
mkdir -p "$INSTALL_DIR/src"

log "  Directory structure created"

# ══════════════════════════════════════════════
# CLONE HERMES-AGENT
# ══════════════════════════════════════════════

# Pinned to tested upstream commit for reproducible installs against current config loader.
# Commit recorded: 3ac96d330892cf0e7d9ad0def1d23b9aa7d50c0f (from /allow/hermes-agent inspection)
HERMES_COMMIT="3ac96d330892cf0e7d9ad0def1d23b9aa7d50c0f"
if [ ! -d "$INSTALL_DIR/src/hermes-agent" ]; then
    log "Cloning hermes-agent (pinned ${HERMES_COMMIT})..."
    # Clone without --depth 1 on fetch; shallow fetch by arbitrary SHA is fragile on some git servers.
    # Full history on clone + checkout guarantees the pinned commit is always available.
    git clone https://github.com/NousResearch/hermes-agent.git "$INSTALL_DIR/src/hermes-agent"
    (cd "$INSTALL_DIR/src/hermes-agent" && git checkout --quiet "$HERMES_COMMIT")
else
    log "  hermes-agent source already present"
fi

# ══════════════════════════════════════════════
# WRITE .env
# ══════════════════════════════════════════════

log "Writing .env ..."

cat > "$INSTALL_DIR/.env" << ENVEOF
# Hermes Stack — generated by setup.sh
# Modify values as needed, then run: bash setup-services.sh

# --- Core API Keys ---
OPENROUTER_API_KEY=${OPENROUTER_KEY}
TELEGRAM_BOT_TOKEN=${TELEGRAM_TOKEN}
DISCORD_BOT_TOKEN=${DISCORD_TOKEN}

# --- Internal Service Keys (auto-generated) ---
LITELLM_MASTER_KEY=${LITELLM_KEY}
API_SERVER_KEY=${API_KEY}

# --- n8n Database ---
N8N_DB_PASSWORD=${N8N_DB_PASS}

# --- Langfuse ---
LANGFUSE_DB_PASSWORD=${LANGFUSE_DB_PASS}
NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
LANGFUSE_SALT=${LANGFUSE_SALT}
LANGFUSE_PUBLIC_KEY=${LANGFUSE_PUB}
LANGFUSE_SECRET_KEY=${LANGFUSE_SEC}

# --- Timezone ---
TZ=$(cat /etc/timezone 2>/dev/null || echo "UTC")
ENVEOF

chmod 600 "$INSTALL_DIR/.env"
log "  .env written (permissions: 600)"

# ══════════════════════════════════════════════
# WRITE .gitignore
# ══════════════════════════════════════════════

cat > "$INSTALL_DIR/.gitignore" << 'GIEOF'
.env
data/
*.log
__pycache__/
.DS_Store
GIEOF

log "  .gitignore written"

# ══════════════════════════════════════════════
# WRITE CONFIG FILES
# ══════════════════════════════════════════════

log "Writing config files..."

# ── LiteLLM config ──
cat > "$INSTALL_DIR/config/litellm.yaml" << 'LMEOF'
model_list:
  # Free brain model via OpenRouter
  - model_name: brain
    litellm_params:
      model: openrouter/xiaomi/mimo-v2-pro
      api_key: os.environ/OPENROUTER_API_KEY

  # Free fallback models
  - model_name: fallback-large
    litellm_params:
      model: openrouter/nvidia/llama-3.1-nemotron-ultra-253b:free
      api_key: os.environ/OPENROUTER_API_KEY

  - model_name: fallback-medium
    litellm_params:
      model: openrouter/meta-llama/llama-3.3-70b-instruct:free
      api_key: os.environ/OPENROUTER_API_KEY

  # Local model via Ollama
  # Pull models: docker exec hermes-ollama ollama pull hermes3:8b
  - model_name: local
    litellm_params:
      model: ollama/hermes3:8b
      api_base: http://hermes-ollama:11434

fallbacks:
  - brain: [fallback-large, fallback-medium]

litellm_settings:
  max_budget: 10.0
  budget_duration: 1d
  cache: true
  cache_params:
    type: "local"
    ttl: 300

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
LMEOF

log "  config/litellm.yaml"

# ── Mosquitto config ──
cat > "$INSTALL_DIR/config/mosquitto/mosquitto.conf" << 'MQEOF'
listener 1883
allow_anonymous true
persistence true
persistence_location /mosquitto/data/
log_dest stdout
MQEOF

log "  config/mosquitto/mosquitto.conf"

# ── SearXNG settings ──
SEARXNG_SECRET="$(gen_key 16)"
cat > "$INSTALL_DIR/config/searxng/settings.yml" << SXEOF
use_default_settings: true
server:
  secret_key: "${SEARXNG_SECRET}"
  limiter: false
search:
  safe_search: 0
  autocomplete: ""
  default_lang: "en"
SXEOF

log "  config/searxng/settings.yml"

# ── Seed hermes config.yaml early (config drift fix + verify compat) ──
# Upstream (commit 3ac96d330892cf0e7d9ad0def1d23b9aa7d50c0f) uses get_config_path() -> $HERMES_HOME/config.yaml
# (cli-config.yaml.example is the example; migrator + _normalize_root_model_keys handle legacy roots + model: dict).
# Pre-seed our adapted template (with model: + litellm wiring) before docker first-boot seed.
TEMPLATE_DIR="$SCRIPT_DIR/templates"
if [ -f "$TEMPLATE_DIR/config.yaml" ]; then
    if [ ! -f "$INSTALL_DIR/data/hermes/config.yaml" ]; then
        cp "$TEMPLATE_DIR/config.yaml" "$INSTALL_DIR/data/hermes/config.yaml"
        log "  data/hermes/config.yaml"
    fi
fi

# ── Init files ──
if [ ! -f "$INSTALL_DIR/data/hermes/cron/jobs.json" ]; then
    echo '[]' > "$INSTALL_DIR/data/hermes/cron/jobs.json"
fi

# ══════════════════════════════════════════════
# SAVE STATE FOR NEXT PHASES
# ══════════════════════════════════════════════

cat > "$SCRIPT_DIR/.setup-state" << STEOF
INSTALL_DIR=${INSTALL_DIR}
STEOF

# ══════════════════════════════════════════════
# DONE
# ══════════════════════════════════════════════

echo ""
echo -e "${BOLD}"
echo "  ============================================"
echo "        Phase 1 Complete — Foundation"
echo "  ============================================"
echo -e "${NC}"
echo "  Install directory:  $INSTALL_DIR"
echo "  OpenRouter key:     ${OPENROUTER_KEY:+set}${OPENROUTER_KEY:-NOT SET}"
echo "  Telegram token:     ${TELEGRAM_TOKEN:+set}${TELEGRAM_TOKEN:-skipped}"
echo "  Discord token:      ${DISCORD_TOKEN:+set}${DISCORD_TOKEN:-skipped}"
echo ""
echo "  Created:"
echo "    .env               API keys + generated secrets"
echo "    config/             litellm.yaml, mosquitto, searxng"
echo "    data/hermes/        plugins, skills, cron, memories, config.yaml"
echo "    src/hermes-agent/   cloned from NousResearch"
echo ""
echo -e "  ${BOLD}Next: bash setup-services.sh${NC}"
echo "  Pick a service tier and start Docker containers."
echo ""
