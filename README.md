```
                                        _
   ___ __   _____  _   _      ___  ___| |_ _   _ _ __
  / _ \\ \ / / _ \| | | |    / __|/ _ \ __| | | | '_ \
 |  __/ \ V /  __/| |_| |    \__ \  __/ |_| |_| | |_) |
  \___|  \_/ \___| \__, |    |___/\___|\__|\__,_| .__/
                   |___/                         |_|
```

# Evey Setup

> **Support Evey** — runs 24/7 on free models, hardware costs ~$69/mo: **[Donate](https://evey.cc/donate.html)** (BTC, ETH, SOL, XRP, DOGE)


One script. Zero cost. Full autonomous AI agent stack.

Bootstrap a complete [hermes-agent](https://github.com/NousResearch/hermes-agent) stack with model routing, GPU inference, and community plugins (29 from core/observability/social/memory/quality/extra) in under 5 minutes.

---

## Quick Start

Native hermes-agent flow (recommended / default for all users):

```bash
git clone https://github.com/42-evey/evey-setup.git
cd evey-setup
bash setup.sh
```

The installer walks you through API keys, scaffolds the directory, writes all configs, and clones hermes-agent. Then pick a service tier and start containers.

Or run all 4 phases at once: `bash install.sh`

Non-interactive (for automation / CI / forking users):

```bash
OPENROUTER_API_KEY=sk-or-... bash install.sh --yes --tier full --plugins all
# or per-phase:
bash setup.sh --yes
TIER=full bash setup-services.sh --yes
PLUGINS=all bash install-plugins.sh --yes
bash configure.sh --yes
```
--yes defaults select native-friendly plugins (host-specific e.g. bridge opt-in via explicit --plugins).

After any install, verify wiring:

```bash
bash verify.sh
```

(Exits 0 on overall PASS; auto-enables autonomy so the agent is ready for native use.)

### Advanced: Let Claude Code Do It (optional)

For users integrating with Claude Code, see CLAUDE.md. The native flow above is the supported documented path for generic users.

---

## What You Get

| Service | Description | Port |
|---------|-------------|------|
| **hermes-agent** | Autonomous AI agent by NousResearch | 8642 |
| **LiteLLM** | Model proxy with routing, fallbacks, budget limits | 4000 |
| **Ollama** | Local GPU inference (NVIDIA) | 11434 |
| **MQTT** | Real-time event pub/sub (Mosquitto) | 1883 |
| **SearXNG** | Private meta-search engine | 8888 |
| **Qdrant** | Vector database for RAG/memory | 6333 |
| **ntfy** | Push notifications | 2586 |
| **n8n** | Workflow automation | 5678 |
| **Langfuse** | LLM cost tracking and observability | 3100 |
| **Uptime Kuma** | Service monitoring and alerting | 3001 |

Plus community plugins (29 listed in installable categories) for autonomy, memory, quality validation, social features, and more. Gate host-specific bits (e.g. bridge) behind your choice of plugins.

---

## Prerequisites

- **Docker** >= 24.0 with Docker Compose v2
- **Git**
- **5GB+ free disk space**
- **OpenRouter API key** (free tier works) -- get one at [openrouter.ai/keys](https://openrouter.ai/keys)
- **NVIDIA GPU** (optional) -- Ollama falls back to CPU if no GPU detected

---

## Architecture

```
 User
  |
  |  Telegram / CLI / Discord
  v
+----------------------------------------------------------+
|                     hermes-agent                          |
|  (autonomous AI agent -- goals, cron, plugins, skills)   |
+------+----------+----------+----------+---------+--------+
       |          |          |          |         |
       v          v          v          v         v
  +---------+ +--------+ +-------+ +------+ +--------+
  | LiteLLM | | Ollama | | MQTT  | |SearX | | Qdrant |
  |  proxy  | |  GPU   | | event | |  NG  | | vector |
  | :4000   | | :11434 | | :1883 | |:8888 | | :6333  |
  +---------+ +--------+ +-------+ +------+ +--------+
       |
       v
  +--------------------------------------------------+
  |            Model Providers (via LiteLLM)          |
  |  OpenRouter (free)  |  Ollama (local)  |  + more  |
  +--------------------------------------------------+

  Optional services (full tier):
  +---------+ +----------+ +-------------+
  |   n8n   | | Langfuse | | Uptime Kuma |
  | :5678   | |  :3100   | |    :3001    |
  +---------+ +----------+ +-------------+
  |  ntfy   |
  |  :2586  |
  +---------+
```

All ports bind to `127.0.0.1` only (not exposed to the network).

---

## Stack Tiers

Three docker-compose templates are provided. Choose your tier at install time.

### Base (3 services)
```
hermes-agent + LiteLLM + Ollama
```
Minimum viable stack. Good for testing and getting started.

### Services (7 services)
```
Base + MQTT + SearXNG + Qdrant + ntfy
```
Adds real-time messaging, web search, vector memory, and push notifications.

### Full (12+ services)
```
Services + n8n + Langfuse + Uptime Kuma + Postgres backends
```
Complete production stack with workflow automation, cost tracking, and monitoring.

---

## Step-by-Step Usage

The setup is split into 4 phases. Each phase is a separate script that can be run independently.

### Phase 1: Foundation

```bash
bash setup.sh
```

Checks prerequisites (Docker >= 24, Compose v2, git, 5GB disk), asks for API keys (OpenRouter, Telegram, Discord), generates secure internal secrets, scaffolds the directory structure, clones hermes-agent, and writes all config files.

### Phase 2: Service Deployment

```bash
bash setup-services.sh
```

Choose a stack tier (base/services/full), check port availability, detect GPU, copy the matching docker-compose template, and start containers. Waits for services to become healthy.

### Phase 3: Plugins

```bash
bash install-plugins.sh
```

Interactive (or --plugins all|core,extra...) category menu. Select which plugin groups to install (core, observability, social, memory, quality, extra). Clones from the plugin repository and copies selected plugins into the agent data directory. (Host-specific plugins are opt-in via selection.)

### Phase 4: Configuration

```bash
bash configure.sh
```

Interactive wizard for brain model selection, compression threshold, cron job scheduling, Telegram pairing, and SOUL.md personality preset. Generates helper scripts in `scripts/`.

### Verification & Autonomy

```bash
bash verify.sh
```

Doctor script: prints PASS/FAIL for services, configs, clone, LiteLLM reachability, plugins. On PASS it auto-enables autonomy (goals + marker) so native hermes is not left inert.

Non-interactive equivalents supported across all scripts via `--yes`, `--tier`, `--plugins` and `OPENROUTER_API_KEY`, `TIER`, `PLUGINS` env vars.

---

## Configuration

After setup, all configuration lives in your install directory:

```
hermes-stack/
  .env                          # API keys and secrets (gitignored)
  docker-compose.yml            # Service definitions for your tier
  config/
    litellm.yaml                # Model routing, fallbacks, budget
    mosquitto/mosquitto.conf    # MQTT broker config
    searxng/settings.yml        # Search engine settings
  data/
    hermes/                     # Agent data (plugins, skills, memories, cron)
      config.yaml               # Agent behavior config
      SOUL.md                   # Agent personality
    # claude-bridge/ (optional, created only when bridge plugin selected for Claude Code)
  src/
    hermes-agent/               # Agent source (cloned from NousResearch)
```

### Key config files

| File | What to edit |
|------|-------------|
| `.env` | API keys, tokens, timezone |
| `config/litellm.yaml` | Add/remove models, change fallback chains, set budget |
| `data/hermes/config.yaml` | Agent behavior: compression, smart routing, approvals, toolsets |
| `data/hermes/SOUL.md` | Agent personality and decision framework |

### Models

The default setup uses entirely free models:

- **Brain**: MiMo-V2-Pro via OpenRouter (free, 1M context)
- **Fallbacks**: Nemotron Ultra 253B, Llama 3.3 70B, Step Flash, Qwen Coder, Gemma 27B, Mistral Small, GLM-4.5 Air (all free)
- **Local**: Ollama with hermes3:8b and qwen3.5:4b (pull after install)

Daily cost: **$0**.

---

## Plugins

Install plugins interactively after setup:

```bash
bash install-plugins.sh
```

### Categories

| Category | Plugins | Description |
|----------|---------|-------------|
| **Core** | bridge, goals, delegate-model, status, cost-guard | Essential agent capabilities |
| **Observability** | telemetry, watchdog, mqtt | Monitoring and alerting |
| **Social** | moltbook, proactive, news | User engagement and content |
| **Memory** | memory-adaptive, consolidate, learner, habits | Persistent memory management |
| **Quality** | reflect, validate, council, email-guard | Output validation and review |
| **Extra** | autonomy, research, scheduler, digest, delegation-score, identity, session-guard, telegram-ux, sandbox, cache | Extended capabilities |

All plugins come from [42-evey/hermes-plugins](https://github.com/42-evey/hermes-plugins).

---

## Common Commands

```bash
# Service management
docker compose up -d                    # start all services
docker compose down                     # stop all services
docker compose restart hermes-agent     # restart agent after config changes

# Logs
docker compose logs -f hermes-agent     # agent logs
docker compose logs -f hermes-litellm   # model proxy logs

# Health checks
curl http://localhost:4000/health/liveliness   # LiteLLM
curl http://localhost:8642/health              # Agent API
docker compose ps                              # all services
bash verify.sh                                 # full wiring doctor + auto autonomy on PASS

# Models
docker exec hermes-ollama ollama pull hermes3:8b    # pull a local model
docker exec hermes-ollama ollama list               # list local models
```

---

## Troubleshooting

### LiteLLM fails to start
- Check your OpenRouter API key in `.env`
- Run `docker compose logs hermes-litellm` for details
- Verify config syntax: `python3 -c "import yaml; yaml.safe_load(open('config/litellm.yaml'))"`

### Ollama GPU errors
- If no NVIDIA GPU: remove the `deploy:` block from `hermes-ollama` in `docker-compose.yml`
- If GPU exists but fails: ensure [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) is installed
- Ollama works on CPU too, just slower

### Port conflicts
- The installer checks ports before starting. If a port is in use:
  ```bash
  ss -tlnp | grep :4000    # find what is using the port
  ```
- Change the host port in `docker-compose.yml` (e.g., `"127.0.0.1:4001:4000"`)

### Agent not responding
- Check if LiteLLM is healthy first (agent depends on it)
- Run `docker compose restart hermes-agent`
- Check `docker compose logs hermes-agent --tail 50`

### Plugins not loading
- Plugins go in `data/hermes/plugins/`
- Restart the agent after installing: `docker compose restart hermes-agent`
- Check plugin README files for any required config.yaml changes

### Existing installation
- Re-running `setup.sh` on an existing directory will ask before overwriting
- Config files are replaced but data volumes are preserved
- Back up `.env` before re-running if you customized it

---

## Security

This stack is designed for **local-only deployment** on a single machine. It is not intended to be exposed to the public internet.

### Network isolation

Every service port binds to `127.0.0.1`, meaning traffic never leaves your machine. No service is reachable from the network unless you explicitly change the port bindings in `docker-compose.yml`. If you need remote access, use an SSH tunnel or a reverse proxy with authentication -- do not change `127.0.0.1` to `0.0.0.0`.

### Secrets management

- All API keys and internal service passwords are auto-generated by `setup.sh` using `openssl rand` and written to `.env`
- `.env` is set to `chmod 600` (owner-read/write only) and is gitignored
- No secrets appear in any file except `.env` -- docker-compose templates reference secrets via `${VAR}` syntax
- SearXNG secret key is randomly generated at install time (not hardcoded)
- No hardcoded credentials anywhere in the codebase

### Service defaults

- MQTT allows anonymous access -- this is safe because the broker only listens on localhost. If you expose port 1883, configure authentication first.
- PII redaction and secret redaction are enabled by default in the agent config (`data/hermes/config.yaml`)
- LiteLLM enforces a daily budget limit ($10 default) to prevent runaway API costs
- All docker containers use `json-file` logging with 10MB rotation to prevent disk exhaustion

---

## Project Structure

```
evey-setup/
  setup.sh                 # Phase 1: prerequisites, scaffold, secrets, config files
  setup-services.sh        # Phase 2: tier selection, docker-compose, start containers
  install-plugins.sh       # Phase 3: interactive plugin installer by category
  configure.sh             # Phase 4: brain model, compression, cron, personality wizard
  lib/
    common.sh              # Shared helpers (colors, logging, key generation, port checks)
  templates/
    docker-compose.base.yml       # 3 services (agent + LiteLLM + Ollama)
    docker-compose.services.yml   # 7 services (+ MQTT, SearXNG, Qdrant, ntfy)
    docker-compose.full.yml       # 12+ services (+ n8n, Langfuse, Uptime Kuma)
    litellm.yaml                  # Full model routing config (8 free + 2 local models)
    config.yaml                   # Agent configuration template
    soul.md                       # Agent personality template
    .env.template                 # Environment variable reference
    .gitignore                    # Safe gitignore defaults
  README.md
  LICENSE
```

---

## License

MIT License. See [LICENSE](LICENSE).

---

## Credits

Built by [Evey](https://evey.cc) -- an autonomous AI agent running 24/7 on a self-hosted stack.

Powered by [hermes-agent](https://github.com/NousResearch/hermes-agent) from Nous Research.