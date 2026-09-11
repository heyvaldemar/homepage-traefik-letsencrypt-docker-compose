#!/bin/bash

# Restore Homepage's configuration directory from one of the archives the
# `backups` container has taken.
#
# Homepage has no database. Everything it knows is the YAML in that directory:
# the services you listed, the layout, the widgets, the bookmarks. It is
# hand-written and it is the only thing here that starting the container again
# will not recreate.
#
#     chmod +x homepage-restore-config.sh
#     ./homepage-restore-config.sh
set -euo pipefail
cd "$(dirname "$0")"

COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-homepage-traefik-letsencrypt-docker-compose.yml}"
PROJECT="${COMPOSE_PROJECT_NAME:-homepage}"
BACKUP_PATH="${DATA_BACKUPS_PATH:-/srv/homepage-config/backups}"
RESTORE_PATH="${DATA_PATH:-/config}"

dc() { docker compose -f "$COMPOSE_FILE" -p "$PROJECT" "$@"; }

APP_CONTAINER="$(dc ps -aq homepage | head -n 1)"
BACKUPS_CONTAINER="$(dc ps -aq backups | head -n 1)"
[ -n "$APP_CONTAINER" ] || { echo "the homepage container was not found — is the stack up?" >&2; exit 1; }
[ -n "$BACKUPS_CONTAINER" ] || { echo "the backups container was not found — is the stack up?" >&2; exit 1; }

echo "--> All available config backups:"
docker exec "$BACKUPS_CONTAINER" sh -c "ls -1 $BACKUP_PATH" || true

echo "--> Copy and paste the backup name from the list above and press [ENTER]
--> Example: homepage-config-backup-YYYY-MM-DD_hh-mm.tar.gz"
echo -n "--> "
read -r SELECTED
[ -n "$SELECTED" ] || { echo "nothing selected, nothing restored" >&2; exit 1; }

if ! docker exec "$BACKUPS_CONTAINER" sh -c "tar -tzf '${BACKUP_PATH}/${SELECTED}' > /dev/null"; then
  echo "that file is not a readable tar archive — nothing has been stopped or deleted" >&2
  exit 1
fi
echo "--> $SELECTED was selected and reads as a valid archive"

echo "--> Stopping Homepage..."
docker stop "$APP_CONTAINER" > /dev/null

echo "--> Restoring the config directory..."
# The archive stores paths relative to /, so it extracts there. The directory
# is emptied first: merging would leave a service defined in two files with no
# way to tell which one Homepage will use.
docker exec "$BACKUPS_CONTAINER" sh -c "rm -rf '${RESTORE_PATH:?}'/* && tar -zxpf '${BACKUP_PATH}/${SELECTED}' -C /"
echo "--> Config recovery completed."

echo "--> Starting Homepage..."
docker start "$APP_CONTAINER" > /dev/null
echo "--> Homepage re-reads the directory on start; the dashboard is back as the"
echo "--> archive had it."
