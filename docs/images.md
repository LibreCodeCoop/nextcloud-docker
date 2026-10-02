# Container image foundation

This document is the policy reference for the Nextcloud container images built
by `LibreCodeCoop/nextcloud-docker`. It is the source of truth for naming,
tagging, reuse and traceability. If a change here disagrees with a Dockerfile or
a workflow, the change wins and the code must be updated to match.

## Goals

* One reusable runtime foundation shared by development, testing, production and
  application-specific environments.
* Stable images based on the official Nextcloud container images.
* A way to follow Nextcloud Server master without adding a new version-specific
  Dockerfile every development cycle.
* Reproducible, traceable builds with automated testing and security checks.
* LibreCode-specific changes kept small, clear and upstream-first.

## What lives here, and what does not

**This repository provides** the generic Nextcloud runtime:

* `app` — Nextcloud FPM plus the shared runtime tooling (locales, PostgreSQL
  client, `poppler-utils`, `gzip`, `bz2` + `imagick` PHP extensions, the shared
  `php.ini`).
* `web` — the nginx front-end that serves the Nextcloud volume.

**This repository does not provide** anything environment-specific:

* LibreSign code, LibreSign development tooling, Xdebug, XHProf, fixtures.
* Environment configuration (SMTP, S3, domains), which belongs in `.env` and
  `docker-compose.override.yml` of the consuming environment.
* Deployment recipes for specific hosts or cloud providers.

Environments that need more than the generic runtime **extend** the image:

```dockerfile
FROM ghcr.io/librecodecoop/nextcloud-docker-app:nc-34

# LibreSign-specific tooling goes here, not upstream.
COPY my-tooling/ /opt/my-tooling/
```

or mount their own configuration:

```yaml
services:
  app:
    image: ghcr.io/librecodecoop/nextcloud-docker-app:nc-34
    volumes:
      - ./volumes/php/xdebug.ini:/usr/local/etc/php/conf.d/xdebug.ini
```

Do not copy these Dockerfiles into another repository. Rebuilding the same
runtime in a second place is exactly the duplication this foundation exists to
remove.

## Image naming

All images are published to GitHub Container Registry:

```
ghcr.io/librecodecoop/nextcloud-docker-app   # Nextcloud FPM runtime
ghcr.io/librecodecoop/nextcloud-docker-web   # nginx front-end
```

The name is `<registry>/<repository>-<label>`, lowercased. The label matches the
`label` input used by `.github/actions/build-and-scan`, so the build, the scan
reports and the published tags always agree.

## Tagging rules

| Tag | Meaning | Example |
| --- | --- | --- |
| `latest` | Latest stable build of the channel | `:latest` |
| `sha-<commit>` | Immutable build, traceable to a commit | `:sha-b83b696` |
| `sha-<commit>-<arch>` | Per-architecture digest source | `:sha-b83b696-amd64` |
| `nc-<major>` | Stable build for a Nextcloud major | `:nc-34` |
| `dev` | Latest development build (Nextcloud master) | `:dev` |
| `dev-<major>` | Development build for an in-progress major | `:dev-35` |
| `<major>` | **Deprecated alias** of `dev-<major>` | `:35` |

Rules:

1. Every published tag is a multi-arch manifest list (`linux/amd64` +
   `linux/arm64`) unless its name ends in `-amd64` / `-arm64`.
2. `sha-*` tags are immutable. Never re-tag them.
3. Consumers that must not break pin `nc-<major>` or `sha-<commit>`.
   Consumers that want automatic updates use `latest` (stable) or `dev`
   (development).
4. The bare `<major>` tag is kept only so existing environments keep working.
   New consumers must use `dev-<major>`. It will be removed once the migration
   is complete.

## Build channels

Both channels are produced by a single file: `.docker/app/Dockerfile`.

| Channel | `NEXTCLOUD_SOURCE` | Source of Nextcloud | Use |
| --- | --- | --- | --- |
| stable | `release` (default) | The upstream `nextcloud:<tag>` image | production, testing |
| development | `daily` | `latest-master.tar.bz2`, verified by `.sha512` | following Nextcloud master / LibreSign main |

Build arguments:

| Argument | Default | Purpose |
| --- | --- | --- |
| `NEXTCLOUD_VERSION` | `stable-fpm` | Upstream `nextcloud:` image tag |
| `NEXTCLOUD_SOURCE` | `release` | `release` or `daily` |
| `NEXTCLOUD_MAJOR` | empty | Asserted against `version.php` in the `daily` channel |
| `NEXTCLOUD_DAILY_URL` | Nextcloud master daily tarball | Daily tarball URL |
| `PHP_EXTENSION_INSTALLER_VERSION` | pinned release | Reproducible PHP extension installs |
| `VCS_REF` | `unknown` | Git commit, injected by CI |
| `BUILD_DATE` | `unknown` | ISO-8601 build date, injected by CI |

### Adding the next Nextcloud major

When Nextcloud master moves to a new major, **no new Dockerfile is added**.
Change the parameters instead:

* `workflow_dispatch` input `nextcloud_major`, or the scheduled default in
  `.github/workflows/nextcloud-development.yml`;
* the `base_image` input, once the matching official image exists.

This is the property the architecture must preserve across every major bump.

## Traceability

Every image carries OCI labels so any running container can be traced back to
its sources:

| Label | Meaning |
| --- | --- |
| `org.opencontainers.image.source` | This repository |
| `org.opencontainers.image.revision` | Git commit that produced the image |
| `org.opencontainers.image.created` | Build timestamp |
| `org.opencontainers.image.version` | Upstream `nextcloud:` tag used as base |
| `org.librecode.nextcloud.base-image` | Fully resolved upstream base image |
| `org.librecode.nextcloud.major` | Asserted Nextcloud major, when known |

Inspect them with:

```bash
docker inspect --format '{{ json .Config.Labels }}' <image> | jq
```

Reproducibility rules:

* Build arguments are pinned where a released artifact exists
  (`PHP_EXTENSION_INSTALLER_VERSION`).
* The `daily` channel only unpacks a tarball whose `.sha512` matches.
* `sha-<commit>` tags must never be rebuilt from different inputs.

## Testing and security

Automated checks are part of the image lifecycle, not an extra step:

* Every image built in CI is scanned with Trivy for both architectures before
  it is pushed (`scripts/scan-images.sh`, policy in `trivy.yaml`).
* SARIF reports are uploaded to GitHub code scanning.
* A build that fails the scan is not published.
* `make scan-images` runs the same scan locally for the stable channel.
* `bash tests/test-scan-images.sh` and `bash tests/test-hooks.sh` are the
  repository's own regression tests and must pass before merging.

## Deployment recipes

Deployment recipes for specific hosts and cloud providers should **compose**
these images, not rebuild them. A recipe is expected to be:

* a `docker-compose*.yml` plus a `.env.example`, or
* a thin `FROM` of one of these images with only what that environment needs.

Keeping recipes out of the image is what lets the same foundation serve small
low-cost hosts and managed cloud environments alike.

## Principles

1. Prefer upstream solutions over custom replacements.
2. Keep generic Nextcloud images independent from LibreSign-specific needs.
3. Reuse and extend these foundations instead of duplicating runtime definitions.
4. Keep final runtime images focused on what is required to run the service.
5. Security, testability, reproducibility and traceability are default
   requirements, not follow-ups.
6. Never replace a working environment before its replacement is tested and
   ready.
