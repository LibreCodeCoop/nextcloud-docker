# NCDD development interface

NCDD provides one interface for local development, AI agents, CI, Dev Containers, and Codespaces. Docker Compose is an implementation detail behind the `ncdd` command.

## Quick start

From an app checkout, copy `.ncdd.yml.example` to `.ncdd.yml` and adjust the app id if necessary. Then run:

```bash
/path/to/nextcloud-docker/bin/ncdd up --nextcloud 35
/path/to/nextcloud-docker/bin/ncdd doctor
/path/to/nextcloud-docker/bin/ncdd shell
/path/to/nextcloud-docker/bin/ncdd down
```

`35` and `stable35` resolve to the same Nextcloud ref. The source checkout is mounted into the environment; private Git authentication never needs to be copied into a container.

## Project contract

`.ncdd.yml` supports the following scalar settings:

```yaml
nextcloud:
  default: stable35
app:
  id: libresign
  source: .
  path: /var/www/html/apps-extra/libresign
  runtime_user: www-data
services:
  app: app
  worker: dev-worker
http:
  port: 8080
```

Environment variables and command-line flags can override the contract. `NCDD_APP_IMAGE` can select a prebuilt Nextcloud development image explicitly.

## Diagnostics

`ncdd env` prints the fully resolved environment. `ncdd doctor` checks Docker, Compose, the app service, and `occ status`. Agents and CI should prefer `ncdd doctor --json`.

## Execution users

`ncdd exec` defaults to the development worker. Use aliases instead of implementation-specific usernames:

```bash
ncdd exec -- composer dump-autoload
ncdd exec --as runtime -- php occ status
ncdd exec --as root -- id
```

`runtime` resolves to `app.runtime_user` (normally `www-data`).

## Private branches and forks

Check out private code on the host or in the CI workspace and mount it:

```bash
gh repo clone OWNER/PRIVATE-FORK app
ncdd --project-root app --source app up --nextcloud stable35
```

Do not run `git fetch` for private repositories from inside the runtime containers.
