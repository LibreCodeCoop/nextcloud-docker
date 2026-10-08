# Container image naming and tagging

This document is the source of truth for image names, tags, runtime variants, and traceability for images published by this repository.

The convention intentionally stays close to the official Nextcloud image model. Channel or server version, runtime variant, and immutable image identity are separate concerns.

## Image names

Published image names describe the component contained in the image:

- `ghcr.io/librecodecoop/nextcloud-docker-app` — Nextcloud application runtime.
- `ghcr.io/librecodecoop/nextcloud-docker-web` — web/proxy runtime published by this repository.

Version, development channel, and runtime variant belong in tags, not in the image name.

Do not create a new image name merely to represent a Nextcloud major or development channel.

## App image tags

The app image follows the tag structure used by the official Nextcloud images.

| Reference | Meaning | Behavior |
| --- | --- | --- |
| `:<major>-fpm` | Stable release channel within one Nextcloud major, for example `35-fpm` | Moving |
| `:<full-version>-fpm` | A specific Nextcloud server release, for example `35.0.1-fpm` | Release-specific tag; may be rebuilt |
| `:stable-fpm` | Current stable Nextcloud channel, when this alias is intentionally published | Moving |
| `:master-fpm` | Development channel following Nextcloud Server `master` | Moving |
| `@sha256:<digest>` | Exact OCI image content | Immutable |

The runtime variant is the suffix after the channel or version. The currently defined app runtime variant is `fpm`.

A future runtime variant, such as `apache`, must preserve the same channel/version semantics instead of introducing a different naming system.

The development channel must follow upstream `master`; it must not be identified by a future Nextcloud major.

## Web image tags

The web image is not tied to a Nextcloud server version.

Use:

- `:main` for the moving image built from this repository's main development line;
- `@sha256:<digest>` when an exact immutable image is required.

Do not add a Nextcloud major to the web image tag unless the web image itself gains a real version-dependent contract.

## Moving tags and immutable references

Moving tags are convenient channel selectors. Their target can change when a new image is published.

Examples:

- `35-fpm`;
- `stable-fpm`;
- `master-fpm`;
- `main` for the web image.

Use a moving tag when following a maintained channel is intentional.

The canonical immutable identity of a published image is its OCI digest:

```
ghcr.io/librecodecoop/nextcloud-docker-app@sha256:<digest>
```

A tag containing a repository commit, such as `sha-<commit>`, may be useful for traceability but is not inherently immutable if a rebuild can resolve different upstream packages or base-image content.

A full Nextcloud release tag such as `35.0.1-fpm` identifies the server release clearly, but the OCI digest is still the exact image identity.

## Tags that are not part of the new contract

Do not introduce these as the repository convention:

- bare `:latest`;
- `:dev`;
- `:dev-<major>`;
- `:stable-<major>-fpm`;
- `:nc-<major>`;
- bare `:<major>`;
- a development tag tied only to the next Nextcloud major.

Historical tags may continue to exist temporarily while old implementations are replaced, but their existence does not make them part of this contract.

The historical development tag `:35` does not require a compatibility alias: the consumer inventory in #52 found no active consumer that depends on it.

## Traceability metadata

Every image published under this convention must expose enough metadata to identify both this repository build and the relevant upstream runtime.

Use standard OCI labels where the standard already defines the meaning:

- `org.opencontainers.image.source` — source repository URL;
- `org.opencontainers.image.revision` — source repository revision used for the build;
- `org.opencontainers.image.created` — build timestamp;
- `org.opencontainers.image.version` — human-readable image/server version or channel where applicable.

The published metadata must also identify:

- Nextcloud version or upstream revision;
- PHP version for the app runtime;
- runtime variant, such as `fpm`;
- resolved upstream/base image when applicable.

Project-specific labels may be used for metadata that has no suitable OCI standard label, but they must not replace an existing OCI label.

Traceability metadata does not replace an OCI digest when an immutable reference is required.

## Examples

Stable moving app channel:

```
ghcr.io/librecodecoop/nextcloud-docker-app:35-fpm
```

Specific stable Nextcloud release:

```
ghcr.io/librecodecoop/nextcloud-docker-app:35.0.1-fpm
```

Development channel following Nextcloud Server `master`:

```
ghcr.io/librecodecoop/nextcloud-docker-app:master-fpm
```

Moving web image:

```
ghcr.io/librecodecoop/nextcloud-docker-web:main
```

Immutable stable app image after resolving the digest of the selected stable build:

```
ghcr.io/librecodecoop/nextcloud-docker-app@sha256:<stable-image-digest>
```

Immutable development app image after resolving the digest published for the `master-fpm` build:

```
ghcr.io/librecodecoop/nextcloud-docker-app@sha256:<master-image-digest>
```

Immutable web image:

```
ghcr.io/librecodecoop/nextcloud-docker-web@sha256:<web-image-digest>
```

## App image build sources

The app image uses a single `.docker/app/Dockerfile` for both release and development builds.

The Dockerfile models its two source modes as Docker build stages instead of runtime shell branching:

- `NEXTCLOUD_SOURCE=release` selects the stage that keeps the Nextcloud payload provided by the selected official Nextcloud base image;
- `NEXTCLOUD_SOURCE=daily` selects the stage that replaces that payload with a verified upstream daily archive.

The base runtime and the Nextcloud server payload are separate inputs. A development build can therefore follow Nextcloud Server `master` without introducing a Dockerfile or image identity tied to a future major.

For daily builds, `NEXTCLOUD_DAILY_URL` is required. The Dockerfile downloads the matching `.sha512` file, verifies the archive, and prepares `/usr/src/nextcloud` in the layout expected by the official Nextcloud entrypoint.

The repository Compose environment keeps `NEXTCLOUD_VERSION` as its user-facing version setting and maps it to the generic official base image. There is no second Compose stack for development images.

The app image remains LibreSign-ready while being generic across Nextcloud versions. It keeps repository-level runtime requirements such as Poppler, UTF-8 locale support, and the PHP bz2 extension, but does not reinstall extensions already supplied by the official Nextcloud base image such as Imagick. Dependabot owns Docker and GitHub Actions updates in this repository. Renovate is deliberately restricted to custom regex-managed values that Dependabot cannot see, currently the explicit Trivy binary version used by CI. The two bots must not manage the same dependency.

## Runtime acceptance

The app image has a runtime acceptance test based on the same behavioral checks used by the official Nextcloud container projects.

The test operates on an already-built local image. It does not rebuild the image and does not use the repository deployment Compose files:

```bash
make test-app-image APP_IMAGE=scan/app:amd64
```

For a local build of the current app image followed by the same acceptance test:

```bash
make test-current-app-image
```

The Bats acceptance test creates an isolated Docker network and PostgreSQL container, starts the image with Nextcloud autoinstall variables, waits for the installation, runs `occ status` and `occ check`, and sends a FastCGI request through the FPM runtime. Test-created resources are removed on success and failure.

CI must run this test against the exact locally loaded app images produced by the build step. Runtime acceptance is a publication gate alongside vulnerability scanning; a separate deployment-stack test is not required for this contract.

## Implementation boundary

This document defines the target contract and the generic app-image foundation now implements the release/daily source split.

Remaining work in #47 must continue incrementally. In particular:

- publish development images from the generic foundation using the documented `:master-fpm` contract;
- add the remaining OCI traceability metadata to published images;
- keep LibreSign-specific behavior out of the generic runtime;
- preserve scan and runtime-acceptance gates before publication;
- preserve the existing Compose environment until a replacement is explicitly validated.
