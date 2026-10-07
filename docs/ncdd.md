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
bin/ncdd doctor
bin/ncdd doctor --json
bin/ncdd shell
bin/ncdd exec --as runtime -- php occ status
bin/ncdd down
```

`runtime` resolves to `www-data` by default and can be overridden with `NCDD_RUNTIME_USER`.

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

The GitHub workflow pins the Bats setup action to an immutable commit SHA and pins the Bats version explicitly.

## Configuration policy

PR #59 intentionally does not introduce `.ncdd.yml`. Environment-specific project contracts may become useful for test-suite definitions later, but adding another configuration format before there is a concrete consumer requirement would duplicate information already present in Compose and `.env`.
