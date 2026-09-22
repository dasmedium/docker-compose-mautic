# AGENTS.md

Image-build repository for Mautic on the `dasmedium/vps-mgmt` platform. This
repo builds and publishes an immutable image to GHCR; it never deploys to
production and never holds production secrets or SSH access. Verify changes with
`shellcheck deploy/*.sh`, `docker build`, and the contract check in
`.github/workflows/ci.yml` (`docker image inspect ... --format '{{json .Config.Labels}}'`).

## Development workflow (PR convention)

Never commit or push directly to `master`. All changes go through a feature
branch + PR:

1. `git checkout -b <short-descriptive-name>` (e.g. `feat/pin-mautic-6.0.6`).
2. Make the change, then verify (`shellcheck deploy/*.sh`, `docker build .`,
   contract/manifest agreement).
3. Commit with a short imperative message, push the branch, and open a PR
   against `master` (`gh pr create`).
4. Do not merge locally or push to `master`; let the PR be the merge point.

## What this repo owns vs. vps-mgmt

- **This repo:** Dockerfile, image tags/digests, the Mautic runtime image, and
  the runtime contract (`deploy/manifest.yaml` + OCI labels).
- **`dasmedium/vps-mgmt`:** desired state (`applications/mautic/`), which image
  digest is live, hostname/TLS routing, networks, limits, secrets, and backup
  policy. Production Compose lives there, not here.

## The runtime contract

The image must carry these OCI labels and `deploy/manifest.yaml` must match them
(CI enforces both):

- `dev.vpsmgmt.contract.v1` = `1`
- `dev.vpsmgmt.contract.v1.env` (JSON array), `.ports`, `.healthcheck`,
  `.volumes`, `.resources`, `.run-user`

Never add a required env var or secret to the labels without adding it to
`deploy/manifest.yaml` (and vice versa). `MAUTIC_DB_PASSWORD` must stay a
required secret. `run-user` must stay `33` and the container port must stay
`8080`.

The contract is consumed by `vps-mgmt`'s reconciler
(`platform/reconciler/contract.py`). Changing it can require a coordinated
change there; treat it as an interface, not an implementation detail.

## Non-root runtime

The web role runs as `www-data` (uid 33). Apache must listen on the
unprivileged port `8080`; do not reintroduce `Listen 80` or a root web process.
`deploy/web-entrypoint.sh` must not perform privileged operations (no `chown`,
no `su`). The base image's cron/worker entrypoints still expect root and are
unchanged.

## Secrets

No production secret enters this repository, its CI, or the image. Production
secrets are provisioned on the VPS by `vps-mgmt`
(`provisioning/playbooks/provision-app.yml`) under
`/var/lib/vps-mgmt/secrets/mautic/`. `deploy/secrets.local/` is git-ignored and
is for local development only.

Never pass a secret on a command line. The platform security contract forbids
secrets in process arguments. Concretely:

- `deploy/init.sh` writes the admin email/password into Mautic's `local.php`
  (via `deploy/set-local-params.php`) and runs `mautic:install` with no
  credential flags; `mautic:install` reads them from `local.php`.
- `deploy/web-entrypoint.sh` probes MySQL with `MYSQL_PWD`, not
  `mysqladmin --password=`. Do not reintroduce the base image's
  `check_database_connection.sh`, which uses `--password=`.

## Publishing and releases

`.github/workflows/publish-image.yml` publishes on push to `master` and calls
the reusable release-PR workflow in `vps-mgmt`. The image pin in
`vps-mgmt/applications/mautic/manifest.yaml` changes only through a release PR
there; this repo proposes, a human merges, the reconciler deploys.

- Base image pins live in the `Dockerfile` `ARG MAUTIC_BASE` (digest-pinned).
  Bump deliberately and note the change.
- `VPS_MGMT_RELEASE_TOKEN` is a repo secret scoped to `dasmedium/vps-mgmt`
  only (contents:write, pull_requests:write); it cannot deploy.
