# Space Engineers - Dedicated Server (Steam App: 298740)
# Pas de binaire Linux natif : SpaceEngineersDedicated.exe tourne sous Wine + Xvfb.
#
# Build :   docker compose build
# Lancer :  docker compose up -d
#
# Base : cm2network/steamcmd:root (Debian 13 trixie), épinglée par digest SHA256.
# Pour mettre à jour la base : docker pull cm2network/steamcmd:root puis
#   docker inspect --format='{{index .RepoDigests 0}}' cm2network/steamcmd:root
FROM cm2network/steamcmd@sha256:e6b6b3503bf0e41feafe12dc709c90151afba193e1292cac55d28a7d470b1493

# Version WineHQ épinglée (dépôt officiel WineHQ, plus récent que Wine Debian).
# La branche 10.x est celle utilisée avec succès par des images communautaires
# récentes pour installer .NET 4.8 (étape la plus fragile).
ARG WINE_VERSION=10.0.0.0~trixie-1

# Note : lib32gcc-s1 / lib32stdc++6 (SteamCMD 32 bits) sont déjà dans l'image de base.
# i386 reste nécessaire : le paquet WineHQ complet et l'installeur .NET 4.8
# posent les deux architectures.
#   gosu      : abandon des droits root vers l'utilisateur steam (PUID/PGID)
#   tini      : PID 1 minimal (relais des signaux, ramassage des zombies)
#   xvfb      : écran virtuel exigé par Wine et par les installeurs winetricks
#   winbind   : NTLM, utilisé par certains composants .NET sous Wine
#   cabextract/unzip : requis par winetricks pour extraire les installeurs Microsoft
#   procps    : pgrep/pkill pour l'arrêt propre du serveur
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates wget gnupg \
    && mkdir -pm755 /etc/apt/keyrings \
    && wget -qO /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key \
    && wget -qNP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/trixie/winehq-trixie.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        gosu tini procps \
        xvfb xauth winbind cabextract unzip \
    # --no-install-recommends : évite ~1,2 Go de paquets inutiles sur un serveur
    # sans écran (pilotes graphiques mesa/vulkan/llvm, codecs vidéo, GTK, sane…).
    && apt-get install -y --no-install-recommends \
        winehq-stable=${WINE_VERSION} \
        wine-stable=${WINE_VERSION} \
        wine-stable-amd64=${WINE_VERSION} \
        wine-stable-i386=${WINE_VERSION} \
    && rm -rf /var/lib/apt/lists/*

# winetricks depuis le dépôt amont, épinglé sur une version datée
# (le paquet Debian est en retard et ses URL d'installeurs Microsoft cassent).
ARG WINETRICKS_VERSION=20260125
RUN wget -qO /usr/local/bin/winetricks \
        "https://raw.githubusercontent.com/Winetricks/winetricks/${WINETRICKS_VERSION}/src/winetricks" \
    && chmod +x /usr/local/bin/winetricks

# Copie de référence de SteamCMD : le volume partagé ~/volumes/steamcmd peut être
# vide au premier lancement, start_server.sh le remplit depuis cette copie.
RUN cp -a /home/steam/steamcmd /opt/steamcmd-template

ENV SERVER_DIR="/home/steam/se_server" \
    SAVE_DIR="/home/steam/se_saves" \
    CONFIG_DIR="/home/steam/se_config" \
    WINEPREFIX="/home/steam/wineprefix" \
    WINEARCH="win64" \
    WINEDEBUG="-all" \
    LANG="C.UTF-8"

RUN mkdir -p "$SERVER_DIR" "$SAVE_DIR" "$CONFIG_DIR" "$WINEPREFIX" \
    && chown steam:steam "$SERVER_DIR" "$SAVE_DIR" "$CONFIG_DIR" "$WINEPREFIX"

COPY --chown=steam:steam start_server.sh healthcheck.sh /home/steam/
RUN chmod +x /home/steam/start_server.sh /home/steam/healthcheck.sh

WORKDIR /home/steam

# Pas d'EXPOSE : le port de jeu est configurable (GAME_PORT dans .env, 7777 ici,
# 27016 par défaut chez Keen). C'est docker-compose qui le publie.

# Socket UDP GAME_PORT ouverte = monde chargé et serveur à l'écoute.
# start-period long : le 1er démarrage télécharge le jeu et installe .NET 4.8.
HEALTHCHECK --interval=60s --timeout=10s --start-period=120m --retries=3 \
    CMD /home/steam/healthcheck.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/home/steam/start_server.sh"]
