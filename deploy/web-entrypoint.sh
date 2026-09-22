#!/bin/bash
# Non-root entrypoint for the Mautic web role.
#
# Runs as www-data (uid 33). The official image entrypoint assumes root (it
# chowns volumes and uses `su`); everything the web role actually needs is
# reproduced here without privileged operations:
#   1. create the Apache runtime directories the current user can write,
#   2. fail fast when required database settings are missing,
#   3. wait for MySQL,
#   4. ensure a local.php exists,
#   5. migrate once Mautic has been installed,
#   6. trust the container's own networks as reverse proxies (Traefik),
#   7. exec Apache.
set -euo pipefail

export APACHE_RUN_DIR="${APACHE_RUN_DIR:-/tmp/apache2}"
export APACHE_LOCK_DIR="${APACHE_LOCK_DIR:-/tmp/apache2}"
export APACHE_LOG_DIR="${APACHE_LOG_DIR:-/tmp/apache2}"
export APACHE_PID_FILE="${APACHE_PID_FILE:-/tmp/apache2/apache2.pid}"
mkdir -p "$APACHE_RUN_DIR"

CONFIG_DIR="${MAUTIC_VOLUME_CONFIG:-/var/www/html/config}"
CONSOLE="${MAUTIC_CONSOLE:-/var/www/html/bin/console}"

for var in MAUTIC_DB_HOST MAUTIC_DB_PORT MAUTIC_DB_DATABASE MAUTIC_DB_USER MAUTIC_DB_PASSWORD; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: required environment variable ${var} is not set" >&2
        exit 1
    fi
done

# Wait for the database to accept connections. The password is passed to the
# client through MYSQL_PWD rather than a --password argument, so it does not
# appear in the process table. (The base image's check_database_connection.sh
# uses `--password=`, which would expose it.)
db_ready() {
    MYSQL_PWD="${MAUTIC_DB_PASSWORD}" mysqladmin \
        --host="${MAUTIC_DB_HOST}" \
        --port="${MAUTIC_DB_PORT}" \
        --user="${MAUTIC_DB_USER}" \
        ping >/dev/null 2>&1
}

attempt=0
max_attempts=31
until db_ready; do
    attempt=$((attempt + 1))
    if [ "${attempt}" -gt "${max_attempts}" ]; then
        echo "ERROR: MySQL at ${MAUTIC_DB_HOST}:${MAUTIC_DB_PORT} is not responding" >&2
        exit 1
    fi
    echo "MySQL is not ready yet, waiting... (${attempt}/${max_attempts})"
    sleep 1
done
echo "MySQL is alive and well."

# The base image ships a local.php template that pre-fills the DB credentials.
if [ ! -f "${CONFIG_DIR}/local.php" ]; then
    cp -p /templates/local.php "${CONFIG_DIR}/local.php"
fi

# Run migrations only after the initial installation has created the schema.
if php -r "include('${CONFIG_DIR}/local.php'); exit(!empty(\$parameters['site_url']) ? 0 : 1);" 2>/dev/null; then
    php "$CONSOLE" doctrine:migrations:migrate -n
else
    echo "Mautic is not installed yet; skipping migrations."
fi

# Trust every on-link container network as a proxy so X-Forwarded-* headers
# from Traefik are honoured. The CIDRs are derived from the container's own
# routing table, so no subnet is hardcoded.
if ! grep -q "trusted_proxies" "${CONFIG_DIR}/local.php"; then
    SUBNETS="$(python3 - <<'PY'
import ipaddress
import socket
import struct


def le_ip(hex_value):
    return socket.inet_ntoa(struct.pack("<L", int(hex_value, 16)))


networks = set()
try:
    with open("/proc/net/route", encoding="utf-8") as routes:
        next(routes, None)
        for line in routes:
            fields = line.split()
            if len(fields) < 8 or fields[1] == "00000000":
                continue
            try:
                networks.add(
                    ipaddress.ip_network(
                        "%s/%s" % (le_ip(fields[1]), le_ip(fields[7])), strict=False
                    )
                )
            except ValueError:
                continue
except OSError:
    pass

print(",".join("'%s'" % net for net in sorted(str(n) for n in networks)))
PY
)"
    if [ -z "${SUBNETS}" ]; then
        echo "WARNING: could not derive proxy subnets; forwarded headers may be ignored" >&2
    else
        {
            echo ""
            echo "\$parameters['trusted_proxies'] = [${SUBNETS}];"
            echo "\$parameters['trusted_headers'] = ["
            echo "    'forwarded' => 'FORWARDED',"
            echo "    'x-forwarded-for' => 'X_FORWARDED_FOR',"
            echo "    'x-forwarded-host' => 'X_FORWARDED_HOST',"
            echo "    'x-forwarded-proto' => 'X_FORWARDED_PROTO',"
            echo "    'x-forwarded-port' => 'X_FORWARDED_PORT'"
            echo "];"
        } >> "${CONFIG_DIR}/local.php"
    fi
fi

exec "$@"
