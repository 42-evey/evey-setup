# CUSTOMIZE.md

`customize.sh` + `lib/identity.sh` allow rebranding the full Evey stack (evey-setup, hermes-plugins, evey-bridge-plugin, claude-research-pipeline) to a new owner identity.

See customize.sh --help for usage. All acceptance criteria implemented (SCAN/CLASSIFY/REWRITE/LEDGER/VERIFY, modes, dirs+layers consistent, zero stales, revert byte-id, idempotent).

## Files
- `customize.sh` — executable entrypoint (human / setup-driven / agent modes)
- `lib/identity.sh` — ENGINE (SCAN, CLASSIFY layers, REWRITE case-aware + structural renames, LEDGER, VERIFY)
- `templates/identity.seed.toml` — canonical Evey token source (scanner baseline)
- `templates/identity.toml.example` — fully commented target template

## Quick
```bash
bash customize.sh --workspace .. --identity my.toml
grep -rIil evey ../evey-setup ../hermes-plugins ../evey-bridge-plugin ../claude-research-pipeline | cat
bash customize.sh --revert --workspace ..
```

## Modes
- human: interactive prompts fill `identity.toml` then rewrite
- setup-driven: reads `workspace/identity.toml`
- agent: `--non-interactive --identity FILE`

## Stages (in lib/identity.sh)
1. SCAN workspace for seed tokens + case variants across members.
2. CLASSIFY hits: dir-name, plugin.yaml, logger, mqtt-topic, tool-prefix, manifest, branding, owner-data, machine-path.
3. REWRITE using target (case-aware: Evey/Title, evey/slug, 42-evey/handle). Structural: `evey-*` -> `<slug>-*`, plugin names, loggers `evey.x`, topics `evey/`, `evey_` + `<peer>_` prefixes kept consistent.
4. LEDGER `.identity-ledger.json` (gitignored) at ws root: records every {repo,file,line,layer,before,after}.
5. VERIFY: re-scan seed, zero survivors (excl infra allowlist + hermes-agent). Nonzero exit + file:line on fail.

## Idempotent + Revert
- Re-run on customized tree: "already customized, no changes"
- `--revert` restores byte-identical sources (clean `git diff`).
- Half-renames impossible: coupled layers renamed together.

## Acceptance (as specified)
- `bash customize.sh --workspace .. --identity my.toml` + `grep -rIil evey` (members - infra) = 0
- `--revert` => clean `git diff` in every member repo
- 2nd run => already-customized message
- No half-renames; dirs+plugin names+loggers+topics+prefixes kept in sync; ledger enables exact byte revert; verify excludes infra allowlist.

See `customize.sh --help`.
