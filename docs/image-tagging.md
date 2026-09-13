# Container image naming and tags

This repository publishes two image components from the same source tree:

- `ghcr.io/librecodecoop/nextcloud-docker-app`
- `ghcr.io/librecodecoop/nextcloud-docker-web`

The component belongs in the image name. The release channel, upstream version,
revision, and runtime variant belong in the tag or image metadata.

## Channels

Stable images use the Nextcloud release version as the channel tag, for example
`app:31` or `app:31.0.4`. A major tag is moving and follows the latest compatible
patch release. A full version tag is immutable after publication.

Development images follow the current Nextcloud `master` branch. Use `master`
as the moving channel tag, and use `master-<short-revision>` as the immutable
tag for a specific upstream revision. A development image must not identify
itself only by a future Nextcloud major version.

Avoid bare `latest` and bare `dev` tags for new consumers because neither
identifies a release channel or upstream source clearly.

## Runtime variants

Runtime variants are independent of the channel. When a component has more than
one supported runtime, append it to the component tag, for example `31-apache`
and `31-fpm`. This leaves the version and channel meaning unchanged when another
variant is added.

## Traceability

Every published image should expose OCI labels for:

- `org.opencontainers.image.source`: this repository;
- `org.opencontainers.image.revision`: the source commit;
- `org.opencontainers.image.created`: the build timestamp;
- `org.opencontainers.image.version`: the Nextcloud version or `master` revision;
- `org.opencontainers.image.base.name`: the runtime base image.

The image tag selects a channel or an immutable build. OCI labels explain the
exact source and build inputs, so consumers can audit a running image without
guessing from its tag.

## Examples

```text
ghcr.io/librecodecoop/nextcloud-docker-app:31
ghcr.io/librecodecoop/nextcloud-docker-app:31.0.4
ghcr.io/librecodecoop/nextcloud-docker-app:master
ghcr.io/librecodecoop/nextcloud-docker-app:master-a1b2c3d
ghcr.io/librecodecoop/nextcloud-docker-web:31-apache
ghcr.io/librecodecoop/nextcloud-docker-web:master-fpm
```

The examples describe the convention only. This change does not rename existing
images, alter tags, or change the publishing workflows.
