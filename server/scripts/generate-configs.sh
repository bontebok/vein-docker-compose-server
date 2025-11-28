#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
#  Requirements
# ---------------------------------------------------------------------------

if ! command -v crudini >/dev/null 2>&1; then
  echo "ERROR: crudini is not installed or not in PATH." >&2
  echo "       Install it (e.g. 'apt install crudini' or 'yum install crudini')." >&2
  exit 1
fi

if [[ -z "${CONFIG_PATH:-}" ]]; then
  echo "ERROR: CONFIG_PATH is not set." >&2
  exit 1
fi

mkdir -p "$CONFIG_PATH"

GAME_INI="${CONFIG_PATH}/Game.ini"
ENGINE_INI="${CONFIG_PATH}/Engine.ini"

# Ensure files exist so crudini and awk always have something to work with
touch "$GAME_INI" "$ENGINE_INI"

# ---------------------------------------------------------------------------
#  Mapping:  file | section (NO brackets) | env-prefix
#  (Flipped mapping per your request)
# ---------------------------------------------------------------------------

CONFIG_MAP=(
  # Game.ini (was Engine.ini before)
  "Game.ini|/Script/Engine.GameSession|GAME_GAMESESSION_"
  "Game.ini|/Script/Vein.VeinGameSession|GAME_VEIN_GAMESESSION_"
  "Game.ini|OnlineSubsystemSteam|GAME_ONLINE_SUBSYSTEM_STEAM_"
  "Game.ini|URL|GAME_URL_"
  "Game.ini|/Script/Vein.ServerSettings|GAME_SERVERSETTINGS_"

  # Engine.ini (was Game.ini before)
  "Engine.ini|Core.Log|ENGINE_CORE_LOG_"
  "Engine.ini|ConsoleVariables|ENGINE_CONSOLEVARIABLES_"
)

# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------

# Decode env-safe key names:
#   _DOT_        -> '.'
#   _UNDERSCORE_ -> '_'
decode_key() {
  local raw="$1"
  raw="${raw//_DOT_/.}"
  raw="${raw//_UNDERSCORE_/_}"
  printf '%s' "$raw"
}

# Escape key name for use in a sed regex (we only need to care about '.')
escape_key_for_sed() {
  local k="$1"
  k="${k//./\\.}"   # escape dots
  printf '%s' "$k"
}

# Special handler for multi-value keys in /Script/Vein.VeinGameSession:
#   - SuperAdminSteamIDs
#   - AdminSteamIDs
#
# Values are given as a comma-separated list in the environment, e.g.:
#   ENGINE_VEIN_GAMESESSION_SuperAdminSteamIDs="123,456,789"
#
# This writes:
#   SuperAdminSteamIDs=123
#   +SuperAdminSteamIDs=456
#   +SuperAdminSteamIDs=789
#
# If the value is empty, all existing entries for that key in that section
# are removed.
set_multi_steam_ids() {
  local ini_path="$1"   # e.g. /path/to/Game.ini
  local section="$2"    # e.g. /Script/Vein.VeinGameSession (no brackets)
  local key="$3"        # SuperAdminSteamIDs or AdminSteamIDs
  local raw="$4"        # comma-separated list of IDs

  local section_header="[$section]"

  # Split comma-separated list into an array
  IFS=',' read -r -a ids <<< "$raw"

  # Build the text block for this key
  local block=""
  if ((${#ids[@]} > 0)) && [[ -n "${ids[0]}" ]]; then
    block="$key=${ids[0]}"
    local i
    for (( i=1; i<${#ids[@]}; i++ )); do
      [[ -z "${ids[$i]}" ]] && continue
      block+=$'\n'"+$key=${ids[$i]}"
    done
  fi

  # If section does not exist yet and we have something to write, append it
  if ! grep -Fxq "$section_header" "$ini_path"; then
    if [[ -n "$block" ]]; then
      {
        echo
        echo "$section_header"
        printf '%s\n' "$block"
      } >> "$ini_path"
    fi
    return
  fi

  # Otherwise rewrite file:
  #  - Within the target section, drop any existing key/+key lines
  #  - When we see the section header, print it and then our new block (if any)
  local tmp
  tmp="$(mktemp)"

  awk -v section="$section" -v key="$key" -v block="$block" '
    BEGIN { in_section = 0 }
    {
      # Exact match for section header in file: [section]
      if ($0 == "[" section "]") {
        in_section = 1
        print
        if (block != "") {
          print block
        }
        next
      }

      # Any line that looks like a section header
      if ($0 ~ /^\[.*\]/) {
        in_section = ($0 == "[" section "]")
      }

      # Inside target section: drop lines that start with key= or +key=
      if (in_section &&
          (index($0, key "=") == 1 || index($0, "+" key "=") == 1)) {
        next
      }

      print
    }
  ' "$ini_path" > "$tmp"

  mv "$tmp" "$ini_path"
}

# ---------------------------------------------------------------------------
#  Main logic
# ---------------------------------------------------------------------------

for entry in "${CONFIG_MAP[@]}"; do
  IFS="|" read -r file section prefix <<< "$entry"
  ini_path="${CONFIG_PATH}/${file}"

  # Find all environment variables that start with this prefix
  mapfile -t vars < <(compgen -v "$prefix" || true)
  (( ${#vars[@]} == 0 )) && continue

  for var in "${vars[@]}"; do
    encoded_name="${var#"$prefix"}"
    key="$(decode_key "$encoded_name")"
    value="${!var}"

    # Special case: multi-value SteamID keys in /Script/Vein.VeinGameSession
    if [[ "$section" == "/Script/Vein.VeinGameSession" ]] && \
       { [[ "$key" == "SuperAdminSteamIDs" ]] || [[ "$key" == "AdminSteamIDs" ]]; }; then
      set_multi_steam_ids "$ini_path" "$section" "$key" "$value"
      continue
    fi

    # Normal keys: use crudini (adds/updates; preserves everything else)
    crudini --set "$ini_path" "$section" "$key" "$value"

    # Formatting fix: strip spaces around '=' for this key
    # crudini typically writes "Key = Value"; we normalize to "Key=Value".
    escaped_key="$(escape_key_for_sed "$key")"
    sed -i -E "s/^(${escaped_key})[[:space:]]*=[[:space:]]*/\1=/" "$ini_path"
  done
done

echo "Updated INI files:"
echo "  $GAME_INI"
echo "  $ENGINE_INI"
