# NCDD command interface

NCDD should expose a stable command surface without creating a second development stack.

## Architecture

`bin/ncdd` is a thin orchestration layer over the files that already define this repository:

- `docker-compose.yml`
- `docker-compose-postgres.yml`
- `.env` / `.env.example`

It must not duplicate the stack, own a second version source, or redefine image versions.

The Makefile remains focused on repository maintenance tasks. It only exposes `test-ncdd` as a convenience for running the CLI test suite; runtime behavior belongs to `bin/ncdd`.

## Commands

```bash
bin/ncdd up
bin/ncdd status
bin/ncdd logs app
bin/ncdd doctor
bin/ncdd doctor --json
bin/ncdd shell
bin/ncdd exec --as runtime -- php occ status
bin/ncdd down
```

`runtime` resolves to `www-data` by default and can be overridden with `NCDD_RUNTIME_USER`.

Use `bin/ncdd logs` for diagnostics instead of rebuilding the underlying Compose command. Optional service names are passed through to Compose.

## Git and app source

NCDD does not fetch application repositories and does not receive GitHub credentials. Human users, CI, and agents perform the checkout outside the containers.

Application worktrees should be placed under the existing Nextcloud tree:

```text
volumes/nextcloud/apps-extra/<app-id>
```

That keeps public and private branches identical from NCDD's point of view and avoids container-specific Git authentication.

## Version source

There is no NCDD version constant in the CLI. The Nextcloud image version is read from the existing `NEXTCLOUD_VERSION` environment variable, then `.env`, then `.env.example`.

A separate NCDD release/version mechanism should only be introduced if the project actually starts publishing the CLI independently.

## Testing

The CLI is Bash, so its behavior is covered with Bats rather than ad-hoc shell assertions. CI also runs ShellCheck.

```bash
make test-ncdd
```

The GitHub workflow pins the Bats setup action to an immutable commit SHA. The action selects its current default Bats version, avoiding a second version pin that would need separate maintenance.

## Focused app tests

NCDD exposes a small test API for test runners that require the existing Nextcloud runtime:

```bash
bin/ncdd test --list
bin/ncdd test phpunit --app libresign -- -c tests/php/phpunit.xml tests/php/Unit/FooTest.php
bin/ncdd test behat --app libresign -- features/file/validate.feature
```

The app source must already exist under `volumes/nextcloud/apps-extra/<app-id>`. NCDD does not clone repositories or receive Git credentials.

Arguments after `--` are passed directly to the selected test runner as an argument array; NCDD does not evaluate them through a shell. PHPUnit runs as root by default and can be changed with `NCDD_PHPUNIT_USER`. Behat runs as the configured runtime user and supplies the Nextcloud integration environment used by app test suites.

The initial API intentionally supports only PHPUnit and Behat. Frontend runners, scenario files, and project-specific configuration are not introduced until a concrete consumer requires them.

## Configuration policy

NCDD still does not introduce `.ncdd.yml`. Test behavior uses explicit CLI arguments and narrowly scoped environment variables so the repository does not acquire a second configuration model before it is necessary.

## GitHub Actions consumer workflow

The reusable workflow `.github/workflows/test-nextcloud-app.yml` lets an app repository run the same NCDD test contract in GitHub Actions.

It intentionally follows the current NCDD scope:

- PHPUnit and Behat only;
- the app is checked out under `volumes/nextcloud/apps-extra/<app-id>`;
- no `.ncdd.yml`;
- no alternate Compose stack;
- no scenario or frontend mini-framework.

A consumer can call it with:

```yaml
jobs:
  ncdd:
    uses: LibreCodeCoop/nextcloud-docker/.github/workflows/test-nextcloud-app.yml@main
    with:
      suite: phpunit
```

`app_id` defaults to the caller repository name and can be overridden when the repository name differs from the Nextcloud app id. `target` is a single runner argument and is passed without shell evaluation.

The workflow can install Composer dependencies before starting NCDD. This bootstrap runs in the GitHub-hosted workspace, while Nextcloud and the selected test runner execute through NCDD. Set `composer_install: false` when the caller provides dependencies by another mechanism.

The workflow uses the Nextcloud version already defined by this repository. It does not introduce a second Nextcloud version input.

A ready-to-copy caller example is available at `templates/workflows/ncdd-tests.yml`.

Dev Containers and Codespaces are deliberately outside this increment. They should only be added after the reusable CI contract has been exercised by a real app repository.
