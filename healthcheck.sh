#!/bin/bash
# Healthcheck : le serveur est "sain" quand il écoute sur son port de jeu UDP
# (GAME_PORT, en hexadécimal dans /proc/net/udp). L'image n'a ni ss ni netstat.
# Ce port n'est ouvert qu'une fois le monde chargé : pendant le téléchargement
# SteamCMD et l'installation de .NET, le conteneur reste en "starting".
HEX=$(printf '%04X' "${GAME_PORT:-7777}")
grep -qE "^ *[0-9]+: [0-9A-F]+:${HEX} " /proc/net/udp /proc/net/udp6 2>/dev/null
