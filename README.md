# Mautic image for the vps-mgmt platform

This repository builds and publishes the Mautic runtime image used by
[`dasmedium/vps-mgmt`](https://github.com/dasmedium/vps-mgmt). It does **not**
deploy to production: GitHub builds and publishes an immutable image to GHCR,
and the VPS pulls it through the platform reconciler.

## Trust model

```
this repo  ->  test / build / scan / publish  ->  GHCR  ->  vps-mgmt reconciler
```

- This repository owns the image, the Dockerfile, and the runtime contract.
- `dasmedium/vps-mgmt` owns desired state: which digest is live, the public
  hostname, TLS routing, networks, limits, secrets, and backup policy.
- This repository has no production SSH access and holds no production secrets.

## Image

- Base: the official `mautic/mautic` Apache image, pinned by digest in the
  `Dockerfile` (`ARG MAUTIC_BASE`).
- Apache listens on **8080** so the web role runs as `www-data` (uid 33) under
  rootless Docker.
- The cron and worker roles keep the official entrypoint.
- The web role uses `deploy/web-entrypoint.sh`: it waits for MySQL, runs
  migrations once installed, trusts the container's own networks as reverse
  proxies (Traefik), and execs Apache.
- The one-shot init service (`deploy/init.sh`) installs Mautic idempotently and
  exits 0 on later runs.
- The runtime contract is published as OCI labels and mirrored in
  `deploy/manifest.yaml` (see `docs/application-contract.md` in `vps-mgmt`).

## Building

```bash
docker build -t mautic-local:test .
```

## Local development

`compose.dev.yaml` runs the image with a MySQL container for local testing. It
is not used in production.

```bash
mkdir -p deploy/secrets.local
printf 'admin@example.com' > deploy/secrets.local/admin_email
printf 'local-password'     > deploy/secrets.local/admin_password
docker compose -f compose.dev.yaml up --build
# http://localhost:8080
```

`deploy/secrets.local/` is git-ignored.

## Publishing

`.github/workflows/publish-image.yml` runs on push to `master`:

1. shellcheck the entrypoints,
2. build the image,
3. validate the contract labels and `deploy/manifest.yaml` agreement,
4. scan with Trivy,
5. push `ghcr.io/dasmedium1/docker-compose-mautic` tagged with the git SHA,
6. call the reusable `create-release-pr.yml` workflow in `vps-mgmt` to propose
   a release PR (requires the `VPS_MGMT_RELEASE_TOKEN` secret).

`.github/workflows/ci.yml` runs the same build and contract validation on pull
requests.

## Repository layout

```
Dockerfile                      # image definition, contract labels
deploy/
  manifest.yaml                 # human-readable contract mirror
  init.sh                       # idempotent installer (one-shot service)
  web-entrypoint.sh             # non-root web entrypoint
  secrets.local.example/        # local dev secret placeholder
compose.dev.yaml                # local-only development stack
.github/workflows/ci.yml        # build + contract validation
.github/workflows/publish-image.yml  # build, scan, publish, propose release
```

## License

MIT — see `LICENSE`.

## Acknowledgments

- Official Mautic Docker images: https://github.com/mautic/docker-mautic
- Platform: https://github.com/dasmedium/vps-mgmt
