# Image maintenance and release automation

This document is for contributors maintaining this repository's Nextcloud images and GitHub Actions workflows. For user-facing image tags and production upgrade guidance, see [Container images](images.md). For the example Compose installation, see [Deployment](deployment.md).

## Release channels and build sources

The application uses one `.docker/app/Dockerfile` for stable releases and development builds. Its source modes are separate Docker build stages:

- `NEXTCLOUD_SOURCE=release` keeps the Nextcloud payload from the selected official base image.
- `NEXTCLOUD_SOURCE=daily` replaces it with a verified Nextcloud Server daily archive.

The base PHP runtime and Nextcloud server payload are separate inputs. The development channel therefore follows upstream `master` without being tied to the next numbered major.

For daily builds, `NEXTCLOUD_DAILY_URL` identifies the upstream archive. The Dockerfile fetches its SHA-512 checksum and prepares the payload for the official Nextcloud entrypoint. The workflow also records the upstream base image digest and archive checksum for traceability.

The generic image retains required runtime dependencies such as Poppler, UTF-8 locale support, and the PHP bz2 extension. Avoid reinstalling extensions already provided by the official Nextcloud base. Keep LibreSign-specific behavior outside this generic runtime.

The repository Compose example retains `NEXTCLOUD_VERSION` as its user-facing setting for the **locally built official base image**. It does not control the GHCR publication matrix.

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

Stable publication runs on pushes to `main`, a weekly rebuild schedule, or manual dispatch on `main`. Pull requests and non-`main` dispatches validate without publishing.

## Development image `master-fpm`

The separate `.github/workflows/nextcloud-development.yml` workflow follows the latest upstream Nextcloud Server master archive. It builds and scans AMD64 and ARM64 images, runs runtime acceptance, and promotes `:master-fpm` when its release gates pass.

This development channel is separate from the stable JSON and must not be labeled as a numbered, stable Nextcloud major. Its architecture-specific staging tags are internal publication details.

## Testing and diagnostics

The repository uses Bash, AWK, `jq`, and Bats rather than a separate Python implementation.

```bash
make test-ci-scripts
make test-development-image-scripts
bash tests/test-scan-images.sh
make test-app-image APP_IMAGE=scan/app:amd64
make test-current-app-image
```

The wiki parser regression tests include real historical snapshots from 2023 to 2026, a malformed revision, overlapping EOL entries, and a release listed before publication. Publication tests simulate Docker calls so they do not push to the registry.

The runtime acceptance test uses an isolated Docker network and PostgreSQL container, verifies Nextcloud installation and `occ` status, and checks the PHP-FPM interface. Test-created resources are cleaned up. CI must run these tests against the images actually built by the workflow.

For YAML syntax, Shell scripts, and publication changes, use `actionlint`, `ShellCheck`, and the Bats suite before requesting review. Do not weaken vulnerability gates to pass CI.

## Other maintenance decisions

Image metadata should use standard OCI labels wherever possible, including the source, revision, creation time, and version or channel. Record the resolved upstream revision or base image where the source permits. OCI digests are the immutable deployment reference; a commit-based staging tag can be rebuilt and is not a substitute.

Keep tag naming consistent with the official Nextcloud model. Do not introduce `:dev`, `:dev-<major>`, bare `:<major>`, or `:nc-<major>` as new public conventions. The legacy development tag `:35` is not a required compatibility alias; see the consumer analysis in #52.

Dependabot manages Docker and GitHub Actions dependencies. Renovate is limited to regex-managed values Dependabot cannot discover (currently the explicitly pinned Trivy binary version), so the two bots do not manage the same dependency.

The remaining implementation constraints tracked under #47 are to improve metadata when upstream identifiers become available, keep the stable and master publishing contracts aligned, preserve runtime and security gates, and maintain deployment compatibility until replacement approaches are validated.

## PHP runtime security policy

Image builds use complementary controls: Trivy scans OS and application
dependencies, while the PHP runtime policy checks the installed interpreter
against the PHP project's live JSON release feed:
https://www.php.net/releases/branches.php

The image checker runs centrally via scripts/scan-images.sh for both linux/amd64
and linux/arm64 application images. It rejects unsupported branches, PHP versions
older than the latest upstream patch, and upstream network failures. This also
covers the case where an official Nextcloud base contains a PHP binary built
outside Debian's package manager and therefore missed by package CVE scanners.

This policy is intentionally more conservative than a CVE-only feed: even routine
PHP patch releases can block image publishing until the official Nextcloud parent
images catch up. It is designed for upstream-derived PHP images, not vendor
distro packages with independently attested security backports. Bats remains
responsible for functional acceptance of the Nextcloud image.

Run offline policy tests with:
    python3 -m unittest discover -s tests -p 'test_php_runtime.py'

Run on a built image with:
    scripts/check-php-runtime.py --image scan/app:amd64 --platform linux/amd64

## Automatic upstream rebuild detection

The scheduled monitor workflow checks the reviewed Nextcloud base tags every six
hours. It compares their remote OCI manifest digests with the digest and Git
revision recorded in both the amd64 and arm64 images currently published on GHCR.

When the official base is updated and both architectures contain a supported,
current PHP security patch, the monitor requests a new run of
docker-image.yml using workflow_dispatch. The build pins the exact upstream
digest resolved at build start and only promotes images after the existing
Trivy scan and Nextcloud runtime tests succeed. If nothing changed, it skips
the build. If the base still ships outdated PHP, it opens or updates a single
security tracking issue and checks again at the next interval. The issue
is closed automatically when all reviewed bases have current PHP runtimes.

A missing GHCR image or provenance label also requires a rebuild; this ensures
existing images without embedded base digests are refreshed once after rollout.
Network or registry inspection failures fail the monitor rather than treating
unknown status as a clean result. The existing weekly full build remains as a
separate safety net, while release discovery continues to propose reviewed
changes for new Nextcloud versions.

This workflow runs only after changes are merged to main. Running the monitor
on an unmerged branch never dispatches a production image build or modifies issues.
