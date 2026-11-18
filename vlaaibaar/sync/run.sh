#!/usr/bin/env bash
#ddev-generated
# Installed by vlaaibaar/ddev-addon. Do not edit: changes are overwritten on update.
#
# Usage (called by .ddev/providers/<env>.yaml, inside the web container):
#   run.sh <environment> <auth|db-pull|files-pull|db-push|files-push>

set -eu -o pipefail

ENVIRONMENT="${1:?Missing environment}"
ACTION="${2:?Missing action}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${DIR}/${ENVIRONMENT}.env"
DOWNLOADS="/var/www/html/.ddev/.downloads"

fail() { echo "$*" >&2; exit 1; }

[ -f "${ENV_FILE}" ] || fail "Missing .ddev/vlaaibaar/sync/${ENVIRONMENT}.env. Copy example.env to ${ENVIRONMENT}.env and fill it in."
# shellcheck source=/dev/null
source "${ENV_FILE}"

: "${SSH_HOST:?SSH_HOST is not set in ${ENVIRONMENT}.env}"
: "${REMOTE_PATH:?REMOTE_PATH is not set in ${ENVIRONMENT}.env}"
: "${REMOTE_UPLOADS:?REMOTE_UPLOADS is not set in ${ENVIRONMENT}.env}"
ALLOW_PUSH="${ALLOW_PUSH:-false}"

case "${SSH_HOST}" in
  *CHANGE_ME*) fail "Fill in SSH_HOST in .ddev/vlaaibaar/sync/${ENVIRONMENT}.env first." ;;
esac

require_push() {
  [ "${ALLOW_PUSH}" = "true" ] || fail "Pushing to ${ENVIRONMENT} is disabled (ALLOW_PUSH=false in ${ENVIRONMENT}.env)."
}

case "${ACTION}" in
  auth)
    ssh-add -l >/dev/null || fail "Please run 'ddev auth ssh' before running this command."
    ssh -o BatchMode=yes "${SSH_HOST}" true || fail "Unable to connect to ${SSH_HOST}."
    ;;

  db-pull)
    mkdir -p "${DOWNLOADS}"
    # Craft's own backup command reads the DB credentials from the server's .env
    ssh "${SSH_HOST}" 'set -eu; tmp=$(mktemp /tmp/ddev-pull-XXXXXX.sql); trap "rm -f $tmp" EXIT; cd '"${REMOTE_PATH}"'; php craft db/backup "$tmp" --overwrite --interactive=0 >&2; gzip -c "$tmp"' \
      > "${DOWNLOADS}/db.sql.gz"
    ;;

  files-pull)
    mkdir -p "${DOWNLOADS}/files"
    rsync -az --delete "${SSH_HOST}:${REMOTE_UPLOADS}/" "${DOWNLOADS}/files/"
    ;;

  db-push)
    require_push
    echo "Pushing local database to ${SSH_HOST}:${REMOTE_PATH}"
    # Restore with Craft's own command (uses the server's .env), then apply pending migrations/project config
    mysqldump db | gzip | ssh "${SSH_HOST}" 'set -eu; tmp=$(mktemp /tmp/ddev-push-XXXXXX.sql); trap "rm -f $tmp" EXIT; gunzip -c > "$tmp"; cd '"${REMOTE_PATH}"'; php craft db/restore "$tmp" --interactive=0; php craft up --interactive=0'
    ;;

  files-push)
    require_push
    echo "Pushing local uploads to ${SSH_HOST}:${REMOTE_UPLOADS}"
    # No --delete on push, to be safe
    rsync -az "${DDEV_FILES_DIR}/" "${SSH_HOST}:${REMOTE_UPLOADS}/"
    ;;

  *)
    fail "Unknown action: ${ACTION}"
    ;;
esac
