#!/bin/bash
# Space Engineers Dedicated Server — script de démarrage du conteneur.
#   1. Ajuste l'utilisateur steam sur PUID/PGID (seule partie exécutée en root)
#   2. Installe / met à jour le serveur via SteamCMD (3 essais max)
#   3. Initialise le préfixe Wine une seule fois (persistant en volume)
#   4. Prépare SpaceEngineers-Dedicated.cfg
#   5. Lance le serveur sous l'utilisateur steam et gère l'arrêt propre (SIGTERM)

APP_ID=298740
SDK_APP_ID=1007   # Steamworks SDK Redist (DLL Steam à jour, voir étape 2b)
GAME_PORT=${GAME_PORT:-7777}   # Même port côté hôte et conteneur (annoncé à Steam)
EXE_DIR="${SERVER_DIR}/DedicatedServer64"
EXE="${EXE_DIR}/SpaceEngineersDedicated.exe"
CFG_NAME="SpaceEngineers-Dedicated.cfg"
STEAMCMD="/home/steam/steamcmd/steamcmd.sh"
PREFIX_MARKER="${WINEPREFIX}/.se_prefix_ready"

log() { echo "[start_server] $*"; }
as_steam() { gosu steam env HOME=/home/steam "$@"; }

# ── 1. Ajustement UID/GID ──────────────────────────────────────────────────
USER_ID=${PUID:-1000}
GROUP_ID=${PGID:-1000}
log "Utilisateur steam -> UID ${USER_ID} / GID ${GROUP_ID}"
groupmod -o -g "$GROUP_ID" steam
usermod -o -u "$USER_ID" -g "$GROUP_ID" steam

# SteamCMD partagé : si le volume est vide, le remplir depuis la copie de l'image
if [ ! -x "$STEAMCMD" ]; then
    log "Volume SteamCMD vide, copie depuis l'image"
    cp -a /opt/steamcmd-template/. /home/steam/steamcmd/
fi

# Les volumes doivent appartenir à PUID:PGID (voir README, chown côté hôte).
# On ne corrige que s'il le faut : un chown -R sur l'install (plusieurs Go)
# à chaque démarrage serait inutilement long.
for d in "$SERVER_DIR" "$SAVE_DIR" "$CONFIG_DIR" "$WINEPREFIX" /home/steam/steamcmd; do
    if [ "$(stat -c '%u:%g' "$d")" != "${USER_ID}:${GROUP_ID}" ] \
       || [ -n "$(find "$d" -xdev \( ! -uid "$USER_ID" -o ! -gid "$GROUP_ID" \) -print -quit 2>/dev/null)" ]; then
        log "Correction des droits sur $d"
        chown -R "${USER_ID}:${GROUP_ID}" "$d"
    fi
done
chown "${USER_ID}:${GROUP_ID}" /home/steam

# ── Xvfb (écran virtuel requis par Wine et winetricks) ─────────────────────
# Nettoyage des verrous laissés par un arrêt brutal (restart: unless-stopped
# relance le même conteneur, donc le même /tmp).
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix
as_steam Xvfb :99 -screen 0 1024x768x16 -nolisten tcp >/dev/null 2>&1 &
export DISPLAY=:99
for _ in $(seq 1 30); do [ -e /tmp/.X11-unix/X99 ] && break; sleep 1; done
[ -e /tmp/.X11-unix/X99 ] || { log "ERREUR : Xvfb n'a pas démarré"; exit 1; }

# ── 2. Installation / mise à jour via SteamCMD ────────────────────────────
steamcmd_update() {
    # $1 = dossier d'installation, $2 = appid, $3 = "validate" ou vide
    as_steam "$STEAMCMD" \
        +@ShutdownOnFailedCommand 1 \
        +@NoPromptForPassword 1 \
        +@sSteamCmdForcePlatformType windows \
        +force_install_dir "$1" \
        +login anonymous \
        +app_info_update 1 \
        +app_update "$2" $3 \
        +quit
}

if [ "${UPDATE_ON_START:-true}" = "true" ] || [ ! -f "$EXE" ]; then
    log "Auto-mise à jour de SteamCMD"
    as_steam "$STEAMCMD" +quit

    log "Espace libre sur le volume d'installation : $(df -h --output=avail "$SERVER_DIR" | tail -1 | tr -d ' ')"
    ok=0
    for i in 1 2 3; do
        log "Mise à jour Space Engineers (App ${APP_ID}) — tentative ${i}/3"
        if steamcmd_update "$SERVER_DIR" "$APP_ID" validate; then
            ok=1; break
        fi
        log "Échec de la tentative ${i} (ex : 'state is 0x4A6 after update job')"
        # Causes fréquentes : droits, espace disque, téléchargement partiel corrompu.
        if ! as_steam test -w "$SERVER_DIR"; then
            log "ERREUR : $SERVER_DIR n'est pas inscriptible par UID ${USER_ID}"
        fi
        log "Espace libre : $(df -h --output=avail "$SERVER_DIR" | tail -1 | tr -d ' ')"
        # Suppression des téléchargements partiels (sans toucher à l'install)
        rm -rf "${SERVER_DIR}/steamapps/downloading" "${SERVER_DIR}/steamapps/temp"
        [ "$i" -lt 3 ] && { log "Nouvel essai dans $((i * 15)) s"; sleep $((i * 15)); }
    done
    if [ "$ok" -ne 1 ]; then
        if [ -f "$EXE" ]; then
            log "ATTENTION : mise à jour impossible, démarrage sur la version déjà installée"
        else
            log "ERREUR : installation impossible après 3 essais. Voir README (erreur 0x4A6)."
            exit 1
        fi
    fi
else
    log "Mise à jour sautée (UPDATE_ON_START=false)"
fi

[ -f "$EXE" ] || { log "ERREUR : $EXE introuvable"; exit 1; }
BUILD=$(sed -n 's/.*"buildid"[^"]*"\([0-9]*\)".*/\1/p' "${SERVER_DIR}/steamapps/appmanifest_${APP_ID}.acf" 2>/dev/null | head -1)
log "Build installé : ${BUILD:-inconnu}"

# ── 2b. DLL Steam à jour (mods du Workshop) ───────────────────────────────
# Le serveur embarque d'anciennes DLL Steam qui ne savent plus lire le nouveau
# format de stockage du Workshop (depuis mi-2025) : les mods échouent au
# téléchargement. Correctif communautaire : les remplacer par celles du
# Steamworks SDK Redist (App 1007). À refaire après chaque mise à jour.
if [ "${STEAM_DLL_FIX:-true}" = "true" ]; then
    SDK_DIR="${SERVER_DIR}/.steam-sdk-redist"
    if steamcmd_update "$SDK_DIR" "$SDK_APP_ID" validate; then
        for dll in steamclient64.dll tier0_s64.dll vstdlib_s64.dll; do
            src=$(find "$SDK_DIR" -name "$dll" -type f 2>/dev/null | head -1)
            [ -n "$src" ] && as_steam cp -f "$src" "${EXE_DIR}/${dll}" && log "DLL mise à jour : $dll"
        done
    else
        log "ATTENTION : téléchargement du SDK Redist impossible, DLL d'origine conservées"
    fi
fi

# ── 3. Préfixe Wine (une seule fois, persistant) ──────────────────────────
# Dépendances requises par le serveur : .NET Framework 4.8 et VC++ 2019 x64.
# Chaque étape réussie laisse un marqueur : après un échec ou un redémarrage,
# on reprend à l'étape suivante au lieu de tout refaire.
# timeout : une étape bloquée (fenêtre invisible sous Xvfb...) ne doit pas
# figer le démarrage indéfiniment.
prefix_step() {
    local name=$1 max=$2; shift 2
    [ -f "${WINEPREFIX}/.step_${name}" ] && return 0
    log "Préfixe Wine : ${name} (max $((max / 60)) min)"
    if as_steam timeout "$max" "$@"; then
        as_steam timeout 300 wineserver -w
        as_steam touch "${WINEPREFIX}/.step_${name}"
        return 0
    fi
    log "ERREUR : étape '${name}' échouée ou trop longue"
    as_steam wineserver -k 2>/dev/null
    return 1
}

if [ ! -f "$PREFIX_MARKER" ]; then
    log "Initialisation du préfixe Wine (première fois : 15 à 30 minutes)"
    # Préfixe neuf : on part d'un dossier vide (marqueurs compris)
    [ -f "${WINEPREFIX}/.step_wineboot" ] || rm -rf "${WINEPREFIX:?}/"* "${WINEPREFIX:?}"/.step_*
    # mscoree=d : empêche wineboot d'installer Wine Mono dans un préfixe à
    # moitié construit (ce qui le casse) — on installe le vrai .NET ensuite.
    prefix_step wineboot 600 env WINEDLLOVERRIDES="mscoree=d" wineboot --init || exit 1
    # Désactive la "mise à jour du préfixe" que Wine relance quand l'horodatage
    # de wine.inf ne correspond pas (constaté : décalage d'1 h -> wineboot figé).
    echo disable | as_steam tee "${WINEPREFIX}/.update-timestamp" >/dev/null
    prefix_step dotnet48   2400 winetricks -q --force dotnet48 || exit 1
    prefix_step vcrun2019  900  winetricks -q vcrun2019 || exit 1
    prefix_step corefonts  900  winetricks -q corefonts || exit 1
    prefix_step sound      300  winetricks -q sound=disabled || exit 1
    as_steam rm -rf /home/steam/.cache/winetricks
    as_steam touch "$PREFIX_MARKER"
    log "Préfixe Wine prêt"
else
    log "Préfixe Wine déjà initialisé"
fi

# ── 4. Configuration ──────────────────────────────────────────────────────
# Le fichier maître est dans le volume config. Il n'est généré qu'une fois,
# ensuite c'est lui qu'on modifie (nom, mot de passe haché, admins...).
# Il est recopié dans le dossier d'instance (-path) à chaque démarrage.
if [ ! -f "${CONFIG_DIR}/${CFG_NAME}" ]; then
    log "Génération d'un ${CFG_NAME} par défaut dans le volume config"
    ADMINS_XML=""
    for id in ${ADMIN_STEAMIDS//,/ }; do
        ADMINS_XML="${ADMINS_XML}    <unsignedLong>${id}</unsignedLong>"$'\n'
    done
    as_steam tee "${CONFIG_DIR}/${CFG_NAME}" >/dev/null <<EOF
<?xml version="1.0"?>
<MyConfigDedicated xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <SessionSettings>
    <GameMode>${GAME_MODE:-Survival}</GameMode>
    <OnlineMode>${ONLINE_MODE:-PUBLIC}</OnlineMode>
    <MaxPlayers>${MAX_PLAYERS:-8}</MaxPlayers>
    <AutoSaveInMinutes>5</AutoSaveInMinutes>
    <EnableSaving>true</EnableSaving>
    <MaxBackupSaves>5</MaxBackupSaves>
  </SessionSettings>
  <LoadWorld />
  <PremadeCheckpointPath>Z:\\home\\steam\\se_server\\Content\\CustomWorlds\\${SCENARIO:-Star System}</PremadeCheckpointPath>
  <IP>0.0.0.0</IP>
  <SteamPort>8766</SteamPort>
  <ServerPort>${GAME_PORT}</ServerPort>
  <Administrators>
${ADMINS_XML}  </Administrators>
  <Banned />
  <GroupID>0</GroupID>
  <ServerName>${SERVER_NAME:-Ludix_SpaceEngineers_FR}</ServerName>
  <WorldName>${WORLD_NAME:-Ludix World}</WorldName>
  <PauseGameWhenEmpty>false</PauseGameWhenEmpty>
  <AutoRestartEnabled>false</AutoRestartEnabled>
  <AutoUpdateEnabled>false</AutoUpdateEnabled>
  <IgnoreLastSession>false</IgnoreLastSession>
  <ServerPasswordHash />
  <ServerPasswordSalt />
  <RemoteApiEnabled>false</RemoteApiEnabled>
  <Plugins />
</MyConfigDedicated>
EOF
fi
# Le port est piloté par GAME_PORT (.env) : on l'impose dans le .cfg à chaque
# démarrage pour qu'il corresponde toujours au port publié par Docker.
sed -i "s|<ServerPort>[0-9]*</ServerPort>|<ServerPort>${GAME_PORT}</ServerPort>|" "${CONFIG_DIR}/${CFG_NAME}"
chmod 600 "${CONFIG_DIR}/${CFG_NAME}"
as_steam install -m 600 "${CONFIG_DIR}/${CFG_NAME}" "${SAVE_DIR}/${CFG_NAME}"

# ── 5. Lancement et arrêt propre ──────────────────────────────────────────
# Le .exe Windows ignore SIGTERM. On le traduit en SIGINT, que Wine transmet
# au programme comme un Ctrl+C (CTRL_C_EVENT) pour qu'il sauvegarde et quitte.
GAME_PATTERN='DedicatedServer64.SpaceEngineersDedicated\.exe'
game_running() { pgrep -f "$GAME_PATTERN" >/dev/null 2>&1; }

shutdown_server() {
    log "SIGTERM reçu : arrêt propre du serveur (délai max ${SHUTDOWN_TIMEOUT:-90} s)"
    pkill -INT -f "$GAME_PATTERN"
    for _ in $(seq 1 "${SHUTDOWN_TIMEOUT:-90}"); do
        game_running || break
        sleep 1
    done
    if game_running; then
        log "Le serveur ne s'est pas arrêté à temps, arrêt forcé de Wine"
    fi
    as_steam wineserver -k 2>/dev/null
    log "Serveur arrêté"
    exit 0
}
trap shutdown_server SIGTERM SIGINT

cd "$EXE_DIR" || exit 1
log "Démarrage de Space Engineers Dedicated Server (port ${GAME_PORT}/udp)"
as_steam env WINEDLLOVERRIDES="mscoree=n,b;mshtml=n,b" \
    wine "$EXE" -noconsole -path 'Z:\home\steam\se_saves' &

# 'wine' peut confier le programme à un autre processus : on surveille donc le
# vrai .exe plutôt que le PID du lanceur. "wait" garde le trap réactif.
sleep 20
while game_running; do
    sleep 5 &
    wait $!
done
log "Le processus du serveur s'est terminé"
as_steam wineserver -k 2>/dev/null
exit 1
