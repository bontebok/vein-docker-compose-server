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
"/opt/scripts/generate-configs.sh"

# Update/Install Vein Server
# The steamcmd base image has a script to handle updates/installs.
# It uses LOGIN, PASSWORD, APPID, APP_UPDATE_FLAGS, VALIDATE_APP
echo "Updating/Installing Vein Dedicated Server (AppID: ${STEAMAPPID})..."
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
SERVER_ARGS="${SERVER_ARGS} -QueryPort=${GAME_ONLINE_SUBSYSTEM_STEAM_GameServerQueryPort:-27015}"
SERVER_ARGS="${SERVER_ARGS} -Port=${GAME_URL_Port:-7777}"

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
