# evey-setup

Bootstrapper for a hermes-agent autonomous AI stack. Sets up hermes-agent + LiteLLM + plugins with free models.

## Setup Phases
```bash
bash setup.sh              # Phase 1: prerequisites, scaffold, .env, clone hermes
bash setup-services.sh     # Phase 2: pick tier (base/services/full), start Docker
bash install-plugins.sh    # Phase 3: pick plugins from 42-evey/hermes-plugins
bash configure.sh          # Phase 4: brain model, compression, crons, SOUL.md
```

## Directory After Install
```
~/evey-stack/
├── config/litellm.yaml         # Model routing (edit to add models)
├── data/hermes/config.yaml     # Agent config
├── data/hermes/plugins/        # Installed plugins
├── data/hermes/skills/         # Skill definitions
├── data/hermes/SOUL.md         # Agent personality (customize this)
├── data/hermes/cron/           # Cron job configs
├── data/claude-bridge/         # Claude Code ↔ Agent bridge
│   ├── inbox/                  # Tasks from Claude Code → Agent
│   ├── outbox/                 # Results from Agent → Claude Code
│   └── channel.jsonl           # Real-time message log (append-only)
├── docker-compose.yml          # Active services
├── .env                        # ALL secrets here (chmod 600)
└── .setup-state                # Tracks install dir + tier
```

## Building Your Daughter — Claude Code ↔ Agent Bridge

The bridge lets Claude Code (you) communicate with the hermes-agent. Think of it as parent-child communication:
- **You** (Claude Code) handle infrastructure, code, deployments
- **Your agent** (hermes) handles day-to-day management, research, scheduling

### How the Bridge Works

**channel.jsonl** — Append-only conversation log. Both sides write here:
```bash
# Send a message to your agent:
echo '{"from":"claude-code","to":"agent","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","message":"Check your goals and report back."}' >> data/claude-bridge/channel.jsonl
```

**inbox/** — Drop YAML task files for your agent to pick up:
```yaml
# data/claude-bridge/inbox/research-task.yaml
from: claude-code
to: agent
type: research
priority: medium
description: Research the latest free models on OpenRouter
```

**outbox/** — Agent drops results here for you to read.

### Setting Up the Bridge Hook

Add to your Claude Code settings (`.claude/settings.json`) so you automatically see agent messages:
```json
{
  "hooks": {
    "UserPromptSubmit": [{
      "hooks": [{
        "type": "command",
        "command": "python3 /path/to/evey-stack/scripts/bridge-hook.py UserPromptSubmit",
        "timeout": 5
      }]
    }]
  }
}
```

The bridge hook checks `channel.jsonl` and `inbox/` for unread messages from your agent and injects them as context into your session.

### Bridge Plugins

If you installed the **Core** plugin pack, your agent has:
- `claude_bridge_task` — send tasks to Claude Code
- `claude_bridge_message` — send quick messages
- `claude_bridge_check` — check for messages from Claude Code

Your agent's context-loader hook reads bridge messages at session start automatically.

### Teaching Your Agent

Customize `data/hermes/SOUL.md` — this is your agent's personality and rules. Tell it:
- What to do and what NOT to do
- When to escalate to you vs act autonomously
- How to manage the human's schedule
- What models to prefer

The SOUL.md is loaded every session. Change it and restart to update behavior.

## Key Commands
```bash
docker compose up -d                    # Start all services
docker compose ps                       # Check health
docker compose logs -f hermes-agent     # Watch agent logs
docker exec hermes-agent hermes cron list  # See cron jobs
```

## Security Rules
- ALL secrets in `.env` only — never hardcode in docker-compose or configs
- ALL ports bind to `127.0.0.1` — nothing exposed to network
- `.env` has `chmod 600` — owner-only read
- `.gitignore` excludes `.env`, `data/`, `backups/`
- Generated keys use `openssl rand` (cryptographically secure)

## Adding Plugins
```bash
bash install-plugins.sh    # Re-run to add more categories
# Or manually:
cp -r plugin-dir/ data/hermes/plugins/
docker compose restart hermes-agent
```

## Adding Services
Edit `docker-compose.yml` or re-run `bash setup-services.sh` with a higher tier.

## Updating
```bash
cd ~/evey-stack/src/hermes-agent && git pull
docker compose build hermes-agent
docker compose up -d --force-recreate hermes-agent
```

## Common Issues
- `Unknown provider 'litellm'` → use `provider: openrouter` with `base_url: http://hermes-litellm:4000/v1`
- Empty model responses → add `reasoning: { exclude: true }` to model config in litellm.yaml
- MQTT connect loop → ensure unique client_id per connection
- Agent not seeing bridge messages → check context-loader hook in `data/hermes/hooks/`
