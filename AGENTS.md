# NCDD agent contract

NCDD is the supported interface for development and test automation in this repository.

- Use `ncdd up`, `ncdd status`, `ncdd doctor --json`, `ncdd exec`, `ncdd shell`, `ncdd test`, and `ncdd down`.
- Do not call `docker compose` directly unless debugging NCDD itself.
- Do not install PHP, Composer, Node, or Nextcloud on the host.
- Keep private Git authentication in the host or CI checkout. Mount the checkout into NCDD instead of fetching private repositories inside containers.
- Use `--as runtime` for commands that must run as the Nextcloud runtime user.
- Prefer focused `ncdd test` commands before full suites.
- Treat `.ncdd.yml` as the project contract; do not hard-code container names or `/var/www/html` paths in automation.
