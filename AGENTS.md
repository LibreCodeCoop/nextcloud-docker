# NCDD agent contract

Use `bin/ncdd` for stack operations. Do not reproduce Docker Compose commands in agent instructions unless debugging NCDD itself.

Keep Git checkout and authentication outside the containers. App worktrees belong under `volumes/nextcloud/apps-extra/`.

Use `bin/ncdd doctor --json` for machine-readable environment diagnostics. See `docs/ncdd.md` for the command contract.
