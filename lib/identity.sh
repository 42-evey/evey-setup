#!/bin/bash
# lib/identity.sh — Identity customization ENGINE for evey-setup workspace.
# Sourced by customize.sh (entrypoint) AND setup.sh.
# Implements the 5 stages: SCAN, CLASSIFY, REWRITE, LEDGER, VERIFY.
# All logic here; customize.sh is thin CLI/modes wrapper.
# Pure bash only. No python, no external.

# Resolve script dir relative to the including script when sourced.
_IDENTITY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_IDENTITY_ROOT_DIR="$(cd "${_IDENTITY_LIB_DIR}/.." && pwd)"

# Default member repos (order matters for deterministic ledger sometimes)
identity_default_members() {
  echo "evey-setup,hermes-plugins,evey-bridge-plugin,claude-research-pipeline"
}

# Infra allowlist to exclude from VERIFY stale scan (exact subdir names anywhere in path)
identity_infra_excludes() {
  echo "hermes-qdrant hermes-litellm hermes-crawl4ai hermes-mqtt hermes-agent"
}

# Paths
identity_seed_path() {
  local base="${1:-${_IDENTITY_ROOT_DIR}}"
  if [ -f "$base/templates/identity.seed.toml" ]; then
    echo "$base/templates/identity.seed.toml"
  else
    echo "${_IDENTITY_ROOT_DIR}/templates/identity.seed.toml"
  fi
}

identity_example_path() {
  local base="${1:-${_IDENTITY_ROOT_DIR}}"
  if [ -f "$base/templates/identity.toml.example" ]; then
    echo "$base/templates/identity.toml.example"
  else
    echo "${_IDENTITY_ROOT_DIR}/templates/identity.toml.example"
  fi
}

# --- TOML load (pure bash) ---
# Sets global vars like ID_OWNER_NAME etc. from given toml path.
identity_load_toml() {
  local toml="$1"
  [ -f "$toml" ] || { echo "identity_load_toml: missing $toml" >&2; return 1; }
  ID_OWNER_NAME=""; ID_OWNER_SLUG=""; ID_OWNER_HANDLE=""
  ID_OWNER_EMAIL=""; ID_OWNER_DOMAIN=""; ID_OWNER_DONATE=""
  ID_AGENT_PEER=""; ID_PATHS_ROOT=""
  local cur=""
  while IFS= read -r line || [ -n "$line" ]; do
    # strip comments and trim
    line="${line%%#*}"
    line="$(echo "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -z "$line" ] && continue
    if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\] ]]; then
      cur="${BASH_REMATCH[1]}"
      continue
    fi
    if [[ "$line" =~ ^([a-zA-Z0-9_]+)[[:space:]]*=[[:space:]]*\"([^\"]*)\" ]]; then
      local k="${BASH_REMATCH[1]}"
      local v="${BASH_REMATCH[2]}"
      local kk
      if [ -n "$cur" ]; then
        kk=$(echo "${cur}_${k}" | tr '[:lower:]' '[:upper:]')
      else
        kk=$(echo "$k" | tr '[:lower:]' '[:upper:]')
      fi
      case "$kk" in
        OWNER_NAME|ID_OWNER_NAME) ID_OWNER_NAME="$v" ;;
        OWNER_SLUG|ID_OWNER_SLUG) ID_OWNER_SLUG="$v" ;;
        OWNER_HANDLE|ID_OWNER_HANDLE) ID_OWNER_HANDLE="$v" ;;
        OWNER_EMAIL|ID_OWNER_EMAIL) ID_OWNER_EMAIL="$v" ;;
        OWNER_DOMAIN|ID_OWNER_DOMAIN) ID_OWNER_DOMAIN="$v" ;;
        OWNER_DONATE|ID_OWNER_DONATE) ID_OWNER_DONATE="$v" ;;
        AGENT_PEER|ID_AGENT_PEER) ID_AGENT_PEER="$v" ;;
        PATHS_ROOT|ID_PATHS_ROOT) ID_PATHS_ROOT="$v" ;;
      esac
    fi
  done < "$toml"
  # normalize
  ID_OWNER_NAME="${ID_OWNER_NAME:-${OWNER_NAME:-Evey}}"
  ID_OWNER_SLUG="${ID_OWNER_SLUG:-${OWNER_SLUG:-evey}}"
  ID_OWNER_HANDLE="${ID_OWNER_HANDLE:-${OWNER_HANDLE:-42-evey}}"
  ID_OWNER_EMAIL="${ID_OWNER_EMAIL:-${OWNER_EMAIL:-evey@evey.cc}}"
  ID_OWNER_DOMAIN="${ID_OWNER_DOMAIN:-${OWNER_DOMAIN:-evey.cc}}"
  ID_OWNER_DONATE="${ID_OWNER_DONATE:-${OWNER_DONATE:-https://evey.cc/donate.html}}"
  ID_AGENT_PEER="${ID_AGENT_PEER:-${AGENT_PEER:-mother}}"
  ID_PATHS_ROOT="${ID_PATHS_ROOT:-${PATHS_ROOT:-/mnt/v/evey}}"
  export ID_OWNER_NAME ID_OWNER_SLUG ID_OWNER_HANDLE ID_OWNER_EMAIL ID_OWNER_DOMAIN ID_OWNER_DONATE ID_AGENT_PEER ID_PATHS_ROOT
}

# --- helpers for pure bash impl ---
title_case() {
  local v="$1"
  [ -z "$v" ] && { echo ""; return 0; }
  local f
  f=$(printf '%s' "${v:0:1}" | tr '[:lower:]' '[:upper:]')
  printf '%s%s' "$f" "${v:1}"
}

encode_b64() {
  local s="$1"
  if [ -z "$s" ]; then echo -n ""; return 0; fi
  printf '%s' "$s" | openssl base64 -A 2>/dev/null | tr -d '\n' || printf '%s' "$s" | base64 2>/dev/null | tr -d '\n' || true
}

decode_b64() {
  local s="$1"
  if [ -z "$s" ]; then echo -n ""; return 0; fi
  printf '%s' "$s" | openssl base64 -d -A 2>/dev/null || printf '%s' "$s" | base64 -d 2>/dev/null || true
}

json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  printf '%s' "$s"
}

# --- SCAN: find hits of seed tokens + variants. Output delimited lines: repo|file|line|layer|before|text?
# Pure bash, no python. Delim chosen for easy parse in bash tests.
identity_scan() {
  local ws="$1"
  local repos_csv="${2:-$(identity_default_members)}"
  local seed_file="${3:-$(identity_seed_path)}"
  [ -d "$ws" ] || { echo ""; return 0; }
  [ -f "$seed_file" ] || { echo ""; return 0; }

  local old_n old_s ; old_n="${ID_OWNER_NAME:-}"; old_s="${ID_OWNER_SLUG:-}"
  identity_load_toml "$seed_file"
  local seed_name="$ID_OWNER_NAME"
  local seed_slug="$ID_OWNER_SLUG"
  local seed_handle="$ID_OWNER_HANDLE"
  local seed_email="$ID_OWNER_EMAIL"
  local seed_domain="$ID_OWNER_DOMAIN"
  local seed_donate="$ID_OWNER_DONATE"
  local seed_peer="$ID_AGENT_PEER"
  local seed_root="$ID_PATHS_ROOT"
  ID_OWNER_NAME="$old_n"; ID_OWNER_SLUG="$old_s"

  local -a variants=()
  addv() { [ -n "$1" ] && variants+=("$1"); }
  addv "$seed_name"; addv "$(title_case "$seed_name")"; addv "$(echo "$seed_name" | tr '[:upper:]' '[:lower:]')"
  addv "$seed_slug"; addv "$(echo "$seed_slug" | tr '[:upper:]' '[:lower:]')"
  addv "$seed_handle"
  addv "$seed_email"
  addv "$seed_domain"
  addv "$seed_donate"
  addv "$seed_peer"; addv "$(title_case "$seed_peer")"
  addv "$seed_root"

  local infra_str="$(identity_infra_excludes)"
  local -a repos_a
  IFS=',' read -ra repos_a <<< "$repos_csv"

  local hits=""
  local slug_low="$seed_slug"
  for repo in "${repos_a[@]}"; do
    repo=$(echo "$repo" | tr -d '[:space:]')
    [ -z "$repo" ] && continue
    local rdir="$ws/$repo"
    [ -d "$rdir" ] || continue

    # file content hits
    while IFS= read -r -d '' fpath; do
      local skip=0
      for ex in $infra_str; do
        if [[ "$fpath" == *"/$ex/"* || "$fpath" == *"/$ex" ]]; then skip=1; break; fi
      done
      [ $skip -eq 1 ] && continue
      local rel="${fpath#$rdir/}"
      [ "$rel" = "$fpath" ] && rel=$(basename "$fpath")
      local lineno=0
      while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno+1))
        for var in "${variants[@]}"; do
          [ -z "$var" ] && continue
          if [[ "$line" == *"$var"* ]]; then
            hits="${hits}${repo}|${rel}|${lineno}|unclassified|${var}|${line}"$'\n'
            break
          fi
        done
      done < "$fpath"
    done < <(find "$rdir" -type f \( ! -path '*/.git/*' ! -path '*/__pycache__/*' ! -name '*.pyc' ! -name '*.pyo' \) -print0 2>/dev/null)

    # dir-name hits using seed slug (remove hardcoded generic)
    while IFS= read -r dpath; do
      local bnd
      bnd=$(basename "$dpath")
      local skipd=0
      for ex in $infra_str; do [[ "$dpath" == *"/$ex"* ]] && skipd=1; done
      [ $skipd -eq 1 ] && continue
      if [[ "$bnd" == "${slug_low}-"* || "$bnd" == "$slug_low" ]]; then
        local reld
        if [ "${dpath#$rdir/}" != "$dpath" ]; then reld="${dpath#$rdir/}"; else reld="$bnd"; fi
        if [ "$reld" = "." ] || [ "$reld" = "" ] || [ "$reld" = "$repo" ]; then
          : # do not rename top level member repo dir
        else
          hits="${hits}${repo}|${reld}|0|dir-name|${bnd}"$'\n'
        fi
      fi
    done < <(find "$rdir" -type d \( ! -path '*/.git/*' ! -path '*/__pycache__/*' \) 2>/dev/null | grep -E "(/|^)(${slug_low}-[^/]*|${slug_low})$" || true)
  done

  # dedup
  echo "$hits" | sort | uniq
}

# --- CLASSIFY: read delimited from scan, output same with layer set. Pure bash.
identity_classify_hits() {
  local input
  input=$(cat)
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    local repo file lnum layer before text
    repo=$(echo "$line" | cut -d'|' -f1)
    file=$(echo "$line" | cut -d'|' -f2)
    lnum=$(echo "$line" | cut -d'|' -f3)
    layer=$(echo "$line" | cut -d'|' -f4)
    before=$(echo "$line" | cut -d'|' -f5)
    text=$(echo "$line" | cut -d'|' -f6-)
    local bn
    bn=$(basename "$file" 2>/dev/null || echo "$file")
    if [ "$layer" = "dir-name" ] || [ "$lnum" = "0" ]; then
      layer="dir-name"
    fi
    # test specific structural layers (machine, manifest, plugin.yaml, tool-prefix, mqtt-topic)
    # BEFORE any broad evey-substring match (owner-data, fallback, evey. etc) per design
    if [ "$layer" != "dir-name" ]; then
      if [[ "$text" == */mnt/v/* ]] || [[ "$before" == /mnt/v/* ]]; then
        layer="machine-path"
      elif [ "$bn" = "plugin.json" ] || [ "$bn" = "FUNDING.yml" ] || [ "$bn" = "LICENSE" ] || [[ "$file" == */.github/*FUNDING* ]]; then
        layer="manifest"
      elif [ "$bn" = "plugin.yaml" ] && [[ "$text" == *name:* ]]; then
        layer="plugin.yaml"
      elif [[ "$text" == *evey_* ]] || [[ "$before" == *evey_* ]] || [[ "$text" == *mother_* ]] || [[ "$before" == *mother_* ]] || [[ "$text" == *Mother_* ]] || [[ "$before" == *Mother_* ]] || [[ "$text" == *MOTHER_* ]]; then
        layer="tool-prefix"
      elif [[ "$text" == *evey/bridge* ]] || [[ "$text" == *evey/events* ]] || [[ "$text" == *evey/health* ]] || [[ "$text" == *evey/mother* ]] || [[ "$text" == *mother/#* ]]; then
        layer="mqtt-topic"
      fi
    fi
    if [ "$layer" = "unclassified" ] || [ -z "$layer" ]; then
      if [[ "$text" == *getLogger* ]] || [[ "$text" == *getlogger* ]] || { [[ "$text" == *"evey."* ]] && [[ "$text" != *evey.cc* ]]; } || [[ "$before" == *"evey."* ]]; then
        layer="logger"
      elif [[ "$bn" == README* ]] && { [[ "$text" == *Evey* ]] || [[ "$text" == *evey.cc* ]] || [[ "$text" == *donate* ]] || [[ "$text" == *42-evey* ]]; }; then
        layer="branding"
      elif [[ "$text" == *evey@evey.cc* ]] || [[ "$text" == *evey.cc* ]] || [[ "$before" == *evey@* ]] || [[ "$before" == *evey.cc* ]]; then
        layer="owner-data"
      else
        if [ "$layer" = "unclassified" ] || [ -z "$layer" ]; then
          if [[ "$bn" == README* ]]; then layer="branding"; else layer="owner-data"; fi
        fi
      fi
    fi
    if [ -n "$text" ]; then
      echo "${repo}|${file}|${lnum}|${layer}|${before}|${text}"
    else
      echo "${repo}|${file}|${lnum}|${layer}|${before}"
    fi
  done <<< "$input"
}

# --- REWRITE engine (pure bash) ---
identity_rewrite() {
  local ws="$1"
  local target_toml="$2"
  local repos_csv="${3:-$(identity_default_members)}"

  local seedf="$(identity_seed_path)"
  identity_load_toml "$seedf"
  local sn="$ID_OWNER_NAME" su="$ID_OWNER_SLUG" sh="$ID_OWNER_HANDLE" se="$ID_OWNER_EMAIL"
  local sdom="$ID_OWNER_DOMAIN" sdo="$ID_OWNER_DONATE" spe="$ID_AGENT_PEER" srt="$ID_PATHS_ROOT"

  identity_load_toml "$target_toml"
  local tn="$ID_OWNER_NAME" tu="$ID_OWNER_SLUG" th="$ID_OWNER_HANDLE" te="$ID_OWNER_EMAIL"
  local tdom="$ID_OWNER_DOMAIN" tdo="$ID_OWNER_DONATE" tpe="$ID_AGENT_PEER" trt="$ID_PATHS_ROOT"

  if [ "$sn" = "$tn" ] && [ "$su" = "$tu" ]; then
    echo "already customized (target matches seed), no changes"
    return 0
  fi

  local scan_out
  scan_out=$(identity_scan "$ws" "$repos_csv" "$seedf")
  local hits_lines
  hits_lines=$(echo "$scan_out" | identity_classify_hits)

  local -a dir_renames=()
  local seen_dirs=""
  local lh
  while IFS= read -r lh || [ -n "$lh" ]; do
    [ -z "$lh" ] && continue
    local lrepo lfile llnum llayer lbefore
    lrepo=$(echo "$lh" | cut -d'|' -f1)
    lfile=$(echo "$lh" | cut -d'|' -f2)
    llnum=$(echo "$lh" | cut -d'|' -f3)
    llayer=$(echo "$lh" | cut -d'|' -f4)
    lbefore=$(echo "$lh" | cut -d'|' -f5)
    if [ "$llayer" = "dir-name" ] && [[ "$lbefore" == "${su}-"* || "$lbefore" = "$su" ]]; then
      local newb="${lbefore//${su}-/${tu}-}"
      [ "$lbefore" = "$su" ] && newb="$tu"
      local newf
      if [[ "$lfile" == */* ]]; then
        newf="$(dirname "$lfile")/$newb"
      else
        newf="$newb"
      fi
      if ! echo "$seen_dirs" | grep -qF "|$lfile|"; then
        seen_dirs="$seen_dirs|$lfile|"
        dir_renames+=("$lfile|$newf|$lrepo")
      fi
    fi
  done <<< "$hits_lines"

  # robust dir scan
  local -a rps
  IFS=',' read -ra rps <<< "$repos_csv"
  for rr in "${rps[@]}"; do
    rr=$(echo "$rr" | tr -d '[:space:]')
    local rdir="$ws/$rr"
    [ -d "$rdir" ] || continue
    while IFS= read -r dd; do
      local bb; bb=$(basename "$dd")
      if [[ "$bb" == "${su}-"* || "$bb" = "$su" ]]; then
        local relp="${dd#${rdir}/}"
        [ "$relp" = "$dd" ] && relp="$bb"
        if [ "$relp" = "." ] || [ "$relp" = "" ] || [ "$relp" = "$rr" ]; then
          : # skip top-level member repo dir
        else
          local nnb="${bb//${su}-/${tu}-}"; [ "$bb" = "$su" ] && nnb="$tu"
          local newf
          if [[ "$relp" == */* ]]; then
            newf="$(dirname "$relp")/$nnb"
          else
            newf="$nnb"
          fi
          if ! echo " ${dir_renames[*]} " | grep -q " ${relp}|"; then
            dir_renames+=("$relp|$newf|$rr")
          fi
        fi
      fi
    done < <(find "$rdir" -type d 2>/dev/null | grep -E "(/|^)(${su}-[^/]*|${su})$" || true)
  done

  local ledger_path="$ws/.identity-ledger.json"
  local ledger_entries=""
  local recorded_keys=""

  append_ledger() {
    local r="$1" f="$2" ln="$3" la="$4" be="$5" af="$6"
    local key="|$r|$f|$ln|"
    if echo "$recorded_keys" | grep -qF "$key" 2>/dev/null; then
      return 0
    fi
    recorded_keys="${recorded_keys}${key}"
    local be_b64 af_b64 be_esc af_esc
    be_b64=$(encode_b64 "$be")
    af_b64=$(encode_b64 "$af")
    be_esc=$(json_escape "$be")
    af_esc=$(json_escape "$af")
    local ent="{\"repo\":\"$r\",\"file\":\"$f\",\"line\":$ln,\"layer\":\"$la\",\"before\":\"$be_esc\",\"after\":\"$af_esc\",\"b64_before\":\"$be_b64\",\"b64_after\":\"$af_b64\"}"
    if [ -z "$ledger_entries" ]; then
      ledger_entries="$ent"
    else
      ledger_entries="${ledger_entries}
${ent}"
    fi
  }

  apply_replace() {
    local text="$1"
    local out="$text"
    local tpeer; tpeer=$(title_case "$tpe")
    local spe_title; spe_title=$(title_case "$spe")
    # longest specific first (before bare slug/name) to prevent partial like evey.cc -> zeta.cc
    # use loaded seed values (s*) rather than hardcoded generic strings
    [ -n "$sdo" ] && out=${out//$sdo/$tdo}
    [ -n "$se" ] && out=${out//$se/$te}
    [ -n "$sdom" ] && out=${out//$sdom/$tdom}
    [ -n "$sh" ] && out=${out//$sh/$th}
    [ -n "$sn" ] && out=${out//$sn/$tn}
    [ -n "$su" ] && out=${out//$su/$tu}
    [ -n "$spe" ] && out=${out//$spe/$tpe}
    [ -n "$srt" ] && out=${out//$srt/$trt}
    [ -n "$spe_title" ] && out=${out//$spe_title/$tpeer}
    # coupled: use sed for safe prefix (boundary, after string subs); no hardcoded generic "evey"
    out=$(printf '%s' "$out" | sed -E 's/(^|[^A-Za-z0-9_])'"$su"'_/\1'"$tu"'_/g')
    out=$(printf '%s' "$out" | sed -E 's/(^|[^A-Za-z0-9_])'"$spe"'_/\1'"$tpe"'_/g')
    out=$(printf '%s' "$out" | sed -E 's/(^|[^A-Za-z0-9_])'"$spe_title"'_/\1'"$tpeer"'_/g')
    out=$(printf '%s' "$out" | sed -E 's/(^|[^A-Za-z0-9_])'"$su"'\./\1'"$tu"'./g')
    out=$(printf '%s' "$out" | sed -E 's|'"$su"'/|'"$tu"'/|g')
    out=$(printf '%s' "$out" | sed -E 's|'"$spe"'/|'"$tpe"'/|g')
    out=$(printf '%s' "$out" | sed -E 's|'"$spe_title"'/|'"$tpeer"'/|g')
    printf '%s' "$out"
  }

  # Pre-record using sweep of all files (pre-edit) + classify FIRST.
  # This ensures classify/sweep record EVERY rewritten layer (mqtt-topic, tool-prefix,
  # manifest, machine-path, plugin.yaml, logger, branding, owner-data) by testing
  # the specific structural layers BEFORE any broad evey-substring match.
  IFS=',' read -ra rps <<< "$repos_csv"
  for rr in "${rps[@]}"; do
    rr=$(echo "$rr" | tr -d '[:space:]')
    local rdir="$ws/$rr"
    [ -d "$rdir" ] || continue
    while IFS= read -r -d '' fp; do
      local relf="${fp#$rdir/}"
      [ "$relf" = "$fp" ] && relf=$(basename "$fp")
      local idx=0
      while IFS= read -r ln || [ -n "$ln" ]; do
        idx=$((idx+1))
        local nn; nn=$(apply_replace "$ln")
        if [ "$nn" != "$ln" ]; then
          local fake="${rr}|${relf}|${idx}|unclassified|evey|${ln}"
          local la; la=$(echo "$fake" | identity_classify_hits | cut -d'|' -f4 | head -n 1)
          [ -z "$la" ] && la="owner-data"
          append_ledger "$rr" "$relf" "$idx" "$la" "$ln" "$nn"
        fi
      done < "$fp"
    done < <(find "$rdir" -type f \( ! -path '*/.git/*' ! -path '*/__pycache__/*' ! -name '*.pyc' ! -name '*.pyo' \) -print0 2>/dev/null)
  done

  # Pre-record classified changes using exact layer from hits (guarantees...); most will dedup against sweep above
  while IFS= read -r lh || [ -n "$lh" ]; do
    [ -z "$lh" ] && continue
    local lrepo lfile llnum llayer lbefore ltext
    lrepo=$(echo "$lh" | cut -d'|' -f1)
    lfile=$(echo "$lh" | cut -d'|' -f2)
    llnum=$(echo "$lh" | cut -d'|' -f3)
    llayer=$(echo "$lh" | cut -d'|' -f4)
    lbefore=$(echo "$lh" | cut -d'|' -f5)
    ltext=$(echo "$lh" | cut -d'|' -f6-)
    [ "$llayer" = "dir-name" ] && continue
    local origl="${ltext:-$lbefore}"
    [ -z "$origl" ] && continue
    local newl; newl=$(apply_replace "$origl")
    if [ "$newl" != "$origl" ]; then
      # re-classify using full origl via classify to ensure specific structural layer (not broad) even from hits path
      local fake="${lrepo}|${lfile}|${llnum}|unclassified|evey|${origl}"
      local la; la=$(echo "$fake" | identity_classify_hits | cut -d'|' -f4 | head -n 1)
      [ -z "$la" ] && la="$llayer"
      append_ledger "$lrepo" "$lfile" "$llnum" "$la" "$origl" "$newl"
    fi
  done <<< "$hits_lines"

  # hits content
  while IFS= read -r lh || [ -n "$lh" ]; do
    [ -z "$lh" ] && continue
    local repo file lnum layer before
    repo=$(echo "$lh" | cut -d'|' -f1)
    file=$(echo "$lh" | cut -d'|' -f2)
    lnum=$(echo "$lh" | cut -d'|' -f3)
    layer=$(echo "$lh" | cut -d'|' -f4)
    before=$(echo "$lh" | cut -d'|' -f5)
    [ "$layer" = "dir-name" ] && continue
    local fpath="$ws/$repo/$file"
    [ -f "$fpath" ] || continue
    local tmpf; tmpf=$(mktemp)
    local idx=0 chg=0
    while IFS= read -r ln || [ -n "$ln" ]; do
      idx=$((idx+1))
      local newl; newl=$(apply_replace "$ln")
      if [ "$newl" != "$ln" ]; then
        chg=1
        printf '%s\n' "$newl" >> "$tmpf"
      else
        printf '%s\n' "$ln" >> "$tmpf"
      fi
    done < "$fpath"
    if [ $chg -eq 1 ]; then cat "$tmpf" > "$fpath"; fi
    rm -f "$tmpf"
  done <<< "$hits_lines"

  # full sweep for guarantee no half-renames and zero stales
  for rr in "${rps[@]}"; do
    rr=$(echo "$rr" | tr -d '[:space:]')
    local rdir="$ws/$rr"
    [ -d "$rdir" ] || continue
    while IFS= read -r -d '' fp; do
      local relf="${fp#$rdir/}"
      [ "$relf" = "$fp" ] && relf=$(basename "$fp")
      local tmpf; tmpf=$(mktemp)
      local idx=0 chg=0
      while IFS= read -r ln || [ -n "$ln" ]; do
        idx=$((idx+1))
        local nn; nn=$(apply_replace "$ln")
        if [ "$nn" != "$ln" ]; then
          chg=1
          printf '%s\n' "$nn" >> "$tmpf"
        else
          printf '%s\n' "$ln" >> "$tmpf"
        fi
      done < "$fp"
      if [ $chg -eq 1 ]; then cat "$tmpf" > "$fp"; fi
      rm -f "$tmpf"
    done < <(find "$rdir" -type f \( ! -path '*/.git/*' ! -path '*/__pycache__/*' ! -name '*.pyc' ! -name '*.pyo' \) -print0 2>/dev/null)
  done

  # dir renames
  for dent in "${dir_renames[@]}"; do
    local oldrel newrel repo
    oldrel=$(echo "$dent" | cut -d'|' -f1)
    newrel=$(echo "$dent" | cut -d'|' -f2)
    repo=$(echo "$dent" | cut -d'|' -f3)
    local oldf="$ws/$repo/$oldrel"
    local newf="$ws/$repo/$newrel"
    if [ -d "$oldf" ] && [ ! -e "$newf" ]; then
      append_ledger "$repo" "$oldrel" "0" "dir-name" "$oldrel" "$newrel"
      mkdir -p "$(dirname "$newf")" 2>/dev/null || true
      mv "$oldf" "$newf" 2>/dev/null || true
    fi
  done

  # ensure plugin.yaml name rewrites
  for rr in "${rps[@]}"; do
    rr=$(echo "$rr" | tr -d '[:space:]')
    local rdir="$ws/$rr"
    [ -d "$rdir" ] || continue
    while IFS= read -r -d '' pyf; do
      local cont newc
      cont=$(cat "$pyf")
      newc=$(printf '%s' "$cont" | sed -E 's/(name:[[:space:]]*["'\'']?)[[:space:]]*'"${su}"'-/\1'"$tu"'-/g')
      if [ "$newc" != "$cont" ]; then
        printf '%s' "$newc" > "$pyf"
        # Note: plugin.yaml name: changes are already pre-recorded in ledger via classify+pre-record
        # (with correct "plugin.yaml" layer and line-granular before/after for --revert)
      fi
    done < <(find "$rdir" -name "plugin.yaml" -print0 2>/dev/null)
  done

  : "${recorded_keys:-}"
  echo "$ledger_entries" > "$ledger_path"

  # gitignore ledger
  local gitig="$ws/.gitignore"
  if [ -f "$gitig" ]; then
    if ! grep -q '.identity-ledger.json' "$gitig" 2>/dev/null; then
      echo "/.identity-ledger.json" >> "$gitig"
    fi
  else
    printf '# customization ledger\n/.identity-ledger.json\n' > "$gitig"
  fi

  echo "rewrite complete"
}

# --- VERIFY (pure bash): re-scan seed tokens, exclude infra+hermes-agent, print file:line exit nonzero on any ---
identity_verify() {
  local ws="$1"
  local repos_csv="${2:-$(identity_default_members)}"
  local seed_file="${3:-$(identity_seed_path)}"

  [ -d "$ws" ] || { echo "verify: no ws"; return 1; }
  [ -f "$seed_file" ] || { echo "verify: no seed"; return 1; }

  local oldn oldsl ; oldn="${ID_OWNER_NAME:-}"; oldsl="${ID_OWNER_SLUG:-}"
  identity_load_toml "$seed_file"
  local sn="$ID_OWNER_NAME" su="$ID_OWNER_SLUG" sh="$ID_OWNER_HANDLE" se="$ID_OWNER_EMAIL"
  local sd="$ID_OWNER_DOMAIN" sdo="$ID_OWNER_DONATE" sp="$ID_AGENT_PEER" sr="$ID_PATHS_ROOT"
  ID_OWNER_NAME="$oldn"; ID_OWNER_SLUG="$oldsl"

  local -a vars=()
  vars+=("$sn" "$(title_case "$sn")" "$(echo "$sn" | tr '[:upper:]' '[:lower:]')")
  vars+=("$su" "$(echo "$su" | tr '[:upper:]' '[:lower:]')")
  vars+=("$sh" "$se" "$sd" "$sdo" "$sp" "$(title_case "$sp")" "$sr")

  local -a infs
  read -ra infs <<< "$(identity_infra_excludes) hermes-agent"

  local stales=""
  local -a rps
  IFS=',' read -ra rps <<< "$repos_csv"

  for repo in "${rps[@]}"; do
    repo=$(echo "$repo" | tr -d '[:space:]')
    local rdir="$ws/$repo"
    [ -d "$rdir" ] || continue

    # files
    while IFS= read -r -d '' fp; do
      local skip=0
      for ex in "${infs[@]}"; do
        [[ "$fp" == *"/$ex/"* || "$fp" == *"/$ex" ]] && skip=1 && break
      done
      [ $skip -eq 1 ] && continue
      local lineno=0
      while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno+1))
        for v in "${vars[@]}"; do
          [ -z "$v" ] && continue
          if [[ "$line" == *"$v"* ]]; then
            local rel="${fp#$ws/}"
            stales="${stales}${rel}:${lineno}"$'\n'
            break
          fi
        done
      done < "$fp"
    done < <(find "$rdir" -type f \( ! -path '*/.git/*' \) -print0 2>/dev/null)

    # dirs
    while IFS= read -r dp; do
      local b; b=$(basename "$dp")
      local skipd=0
      for ex in "${infs[@]}"; do [[ "$dp" == *"/$ex"* ]] && skipd=1; done
      [ $skipd -eq 1 ] && continue
      if [[ "$b" == "${su}-"* || "$b" = "$su" ]]; then
        local rel="${dp#$ws/}"
        if [ "$b" = "$repo" ] || [ "$rel" = "$repo" ] || [ "$rel" = "." ]; then
          : # container repo dir itself not a rename target
        else
          stales="${stales}${rel}:0"$'\n'
        fi
      fi
    done < <(find "$rdir" -type d 2>/dev/null | grep -E "(/|^)(${su}-[^/]*|${su})$" || true)
  done

  if [ -n "$stales" ]; then
    printf '%s' "$stales" | sort | uniq | while IFS= read -r s || [ -n "$s" ]; do
      [ -n "$s" ] && echo "$s"
    done
    return 1
  fi
  echo "verify: ZERO stale Evey hits"
  return 0
}

# --- REVERT pure bash replay of ledger ---
identity_revert() {
  local ws="$1"
  local ledger="$ws/.identity-ledger.json"
  [ -f "$ledger" ] || { echo "no ledger at $ledger"; return 1; }

  local tmpd; tmpd=$(mktemp -d)
  local parsed="$tmpd/parsed.txt"
  local dirmapf="$tmpd/dirmap.txt"

  # extract records (ndjson one per line, shell strip tolerant of inner chars)
  > "$parsed"
  local obj
  while IFS= read -r obj || [ -n "$obj" ]; do
    [ -z "$obj" ] && continue
    local rp fl ln la bb ba
    rp=$(printf "%s\n" "$obj" | sed -n 's/.*"repo":"\([^"]*\)".*/\1/p')
    fl=$(printf "%s\n" "$obj" | sed -n 's/.*"file":"\([^"]*\)".*/\1/p')
    ln=$(printf "%s\n" "$obj" | sed -n 's/.*"line":\([0-9]*\).*/\1/p')
    la=$(printf "%s\n" "$obj" | sed -n 's/.*"layer":"\([^"]*\)".*/\1/p')
    bb=$(printf "%s\n" "$obj" | sed -n 's/.*"b64_before":"\([^"]*\)".*/\1/p')
    ba=$(printf "%s\n" "$obj" | sed -n 's/.*"b64_after":"\([^"]*\)".*/\1/p')
    [ -n "$rp" ] && [ -n "$fl" ] && printf "%s|%s|%s|%s|%s|%s\n" "$rp" "$fl" "$ln" "$la" "$bb" "$ba" >> "$parsed"
  done < "$ledger"

  cp "$parsed" "$tmpd/recs.txt" 2>/dev/null || true
  local recf="$tmpd/recs.txt"
  [ -s "$recf" ] || recf="$parsed"
  > "$dirmapf"
  while IFS='|' read -r rp fl ln la bb ba || [ -n "$rp" ]; do
    if [ "$la" = "dir-name" ]; then
      local pre post
      pre=$(decode_b64 "$bb"); [ -z "$pre" ] && pre="$fl"
      post=$(decode_b64 "$ba"); [ -z "$post" ] && post="$fl"
      printf "%s|%s\n" "$pre" "$post" >> "$dirmapf"
    fi
  done < "$recf"

  to_current_rel() {
    local rec="$1"
    while IFS='|' read -r pre post; do
      if [ "$rec" = "$pre" ] || [[ "$rec" == "$pre/"* ]]; then
        echo "${rec/$pre/$post}"
        return 0
      fi
    done < "$dirmapf"
    echo "$rec"
  }

  # revert content first (prefer line num exact restore for byte id)
  while IFS='|' read -r rp fl ln la bb ba || [ -n "$rp" ]; do
    [ "$la" = "dir-name" ] && continue
    [ -z "$rp$fl" ] && continue
    local cur; cur=$(to_current_rel "$fl")
    local full="$ws/$rp/$cur"
    if [ -f "$full" ]; then
      local bef
      bef=$(decode_b64 "$bb")
      if [ "$ln" -gt 0 ] 2>/dev/null; then
        awk -v n="$ln" -v b="$bef" "
          NR==n { print b; next }
          { print }
        " "$full" > "$full.tmp" && mv "$full.tmp" "$full" 2>/dev/null || true
      elif [ -n "$bef" ]; then
        # fallback string for safety
        grep -q -F "$bef" "$full" 2>/dev/null || true
      fi
    fi
  done < "$recf"

  # revert dirs
  while IFS='|' read -r rp fl ln la bb ba || [ -n "$rp" ]; do
    [ "$la" != "dir-name" ] && continue
    local pre post
    pre=$(decode_b64 "$bb"); [ -z "$pre" ] && pre="$fl"
    post=$(decode_b64 "$ba"); [ -z "$post" ] && post="$fl"
    local curf="$ws/$rp/$post"
    local tgt="$ws/$rp/$pre"
    if [ -d "$curf" ] && [ ! -e "$tgt" ]; then
      mkdir -p "$(dirname "$tgt")" 2>/dev/null || true
      mv "$curf" "$tgt" 2>/dev/null || true
    fi
  done < "$parsed"

  rm -f "$ledger"
  # restore gitignore if we appended the ledger line
  local gi="$ws/.gitignore"
  if [ -f "$gi" ]; then
    grep -v ".identity-ledger.json" "$gi" > "$gi.tmp" 2>/dev/null || true
    mv "$gi.tmp" "$gi" 2>/dev/null || true
  fi
  rm -rf "$tmpd"
  echo "revert complete"
  return 0
}

# --- run entry ---
identity_run() {
  local ws="$1"
  local identity_file="$2"
  local repos_csv="${3:-$(identity_default_members)}"

  [ -d "$ws" ] || { echo "workspace not found: $ws" >&2; return 1; }

  local seedf="$(identity_seed_path)"
  [ -f "$seedf" ] || { echo "seed not found"; return 1; }

  local stales
  stales=$(identity_verify "$ws" "$repos_csv" "$seedf" 2>&1 || true)
  if [ -z "$stales" ] || ! echo "$stales" | grep -qE ':[0-9]+|evey-'; then
    if [ -f "$ws/.identity-ledger.json" ]; then
      echo "already customized, no changes"
      return 0
    fi
  fi

  if [ -z "$identity_file" ] || [ ! -f "$identity_file" ]; then
    echo "no --identity file or not found" >&2
    return 2
  fi

  identity_rewrite "$ws" "$identity_file" "$repos_csv"

  local vout
  vout=$(identity_verify "$ws" "$repos_csv" "$seedf" 2>&1)
  local vrc=$?
  if [ $vrc -ne 0 ]; then
    echo "$vout" >&2
    echo "VERIFY FAILED: stale Evey tokens survive" >&2
    return 3
  fi
  echo "customize complete"
  return 0
}

# end of lib/identity.sh
