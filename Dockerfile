# Mautic runtime image for the vps-mgmt platform.
#
# Built on the official Mautic Apache image, pinned by digest. The only
# behavioural change is that Apache listens on the unprivileged port 8080 so
# the web service can run as www-data (uid 33) under rootless Docker. The
# runtime contract for the platform is published as OCI labels below and
# mirrored in deploy/manifest.yaml.

ARG MAUTIC_BASE=mautic/mautic:6.0.5-apache@sha256:585cdc1b1891b2df083c74485fc2815caff0f62ee913c7f4f79ae94717ac213b
FROM ${MAUTIC_BASE}

# Serve on an unprivileged port. The base image keeps the root master process
# so that cron/worker roles still work; the web service is pinned to uid 33 by
# the deployment stack (applications/mautic/compose.yaml in vps-mgmt).
RUN set -eux; \
    sed -i 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf; \
    sed -i 's/<VirtualHost \*:80>/<VirtualHost *:8080>/' /etc/apache2/sites-enabled/000-default.conf; \
    grep -q 'Listen 8080' /etc/apache2/ports.conf

# Runtime directories the non-root web entrypoint can create and write.
ENV APACHE_RUN_DIR=/tmp/apache2 \
    APACHE_LOCK_DIR=/tmp/apache2 \
    APACHE_LOG_DIR=/tmp/apache2 \
    APACHE_PID_FILE=/tmp/apache2/apache2.pid

COPY deploy/web-entrypoint.sh /usr/local/bin/mautic-web-entrypoint
COPY deploy/init.sh /usr/local/bin/mautic-init
COPY deploy/set-local-params.php /usr/local/bin/mautic-set-local-params
RUN chmod 0755 /usr/local/bin/mautic-web-entrypoint /usr/local/bin/mautic-init /usr/local/bin/mautic-set-local-params

# Runtime contract (see docs/application-contract.md in dasmedium/vps-mgmt).
LABEL dev.vpsmgmt.contract.v1="1" \
      dev.vpsmgmt.contract.v1.env='[{"name":"MAUTIC_DB_HOST","type":"string","optional":false,"secret":false,"description":"MySQL host"},{"name":"MAUTIC_DB_PORT","type":"int","optional":false,"secret":false,"description":"MySQL port"},{"name":"MAUTIC_DB_DATABASE","type":"string","optional":false,"secret":false,"description":"Mautic database name"},{"name":"MAUTIC_DB_USER","type":"string","optional":false,"secret":false,"description":"Mautic database user"},{"name":"MAUTIC_DB_PASSWORD","type":"string","optional":false,"secret":true,"description":"Mautic database password"},{"name":"MAUTIC_URL","type":"string","optional":false,"secret":false,"description":"Canonical https site URL"},{"name":"MAUTIC_MESSENGER_DSN_EMAIL","type":"string","optional":false,"secret":false,"description":"Messenger transport for email"},{"name":"MAUTIC_MESSENGER_DSN_HIT","type":"string","optional":false,"secret":false,"description":"Messenger transport for hits"}]' \
      dev.vpsmgmt.contract.v1.ports='[{"container":8080,"protocol":"tcp"}]' \
      dev.vpsmgmt.contract.v1.healthcheck='{"test":["CMD-SHELL","curl -fsS http://127.0.0.1:8080/ || exit 1"],"interval":"30s","timeout":"10s","retries":"3","start_period":"60s"}' \
      dev.vpsmgmt.contract.v1.volumes='[{"name":"config","mount":"/var/www/html/config"},{"name":"media_files","mount":"/var/www/html/docroot/media/files"},{"name":"media_images","mount":"/var/www/html/docroot/media/images"}]' \
      dev.vpsmgmt.contract.v1.resources='{"cpus":"1.0","memory":"768M"}' \
      dev.vpsmgmt.contract.v1.run-user="33"

# The image default remains the official entrypoint so the cron and worker
# roles keep working; the web service overrides it with the non-root entrypoint.
CMD ["apache2-foreground"]
