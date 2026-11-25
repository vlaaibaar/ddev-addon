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

# Personal settings (gitignored), e.g. SSH_USER. Loaded after the shared file so they can override it.
LOCAL_ENV_FILE="${DIR}/${ENVIRONMENT}.local.env"
if [ -f "${LOCAL_ENV_FILE}" ]; then
  # shellcheck source=/dev/null
  source "${LOCAL_ENV_FILE}"
fi

: "${SSH_HOST:?SSH_HOST is not set in ${ENVIRONMENT}.env}"
: "${REMOTE_PATH:?REMOTE_PATH is not set in ${ENVIRONMENT}.env}"
: "${REMOTE_UPLOADS:?REMOTE_UPLOADS is not set in ${ENVIRONMENT}.env}"
ALLOW_PUSH="${ALLOW_PUSH:-false}"

case "${SSH_HOST}" in
  *CHANGE_ME*) fail "Fill in SSH_HOST in .ddev/vlaaibaar/sync/${ENVIRONMENT}.env first." ;;
esac

# SSH_HOST may still contain "user@host" (older setups); otherwise the user comes from SSH_USER.
case "${SSH_HOST}" in
  *@*) SSH_TARGET="${SSH_HOST}" ;;
  *)
    case "${SSH_USER:-}" in
      ""|*CHANGE_ME*) fail "Set SSH_USER in .ddev/vlaaibaar/sync/${ENVIRONMENT}.env (a shared user, e.g. the Cloudways master user) or in ${ENVIRONMENT}.local.env (your own user, gitignored)." ;;
    esac
    SSH_TARGET="${SSH_USER}@${SSH_HOST}"
    ;;
esac

require_push() {
  [ "${ALLOW_PUSH}" = "true" ] || fail "Pushing to ${ENVIRONMENT} is disabled (ALLOW_PUSH=false in ${ENVIRONMENT}.env)."
}

# PHP binary on the server. Defaults to the version pinned for this project in DDEV (php8.3 etc.),
# because the SSH user's default `php` can be another version (e.g. the Cloudways master user).
REMOTE_PHP="${REMOTE_PHP:-php${DDEV_PHP_VERSION:-}}"

# Start of every remote command that runs Craft:
# - umask 002 keeps files it creates group-writable, so the site's PHP user (same group) can write them
# - falls back to plain `php` when the versioned binary doesn't exist on the server
remote_setup() {
  printf 'set -eu; umask 002; PHP=%q; if ! command -v "$PHP" >/dev/null 2>&1; then echo "$PHP not found on the server, using php" >&2; PHP=php; fi; cd %q; ' \
    "${REMOTE_PHP}" "${REMOTE_PATH}"
}

case "${ACTION}" in
  auth)
    ssh-add -l >/dev/null || fail "Please run 'ddev auth ssh' before running this command."
    ssh -o BatchMode=yes "${SSH_TARGET}" true || fail "Unable to connect to ${SSH_TARGET}."
    ;;

  db-pull)
    mkdir -p "${DOWNLOADS}"
    # Craft's own backup command reads the DB credentials from the server's .env
    ssh "${SSH_TARGET}" "$(remote_setup)"'tmp=$(mktemp /tmp/ddev-pull-XXXXXX.sql); trap "rm -f $tmp" EXIT; "$PHP" craft db/backup "$tmp" --overwrite --interactive=0 >&2; gzip -c "$tmp"' \
      > "${DOWNLOADS}/db.sql.gz"
    ;;

  files-pull)
    mkdir -p "${DOWNLOADS}/files"
    rsync -az --delete "${SSH_TARGET}:${REMOTE_UPLOADS}/" "${DOWNLOADS}/files/"
    ;;

  db-push)
    require_push
    echo "Pushing local database to ${SSH_TARGET}:${REMOTE_PATH}"
    # Restore with Craft's own command (uses the server's .env), then apply pending migrations/project config
    mysqldump db | gzip | ssh "${SSH_TARGET}" "$(remote_setup)"'tmp=$(mktemp /tmp/ddev-push-XXXXXX.sql); trap "rm -f $tmp" EXIT; gunzip -c > "$tmp"; "$PHP" craft db/restore "$tmp" --interactive=0; "$PHP" craft up --interactive=0'
    ;;

  files-push)
    require_push
    echo "Pushing local uploads to ${SSH_TARGET}:${REMOTE_UPLOADS}"
    # No --delete on push, to be safe.
    # Fixed modes (dirs 775, files 664) instead of the local ones, which can be 700/600 after a
    # pull: files must stay readable for the web server and writable for the site's PHP user
    # (same group). No group or dir-time changes, so it also works on files owned by another user.
    rsync -az --no-group --omit-dir-times --chmod=D775,F664 "${DDEV_FILES_DIR}/" "${SSH_TARGET}:${REMOTE_UPLOADS}/"
    ;;

  *)
    fail "Unknown action: ${ACTION}"
    ;;
esac
