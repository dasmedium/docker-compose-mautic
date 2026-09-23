# Todo

## vps-mgmt migration (done)

- [x] Build a non-root Mautic image (Apache on 8080, uid 33).
- [x] Publish the vps-mgmt runtime contract as OCI labels + `deploy/manifest.yaml`.
- [x] Replace SSH deploy/backup/restore/rotate workflows with build/scan/publish
      and a release-PR call into `vps-mgmt`.
- [x] Move production desired state to `vps-mgmt/applications/mautic/`.
- [x] Replace `setup-dc.sh` with an idempotent one-shot init service.
- [x] Add a local-only `compose.dev.yaml`.

## Follow-ups

- [ ] Set `VPS_MGMT_RELEASE_TOKEN` (scoped to `dasmedium/vps-mgmt`) on this repo.
- [ ] Confirm the GHCR namespace (`ghcr.io/dasmedium1/docker-compose-mautic` vs
      `ghcr.io/dasmedium/mautic`) before the first release PR.
- [ ] Tighten the Trivy gate from report-only to failing on HIGH/CRITICAL once
      the base image is clean.
- [ ] Decide the data migration path (fresh install vs. restore of the legacy
      Mautic database and media volumes).
