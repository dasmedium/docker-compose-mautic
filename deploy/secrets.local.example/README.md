# Local development secrets (example)

Copy this directory to `deploy/secrets.local/` and fill in the two files used
by `compose.dev.yaml`:

    deploy/secrets.local/admin_email     # e.g. admin@example.com
    deploy/secrets.local/admin_password  # local-only password

`deploy/secrets.local/` is git-ignored. It exists only to run the local
development stack; production secrets are provisioned on the VPS by
`dasmedium/vps-mgmt` (`provisioning/playbooks/provision-app.yml`) and never
live in this repository.
