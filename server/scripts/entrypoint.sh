#!/bin/bash

# If running as root, re-execute this script as the steam user
if [ "$(id -u)" = "0" ]; then
    # Ensure gosu is available, install if not (Debian-based)
    if ! command -v gosu > /dev/null; then
        echo "gosu not found, attempting to install..."
        # Assuming apt is available. Add error handling if needed for other distros.
        # This part might need adjustment if the base image isn't Debian-like or if apt needs root.
        # Since we are root here, apt-get should work.
        apt-get update && apt-get install -y --no-install-recommends gosu && rm -rf /var/lib/apt/lists/*
        if ! command -v gosu > /dev/null; then
            echo "Failed to install gosu. Exiting."
            exit 1
        fi
    fi
    echo "Switching to user steam..."
    exec gosu steam "$0" "$@"
fi

# The rest of the script will now run as steam user

set -e # Exit immediately if a command exits with a non-zero status.

# Create config directory if it doesn't exist (it should from Dockerfile, but just in case)
mkdir -p "${CONFIG_PATH}"

GAME_INI_PATH="${CONFIG_PATH}/Game.ini"
ENGINE_INI_PATH="${CONFIG_PATH}/Engine.ini"

# Start with clean config files each time or check if they exist?
# For simplicity, this script will overwrite them based on ENV vars on each start.
# If you want to preserve manual changes, you'd need a more complex logic
# to check if ENVs are set and only then override specific lines.

echo "Generating ${GAME_INI_PATH}..."
cat > "${GAME_INI_PATH}" <<- EOM
[/Script/Engine.GameSession]
MaxPlayers=${MAX_PLAYERS:-16}

[/Script/Vein.VeinGameSession]
ServerName="${SERVER_NAME:-Vein Docker Server}"
ServerDescription="${SERVER_DESCRIPTION}"
BindAddr=${SERVER_BIND_ADDR:-0.0.0.0}
HeartbeatInterval=${HEARTBEAT_INTERVAL:-5.0}
EOM

if [ "${SERVER_PUBLIC,,}" == "false" ]; then
    echo "bPublic=False" >> "${GAME_INI_PATH}"
else
    echo "bPublic=True" >> "${GAME_INI_PATH}"
fi

if [ -n "${SERVER_PASSWORD}" ]; then
    echo "Password=${SERVER_PASSWORD}" >> "${GAME_INI_PATH}"
fi

# Handle AdminSteamIDs and SuperAdminSteamIDs
OLD_IFS="$IFS"
IFS=','; # comma is set as delimiter

if [ -n "${SUPER_ADMIN_STEAM_IDS}" ]; then
    set -- ${SUPER_ADMIN_STEAM_IDS} # convert to positional parameters
    echo "SuperAdminSteamIDs=$1" >> "${GAME_INI_PATH}"
    shift # remove the first one
    for id in "$@"; do # iterate over the rest
        echo "+SuperAdminSteamIDs=$id" >> "${GAME_INI_PATH}"
    done
fi

if [ -n "${ADMIN_STEAM_IDS}" ]; then
    set -- ${ADMIN_STEAM_IDS} # convert to positional parameters
    echo "AdminSteamIDs=$1" >> "${GAME_INI_PATH}"
    shift # remove the first one
    for id in "$@"; do # iterate over the rest
        echo "+AdminSteamIDs=$id" >> "${GAME_INI_PATH}"
    done
fi

IFS="$OLD_IFS"

cat >> "${GAME_INI_PATH}" <<- EOM

[OnlineSubsystemSteam]
GameServerQueryPort=${GAME_SERVER_QUERY_PORT:-27015}
bVACEnabled=${VAC_ENABLED:-0}

[URL]
Port=${GAME_PORT:-7777}
EOM

# [/Script/Vein.ServerSettings] - Add only if relevant variables are set
SERVER_SETTINGS_HEADER_ADDED=false
ensure_server_settings_header() {
    if [ "$SERVER_SETTINGS_HEADER_ADDED" = false ]; then
        echo -e "\n[/Script/Vein.ServerSettings]" >> "${GAME_INI_PATH}"
        SERVER_SETTINGS_HEADER_ADDED=true
    fi
}

if [ -n "${GS_SHOW_SCOREBOARD_BADGES}" ]; then
    ensure_server_settings_header
    echo "GS_ShowScoreboardBadges=${GS_SHOW_SCOREBOARD_BADGES}" >> "${GAME_INI_PATH}"
fi

if [ -n "${DISCORD_WEBHOOK_URL}" ]; then
    ensure_server_settings_header
    echo "DiscordChatWebhookURL=\"${DISCORD_WEBHOOK_URL}\"" >> "${GAME_INI_PATH}"
fi

if [ -n "${DISCORD_ADMIN_WEBHOOK_URL}" ]; then
    ensure_server_settings_header
    echo "DiscordChatAdminWebhookURL=\"${DISCORD_ADMIN_WEBHOOK_URL}\"" >> "${GAME_INI_PATH}"
fi

echo "${GAME_INI_PATH} generated."

echo "Generating ${ENGINE_INI_PATH}..."
cat > "${ENGINE_INI_PATH}" <<- EOM
[URL]
Port=${GAME_PORT:-7777}

[Core.Log]
LogOnlineSession=Warning
LogOnline=Warning
EOM

# Engine.ini - [ConsoleVariables]
CONSOLE_VARIABLES_HEADER_ADDED=false
ensure_console_variables_header() {
    if [ "$CONSOLE_VARIABLES_HEADER_ADDED" = false ]; then
        echo -e "\n[ConsoleVariables]" >> "${ENGINE_INI_PATH}"
        CONSOLE_VARIABLES_HEADER_ADDED=true
    fi
}

# Loop through all environment variables prefixed with CVAR_
for var in $(env | grep "^CVAR_"); do
    ensure_console_variables_header
    # Extract variable name after CVAR_ and its value
    cvar_name=$(echo "$var" | sed -e 's/^CVAR_//' -e 's/=.*//')
    cvar_value=$(echo "$var" | sed 's/^[^=]*=//')
    echo "${cvar_name}=${cvar_value}" >> "${ENGINE_INI_PATH}"
done

echo "${ENGINE_INI_PATH} generated."

# Update/Install Vein Server
# The steamcmd base image has a script to handle updates/installs.
# It uses LOGIN, PASSWORD, APPID, APP_UPDATE_FLAGS, VALIDATE_APP
echo "Updating/Installing Vein Dedicated Server (AppID: ${APPID})..."
${STEAMCMDDIR}/steamcmd.sh +force_install_dir ${SERVER_PATH} \
                                 +login ${STEAMLOGIN} \
                                 +app_update ${STEAMAPPID} validate \
                                 +quit

# Fix for steamclient.so if needed (common issue on Linux)
# Check if the target directory exists, then create symlink
STEAMCMD_LINUX64_PATH="${STEAMCMDDIR}/linux64"
SDK64_PATH="${HOME}/.steam/sdk64"
STEAMCLIENT_SO="steamclient.so"

if [ -f "${STEAMCMD_LINUX64_PATH}/${STEAMCLIENT_SO}" ]; then
    mkdir -p "${SDK64_PATH}"
    if [ ! -L "${SDK64_PATH}/${STEAMCLIENT_SO}" ]; then # If not a symlink or doesn't exist
        ln -sf "${STEAMCMD_LINUX64_PATH}/${STEAMCLIENT_SO}" "${SDK64_PATH}/${STEAMCLIENT_SO}"
        echo "Symlinked steamclient.so for SteamAPI."
    fi
elif [ -f "${SERVER_PATH}/${STEAMCLIENT_SO}" ]; then # Sometimes it's in the server dir
    mkdir -p "${SDK64_PATH}"
    if [ ! -L "${SDK64_PATH}/${STEAMCLIENT_SO}" ]; then
        ln -sf "${SERVER_PATH}/${STEAMCLIENT_SO}" "${SDK64_PATH}/${STEAMCLIENT_SO}"
        echo "Symlinked steamclient.so from server directory for SteamAPI."
    fi
else
    echo "Warning: steamclient.so not found in common SteamCMD paths or server directory. SteamAPI might fail."
fi

# Construct server arguments
SERVER_ARGS="-log"
SERVER_ARGS="${SERVER_ARGS} -QueryPort=${GAME_SERVER_QUERY_PORT:-27015}"
SERVER_ARGS="${SERVER_ARGS} -Port=${GAME_PORT:-7777}"

# Add multihome if specified
if [ -n "${SERVER_MULTIHOME_IP}" ]; then
    SERVER_ARGS="${SERVER_ARGS} -multihome=${SERVER_MULTIHOME_IP}"
fi

# Pass through any additional arguments provided to the docker run command
if [ $# -gt 0 ]; then
    SERVER_ARGS="${SERVER_ARGS} $@"
fi

echo "Starting Vein Server with arguments: ${SERVER_ARGS}"

# Navigate to the server directory and execute
cd "${SERVER_PATH}"

# The executable is VeinServer.sh according to docs
if [ -f "./VeinServer.sh" ]; then
    exec ./VeinServer.sh ${SERVER_ARGS}
elif [ -f "./VeinServer" ]; then # Fallback if .sh is not present or for some reason it's just VeinServer
    exec ./VeinServer ${SERVER_ARGS}
else
    echo "Error: VeinServer.sh or VeinServer executable not found in ${SERVER_PATH}."
    echo "Please check the installation."
    exit 1
fi
