FROM	debian:trixie-slim AS build

ARG	HOSTUSERID=1000 \
	HOSTGROUPID=1000 \
	USER=steam

ENV	STEAMAPPID=2131400 \
	STEAMCMDDIR=/opt/steamcmd \
	STEAMAPPDIR=/opt/steamapp \
	SCRIPTDIR=/opt/scripts \
	STEAMLOGIN=anonymous \
	STEAMCMDURL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
	HOSTUSERID=${HOSTUSERID} \
	HOSTGROUPID=${HOSTGROUPID} \
	USER=${USER}

# Environment variables for server installation and paths
ENV	SERVER_PATH=${STEAMAPPDIR}/vein-server \
	CONFIG_DIR_NAME=LinuxServer
ENV	CONFIG_PATH=${SERVER_PATH}/Vein/Saved/Config/${CONFIG_DIR_NAME}

# Update and install Vein dependencies
RUN	set -x && \
	dpkg --add-architecture i386 && \
	apt update -y && apt dist-upgrade -y && \
	apt install --no-install-recommends -y \
		lib32gcc-s1 libc6-dev ca-certificates adduser tar gzip \
		curl libatomic1 libasound2-dev libpulse-dev

# Clean up
RUN	apt-get -y clean && rm -rf /var/lib/{apt,dpkg,cache}

# Add locales
RUN	DEBIAN_FRONTEND=noninteractive apt-get install -y locales && \
	sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
	sed -i -e 's/# en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen && \
	dpkg-reconfigure --frontend=noninteractive locales && \
	update-locale LANG=en_US.UTF-8 && \
	update-locale LANG=en_GB.UTF-8

ENV	LANG en_US.UTF-8

# Create user, install SteamCMD
RUN	addgroup --gid ${HOSTGROUPID} ${USER}

RUN	adduser --disabled-login \
		--shell /bin/bash \
		--gecos "" \
		--gid ${HOSTGROUPID} \
		--uid ${HOSTUSERID} \
		${USER}

RUN	mkdir -p ${STEAMCMDDIR} ${STEAMAPPDIR} ${SCRIPTDIR} ${SERVER_PATH} ${CONFIG_PATH} && \
	chown -R ${USER}:${USER} ${STEAMCMDDIR} ${STEAMAPPDIR} ${SCRIPTDIR}

# Copy setup and startup scripts
COPY	--chown=${USER}:${USER} scripts ${SCRIPTDIR}

# Switch user context
USER	${USER}

# Install steamcmd
RUN	cd ${STEAMCMDDIR} && \
	curl -sqL ${STEAMCMDURL} | tar zxvf -

# Ports to expose (UDP)
# These are defaults; actual ports used depend on GAME_PORT and GAME_SERVER_QUERY_PORT ENV vars
EXPOSE	7777/udp
EXPOSE	27015/udp

WORKDIR	${SERVER_PATH}

# Volume for persistent data (game saves, potentially logs if not stdout)
VOLUME	${SERVER_PATH}/Vein/Saved

# Set the entrypoint
ENTRYPOINT ["/opt/scripts/entrypoint.sh"]

# Default command passed to entrypoint.sh (can be overridden)
# The entrypoint script will add essential args like -log, -Port, -QueryPort

#CMD []
