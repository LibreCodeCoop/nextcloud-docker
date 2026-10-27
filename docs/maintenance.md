# Image maintenance and release automation

This document is for contributors maintaining this repository's Nextcloud images and GitHub Actions workflows. For user-facing image tags and production upgrade guidance, see [Container images](images.md). For the example Compose installation, see [Deployment](deployment.md).

## Release channels and build sources

The application uses one `.docker/app/Dockerfile` for stable releases and development builds. Its source modes are separate Docker build stages:

- `NEXTCLOUD_SOURCE=release` keeps the Nextcloud payload from the selected official base image.
- `NEXTCLOUD_SOURCE=daily` replaces it with a verified Nextcloud Server daily archive.

The base PHP runtime and Nextcloud server payload are separate inputs. The development channel therefore follows upstream `master` without being tied to the next numbered major.

For daily builds, `NEXTCLOUD_DAILY_URL` identifies the upstream archive. The Dockerfile fetches its SHA-512 checksum and prepares the payload for the official Nextcloud entrypoint. The workflow also records the upstream base image digest and archive checksum for traceability.

The generic image retains required runtime dependencies such as Poppler, UTF-8 locale support, and the PHP bz2 extension. Avoid reinstalling extensions already provided by the official Nextcloud base. Keep LibreSign-specific behavior outside this generic runtime.

The repository Compose example uses `NEXTCLOUD_VERSION` to select the **published LibreCode application image tag** for `app` and `cron`. Builds stay in CI and explicit maintainer commands; this setting does not control the GHCR publication matrix. The `make test-current-app-image` and `make scan-images` maintenance targets use the newest reviewed upstream image reference from `.github/nextcloud-supported.json` (overridable with `APP_BASE_IMAGE`), independently of the deployment image selector.

## Reviewed stable-version inventory

The file `.github/nextcloud-supported.json` is the authoritative **reviewed** inventory for stable-image CI. Its entries contain a major, the current stable patch release, and an EOL month, along with the upstream source and schema version.

The [official Nextcloud Server maintenance wiki](https://github.com/nextcloud/server/wiki/Maintenance-and-Release-Schedule) is the primary source for determining supported majors. The watcher is not driven by the `nextcloud/docker` repository's image-retention list or by third-party EOL services.

The `Discover maintained Nextcloud versions` workflow runs twice a day and on manual dispatch. It uses `scripts/nextcloud-versions.sh` and `scripts/parse-nextcloud-wiki.awk` to:

1. Extract the **Currently supported/maintained versions** table and cross-check the **EOL Versions** table.
2. Reject missing headings, incompatible table structures, duplicate majors, expired EOL months, future release dates, and invalid release numbers.
3. Verify each candidate against an official stable `nextcloud-releases/server` release and the exact `nextcloud:<full-version>-fpm` Docker Hub tag on AMD64 and ARM64.
4. Write the candidate JSON only when validation succeeds.

This job does **not** directly publish or alter production images.

## Reviewing a proposed version change

If the candidate JSON differs from the reviewed file, the watcher proposes a pull request on `automation/nextcloud-supported-versions`.

Review the upstream changes, the proposed additions and removals, the supported PHP/Nextcloud combinations, and the release/EOL transition **before merging**. The bot does not auto-merge.

If a wiki edit cannot be parsed or the upstream sources disagree, the discovery job fails with a GitHub Actions error and job summary. **No JSON change or PR is created on failure** and the existing reviewed inventory is left intact. Enable workflow-failure notifications; a failed schedule should be visible.

The repository or organization must allow GitHub Actions to create pull requests. Because pushes made with `GITHUB_TOKEN` do not trigger ordinary PR workflows, the watcher explicitly dispatches the stable-image workflow on its PR branch. Workflow dispatches outside `main` validate without publishing.

**Signing policy:** the current watcher uses DCO sign-off and GitHub Actions bot commit signing. The Git Signing MCP is used for contributor commits, but is **not yet integrated with the watcher**. Review that limitation before enabling automated commits under a strict signing policy.

## Stable builds and promotion

After review and merge, `.github/workflows/docker-image.yml` loads the committed JSON to create the matrix. It builds each approved `nextcloud:<full-version>-fpm` on AMD64 and ARM64 and builds the web image once.

Trivy vulnerability checks and Bats runtime acceptance are publication gates. Successful jobs publish architecture-specific staging tags. Only when all required matrix jobs pass does `scripts/publish-images.sh` promote the multiarch manifests.

Publication produces:

- `:<major>-fpm` for every approved supported major;
- `:<full-version>-fpm` for the tested patch release;
- `:stable-fpm` and compatibility `:latest` for the **highest approved major**, without a hardcoded major number;
- `:main` and compatibility `:latest` for the independent web image.

Expired EOL months in the approved JSON stop the release workflow instead of silently rebuilding an unsupported version. Existing EOL tags are **not deleted automatically**; they stop being rebuilt after the reviewed inventory changes.

Stable publication runs on pushes to `main` or manual dispatch on `main`. Pull requests and non-`main` dispatches validate without publishing.

## Development image `master-fpm`

The separate `.github/workflows/nextcloud-development.yml` workflow follows the latest upstream Nextcloud Server master archive. It builds and scans AMD64 and ARM64 images, runs runtime acceptance, and promotes `:master-fpm` when its release gates pass.

This development channel is separate from the stable JSON and must not be labeled as a numbered, stable Nextcloud major. Its architecture-specific staging tags are internal publication details.

## Testing and diagnostics

The repository uses Bash, AWK, `jq`, and Bats rather than a separate Python implementation.

```bash
make test-ci-scripts
make test-development-image-scripts
make test-ncdd
make test-scan-images
make test-app-image APP_IMAGE=scan/app:amd64
make test-web-image WEB_IMAGE=scan/web:amd64
make test-current-app-image
```

The wiki parser regression tests include real historical snapshots from 2023 to 2026, a malformed revision, overlapping EOL entries, and a release listed before publication. Publication tests simulate Docker calls so they do not push to the registry.

The runtime acceptance test uses an isolated Docker network and PostgreSQL container, verifies Nextcloud installation and `occ` status, and checks the PHP-FPM interface. Test-created resources are cleaned up. CI must run these tests against the images actually built by the workflow.

The Trivy wrapper tests are part of the offline CI suite. Bats tests are grouped into `tests/ci/` (offline checks), `tests/development/`,
`tests/cli/`, `tests/app/`, and `tests/web/`. The Makefile discovers every
`*.bats` file in the corresponding directory. Add tests there without changing
GitHub Actions or maintaining a file list. The app and web suites require
locally built images passed through `APP_IMAGE` and `WEB_IMAGE`.

For YAML syntax, Shell scripts, and publication changes, use `actionlint`, `ShellCheck`, and the Bats suite before requesting review. Do not weaken vulnerability gates to pass CI.

## Other maintenance decisions

Image metadata should use standard OCI labels wherever possible, including the source, revision, creation time, and version or channel. Record the resolved upstream revision or base image where the source permits. OCI digests are the immutable deployment reference; a commit-based staging tag can be rebuilt and is not a substitute.

Keep tag naming consistent with the official Nextcloud model. Do not introduce `:dev`, `:dev-<major>`, bare `:<major>`, or `:nc-<major>` as new public conventions. The legacy development tag `:35` is not a required compatibility alias; see the consumer analysis in #52.

Dependabot manages Docker and GitHub Actions references, including commit SHA pins and their release-version comments. Renovate handles only regex-managed values (Nextcloud image digests and the Trivy binary version), so the bots do not manage the same dependency. The CI rejects mutable external Actions references. The NCDD reusable-workflow example pins a source-branch snapshot; refresh its commit when updating that template.

The remaining implementation constraints tracked under #47 are to improve metadata when upstream identifiers become available, keep the stable and master publishing contracts aligned, preserve runtime and security gates, and maintain deployment compatibility until replacement approaches are validated.


## Automatic Docker base updates

The supported Nextcloud JSON is the source of truth for the immutable Docker
base references. Renovate updates each supported image tag and digest in a
reviewable pull request. New major versions and EOL transitions remain managed
by the existing maintenance-wiki discovery workflow, which preserves the
Renovate-managed references for already-supported versions.

Dependabot manages the independent Nginx Dockerfile (also digest-pinned) and
GitHub Actions. The stable Docker image workflow runs on pull requests and
reviewed merges to main. It has no scheduled rebuild.

The separate maintenance-wiki discovery cron is only for changes to the
Nextcloud support inventory; it does not build or publish images. Docker base
updates alone do not detect changes in unpinned APT/APK packages.
