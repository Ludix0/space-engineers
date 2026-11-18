# Space Engineers — Dedicated Server (Docker + Wine)

🇬🇧 [English](#english) | 🇫🇷 [Français](#français)

---

## English

Docker container to host a **Space Engineers** dedicated server (SteamCMD App ID `298740`, anonymous download). There is no native Linux build, so the Windows server runs under **Wine** (WineHQ stable `10.0`, with `dotnet48`, `vcrun2019` and `corefonts` installed in the Wine prefix). The server is updated automatically through SteamCMD each time the container starts.

- Docker Hub image: [`ludix0/space-engineers`](https://hub.docker.com/r/ludix0/space-engineers)
- Port used: `7777/udp` (game) — nothing else is needed

### Requirements

- Docker and Docker Compose v2
- About 15 GB of free disk space (server ~8.5 GB + Wine prefix)
- A CPU exposing AVX2 to the VM (on Proxmox: CPU type `host`)
- UDP port `7777` forwarded on your router/firewall

> ⏳ **The first start is long (30 to 60 min)**: server download, then .NET 4.8 installation in the Wine prefix. Later starts skip both. The container stays `health: starting` until the game UDP port is open (world loaded).

### Method 1 — Quick install from Docker Hub (recommended)

Create a `docker-compose.yml`:

```yaml
services:
  space-engineers:
    image: ludix0/space-engineers:latest
    container_name: space-engineers
    restart: unless-stopped
    stop_grace_period: 120s
    volumes:
      - ./filesServer:/home/steam/se_server
      - ./saves:/home/steam/se_saves
      - ./config:/home/steam/se_config
      - ./wineprefix:/home/steam/wineprefix
      - ./steamcmd:/home/steam/steamcmd
    environment:
      - TZ=Europe/Paris
      - PUID=1000
      - PGID=1000
      - GAME_PORT=7777
      - UPDATE_ON_START=true
      - STEAM_DLL_FIX=true
      - SHUTDOWN_TIMEOUT=90
      - SERVER_NAME=My Space Engineers Server
      - WORLD_NAME=My World
      - GAME_MODE=Survival
      - ONLINE_MODE=PUBLIC
      - MAX_PLAYERS=8
      - SCENARIO=Star System
      - ADMIN_STEAMIDS=
    ports:
      - "7777:7777/udp"
```

Replace `PUID`/`PGID` (output of `id -u` / `id -g`), then run:

```bash
mkdir -p filesServer saves config wineprefix steamcmd
docker compose up -d
docker compose logs -f
```

### Method 2 — Build from source (GitHub)

```bash
git clone https://github.com/Ludix0/space-engineers.git
cd space-engineers
cp .env.example .env    # then edit TZ, PUID, PGID, jeux1 (game port)
mkdir -p ~/volumes/space-engineers/{filesServer,saves,config,wineprefix} ~/volumes/steamcmd
docker compose build
docker compose up -d
```

### Environment variables

| Variable | Description |
|---|---|
| `TZ` | Time zone (e.g. `Europe/Paris`) |
| `PUID` / `PGID` | UID/GID owning the volume files |
| `GAME_PORT` | Game UDP port (same on host and container; rewritten in the `.cfg` at each start) |
| `UPDATE_ON_START` | `true` = update via SteamCMD (`validate`) at each start |
| `STEAM_DLL_FIX` | `true` = replace the server's Steam DLLs with the Steam SDK Redist ones (needed for Workshop mods) |
| `SHUTDOWN_TIMEOUT` | Seconds given to the server to save on shutdown (keep below `stop_grace_period`) |
| `SERVER_NAME` | Server name ¹ |
| `WORLD_NAME` | World name ¹ |
| `GAME_MODE` | `Survival` or `Creative` ¹ |
| `ONLINE_MODE` | `PUBLIC`, `PRIVATE`, `FRIENDS` or `OFFLINE` ¹ |
| `MAX_PLAYERS` | Maximum number of players ¹ |
| `SCENARIO` | Starting scenario (folder of `Content/CustomWorlds`) ¹ |
| `ADMIN_STEAMIDS` | Administrators' SteamID64, comma-separated ¹ |

¹ Used **only** to generate the default `config/SpaceEngineers-Dedicated.cfg` on first start. Afterwards, edit that file directly and run `docker compose restart`.

### Volumes

| Container path | Content | Back up? |
|---|---|---|
| `/home/steam/se_server` | Server binaries (SteamCMD) | No (re-downloadable) |
| `/home/steam/se_saves` | World (`Saves/`), logs, automatic backups | **Yes** |
| `/home/steam/se_config` | `SpaceEngineers-Dedicated.cfg` (master file) | **Yes** |
| `/home/steam/wineprefix` | Wine prefix (.NET 4.8…) | No (recreated if deleted) |
| `/home/steam/steamcmd` | SteamCMD (can be shared between servers) | No |

### Ports

| Port | Protocol | Usage |
|---|---|---|
| `7777` | UDP | Game (the only port to forward) |

The Remote API (TCP 8080) is disabled and not published: it relies on `http.sys`, which Wine does not really implement.

### Server password and admins

Space Engineers does not store the password in clear text but as a hash (`ServerPasswordHash` + `ServerPasswordSalt` in the `.cfg`), so no environment variable is used. The most reliable way to generate it is the official *Space Engineers Dedicated Server* tool on Windows, then copy both lines into the `.cfg`. Admins are set by SteamID64 in `<Administrators>`.

### Updating

```bash
docker compose restart                                 # game update
docker compose pull && docker compose up -d            # image update
```

Steam clients update automatically and an outdated server refuses players: restart the container after each Keen patch.

### Troubleshooting

| Symptom | Fix |
|---|---|
| `App '298740' state is 0x4A6 after update job` | Check volume ownership (`PUID`/`PGID`) and disk space; otherwise stop, delete `filesServer/steamapps` and start again |
| `illegal instruction`, immediate .NET/Wine crash | VM CPU type must expose AVX2 (Proxmox: `host` instead of `kvm64`) |
| Broken Wine prefix | `docker compose down`, empty `wineprefix/` (including `.step_*` and `.se_prefix_ready`), `docker compose up -d` |
| Workshop mods not downloading | Keep `STEAM_DLL_FIX=true` |
| Game logs | `saves/` (`SpaceEngineersDedicated_*.log` files) |

---

## Français

Conteneur Docker pour héberger un serveur dédié **Space Engineers** (SteamCMD App ID `298740`, téléchargement anonyme). Il n'existe pas de version Linux native : le serveur Windows tourne donc sous **Wine** (WineHQ stable `10.0`, avec `dotnet48`, `vcrun2019` et `corefonts` installés dans le préfixe Wine). Le serveur est mis à jour automatiquement via SteamCMD à chaque démarrage du conteneur.

- Image Docker Hub : [`ludix0/space-engineers`](https://hub.docker.com/r/ludix0/space-engineers)
- Port utilisé : `7777/udp` (jeu) — aucun autre n'est nécessaire

### Prérequis

- Docker et Docker Compose v2
- Environ 15 Go d'espace disque libre (serveur ~8,5 Go + préfixe Wine)
- Un processeur exposant AVX2 à la VM (sous Proxmox : type de CPU `host`)
- Port UDP `7777` redirigé sur votre routeur/pare-feu

> ⏳ **Le premier démarrage est long (30 à 60 min)** : téléchargement du serveur, puis installation de .NET 4.8 dans le préfixe Wine. Les démarrages suivants ne refont ni l'un ni l'autre. Le conteneur reste en `health: starting` tant que le port UDP du jeu n'est pas ouvert (monde chargé).

### Méthode 1 — Installation rapide depuis Docker Hub (recommandée)

Créez un fichier `docker-compose.yml` :

```yaml
services:
  space-engineers:
    image: ludix0/space-engineers:latest
    container_name: space-engineers
    restart: unless-stopped
    stop_grace_period: 120s
    volumes:
      - ./filesServer:/home/steam/se_server
      - ./saves:/home/steam/se_saves
      - ./config:/home/steam/se_config
      - ./wineprefix:/home/steam/wineprefix
      - ./steamcmd:/home/steam/steamcmd
    environment:
      - TZ=Europe/Paris
      - PUID=1000
      - PGID=1000
      - GAME_PORT=7777
      - UPDATE_ON_START=true
      - STEAM_DLL_FIX=true
      - SHUTDOWN_TIMEOUT=90
      - SERVER_NAME=Mon serveur Space Engineers
      - WORLD_NAME=Mon monde
      - GAME_MODE=Survival
      - ONLINE_MODE=PUBLIC
      - MAX_PLAYERS=8
      - SCENARIO=Star System
      - ADMIN_STEAMIDS=
    ports:
      - "7777:7777/udp"
```

Adaptez `PUID`/`PGID` (résultat de `id -u` / `id -g`), puis lancez :

```bash
mkdir -p filesServer saves config wineprefix steamcmd
docker compose up -d
docker compose logs -f
```

### Méthode 2 — Construire depuis les sources (GitHub)

```bash
git clone https://github.com/Ludix0/space-engineers.git
cd space-engineers
cp .env.example .env    # puis adapter TZ, PUID, PGID, jeux1 (port de jeu)
mkdir -p ~/volumes/space-engineers/{filesServer,saves,config,wineprefix} ~/volumes/steamcmd
docker compose build
docker compose up -d
```

### Variables d'environnement

| Variable | Description |
|---|---|
| `TZ` | Fuseau horaire (ex. `Europe/Paris`) |
| `PUID` / `PGID` | UID/GID propriétaires des fichiers des volumes |
| `GAME_PORT` | Port UDP du jeu (identique hôte/conteneur ; réécrit dans le `.cfg` à chaque démarrage) |
| `UPDATE_ON_START` | `true` = mise à jour via SteamCMD (`validate`) à chaque démarrage |
| `STEAM_DLL_FIX` | `true` = remplace les DLL Steam du serveur par celles du Steam SDK Redist (nécessaire pour les mods Workshop) |
| `SHUTDOWN_TIMEOUT` | Secondes laissées au serveur pour sauvegarder à l'arrêt (rester sous `stop_grace_period`) |
| `SERVER_NAME` | Nom du serveur ¹ |
| `WORLD_NAME` | Nom du monde ¹ |
| `GAME_MODE` | `Survival` ou `Creative` ¹ |
| `ONLINE_MODE` | `PUBLIC`, `PRIVATE`, `FRIENDS` ou `OFFLINE` ¹ |
| `MAX_PLAYERS` | Nombre maximum de joueurs ¹ |
| `SCENARIO` | Scénario de départ (dossier de `Content/CustomWorlds`) ¹ |
| `ADMIN_STEAMIDS` | SteamID64 des administrateurs, séparés par des virgules ¹ |

¹ Utilisées **uniquement** pour générer le fichier `config/SpaceEngineers-Dedicated.cfg` par défaut au premier démarrage. Ensuite, modifiez directement ce fichier puis `docker compose restart`.

### Volumes

| Chemin dans le conteneur | Contenu | À sauvegarder ? |
|---|---|---|
| `/home/steam/se_server` | Binaires du serveur (SteamCMD) | Non (re-téléchargeable) |
| `/home/steam/se_saves` | Monde (`Saves/`), logs, sauvegardes automatiques | **Oui** |
| `/home/steam/se_config` | `SpaceEngineers-Dedicated.cfg` (fichier maître) | **Oui** |
| `/home/steam/wineprefix` | Préfixe Wine (.NET 4.8…) | Non (recréé si supprimé) |
| `/home/steam/steamcmd` | SteamCMD (partageable entre serveurs) | Non |

### Ports

| Port | Protocole | Usage |
|---|---|---|
| `7777` | UDP | Jeu (seul port à rediriger) |

L'API distante (TCP 8080) est désactivée et non publiée : elle repose sur `http.sys`, que Wine n'implémente pas réellement.

### Mot de passe du serveur et admins

Space Engineers ne stocke pas le mot de passe en clair mais un hash (`ServerPasswordHash` + `ServerPasswordSalt` dans le `.cfg`) : aucune variable d'environnement n'est donc utilisée. Le plus fiable pour le générer est l'outil officiel *Space Engineers Dedicated Server* sous Windows, puis recopier les deux lignes dans le `.cfg`. Les admins se déclarent par SteamID64 dans `<Administrators>`.

### Mise à jour

```bash
docker compose restart                                 # mise à jour du jeu
docker compose pull && docker compose up -d            # mise à jour de l'image
```

Les clients Steam se mettent à jour automatiquement et un serveur en retard refuse les joueurs : redémarrez le conteneur après chaque patch de Keen.

### Dépannage

| Symptôme | Solution |
|---|---|
| `App '298740' state is 0x4A6 after update job` | Vérifier les droits des volumes (`PUID`/`PGID`) et l'espace disque ; sinon arrêter, supprimer `filesServer/steamapps` et relancer |
| `illegal instruction`, crash .NET/Wine immédiat | Le type de CPU de la VM doit exposer AVX2 (Proxmox : `host` au lieu de `kvm64`) |
| Préfixe Wine cassé | `docker compose down`, vider `wineprefix/` (y compris `.step_*` et `.se_prefix_ready`), `docker compose up -d` |
| Mods Workshop qui ne se téléchargent pas | Garder `STEAM_DLL_FIX=true` |
| Logs du jeu | `saves/` (fichiers `SpaceEngineersDedicated_*.log`) |
