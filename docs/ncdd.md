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

## Test API

Projects can define test working directories, commands, and users in `.ncdd.yml`. The CLI keeps the container details out of developer and agent instructions:

```bash
ncdd test --list
ncdd test phpunit
ncdd test phpunit tests/php/Unit/Service/FooTest.php
ncdd test behat tests/integration/features/file/validate.feature
ncdd test frontend lint
ncdd test frontend types
ncdd test full
```

`ncdd test --json ...` emits a compact machine-readable result while preserving the test output on stderr.

The default PHPUnit command includes `-c tests/php/phpunit.xml`, and Behat defaults to the configured runtime user. This keeps bootstrap and permission details in the NCDD contract rather than in every CI job or agent prompt.

## Reproducible scenarios

Regression reproductions can be versioned as small YAML files:

```yaml
nextcloud: stable35
setup:
  - composer dump-autoload
tests:
  - phpunit tests/php/Unit/Service/Policy/ValidationEffectivePolicyServiceTest.php
  - behat features/file/validate.feature
  - frontend lint
teardown: []
```

Run a scenario with:

```bash
ncdd scenario run .ncdd/scenarios/issue-1234.yml
```

NCDD owns environment startup and teardown, so an issue, PR, or security regression can use the same reproduction locally and in CI.

## GitHub Actions

The reusable workflow runs the same NCDD contract used locally. A consumer repository can call:

```yaml
jobs:
  ncdd:
    uses: LibreCodeCoop/nextcloud-docker/.github/workflows/test-nextcloud-app.yml@main
    with:
      nextcloud: stable35
      suite: full
```

Pull requests test the checked-out PR ref. Manual workflows can pass a branch, commit, focused target, or scenario. The workflow uploads the doctor result, test result, test log, and stack log as artifacts.

A complete consumer example is available at `templates/workflows/ncdd-tests.yml`.

## Dev Containers and Codespaces

`templates/devcontainer/` provides a Docker-in-Docker Dev Container that installs NCDD into `~/.local/share/ncdd`, exposes the CLI on `PATH`, and forwards port 8080.

Copy the template to an app repository as `.devcontainer/`. The terminal then uses the same commands as a local checkout or CI:

```bash
ncdd up --nextcloud 35
ncdd doctor --json
ncdd test phpunit
ncdd test behat path/to/feature
ncdd down
```

Codespaces consumes the same Dev Container definition; it is not a separate NCDD implementation.
