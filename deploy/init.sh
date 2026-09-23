#!/bin/bash
# One-shot, idempotent Mautic installer.
#
# Runs once per deployment as a Compose service that `web`, `cron`, and
# `worker` wait for (`service_completed_successfully`). It exits 0 when
# Mautic is already installed, so every later reconcile is a no-op.
#
# It replaces the old setup-dc.sh host script: no SSH, no substituted secrets
# on disk, all inputs arrive as environment or mounted secret files.
#
# Secret handling: admin credentials are read from secret files and written
# into Mautic's local.php (mode-0600, on the persistent config volume), then
# `mautic:install` reads them from local.php. The values are handed to the
# helper as file paths, never as arguments, so no secret appears in the process
# table or command logs.
set -euo pipefail

CONFIG_DIR="${MAUTIC_VOLUME_CONFIG:-/var/www/html/config}"
CONSOLE="${MAUTIC_CONSOLE:-/var/www/html/bin/console}"
MAUTIC_URL="${MAUTIC_URL:?MAUTIC_URL is required}"
ADMIN_EMAIL_FILE="${MAUTIC_ADMIN_EMAIL_FILE:-/run/secrets/mautic_admin_email}"
ADMIN_PASSWORD_FILE="${MAUTIC_ADMIN_PASSWORD_FILE:-/run/secrets/mautic_admin_password}"

# The base image only creates config/local.php in the entrypoint; migrations
# and install need it to exist.
if [ ! -f "${CONFIG_DIR}/local.php" ]; then
    cp -p /templates/local.php "${CONFIG_DIR}/local.php"
fi

if php -r "include('${CONFIG_DIR}/local.php'); exit(!empty(\$parameters['site_url']) ? 0 : 1);" 2>/dev/null; then
    echo "Mautic is already installed; nothing to do."
    exit 0
fi

if [ ! -s "${ADMIN_EMAIL_FILE}" ]; then
    echo "ERROR: admin email secret file is missing or empty: ${ADMIN_EMAIL_FILE}" >&2
    exit 1
fi
if [ ! -s "${ADMIN_PASSWORD_FILE}" ]; then
    echo "ERROR: admin password secret file is missing or empty: ${ADMIN_PASSWORD_FILE}" >&2
    exit 1
fi

# Pass file paths only; the helper reads the values itself.
php /usr/local/bin/mautic-set-local-params \
    "${CONFIG_DIR}/local.php" \
    "admin_email_FILE=${ADMIN_EMAIL_FILE}" \
    "admin_password_FILE=${ADMIN_PASSWORD_FILE}"
php -l "${CONFIG_DIR}/local.php" >/dev/null

echo "Installing Mautic at ${MAUTIC_URL}"
# No credential flags: install reads admin_email/admin_password from local.php.
php "$CONSOLE" mautic:install --force "${MAUTIC_URL}"

php "$CONSOLE" cache:clear
echo "Mautic installation complete."
