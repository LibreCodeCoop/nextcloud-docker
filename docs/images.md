# Container images and upgrade policy

The LibreCode Nextcloud images let you choose a maintained Nextcloud release for your environment. This guide describes the **public image names, tags, and update behavior**. For details of how these images are built, tested, and published, see the [maintainer guide](maintenance.md).

## Images

| Image | Purpose |
| --- | --- |
| `ghcr.io/librecodecoop/nextcloud-docker-app` | Nextcloud application runtime with PHP-FPM |
| `ghcr.io/librecodecoop/nextcloud-docker-web` | Nginx web runtime; independent of the Nextcloud major |

The [repository's Docker Compose example](deployment.md) builds its images locally from the official `nextcloud:${NEXTCLOUD_VERSION}` base. It does not automatically pull these GHCR images.

## Application tags

| Tag | Meaning | Update behavior |
| --- | --- | --- |
| `:<major>-fpm`, e.g. `:35-fpm` | One maintained Nextcloud major | Receives updates within that major |
| `:<full-version>-fpm`, e.g. `:35.0.2-fpm` | A particular Nextcloud server release | May be rebuilt with updated base packages |
| `:stable-fpm` | The newest approved, supported major | Can advance to a different major |
| `:latest` | Compatibility alias of `:stable-fpm` | Can advance to a different major |
| `:master-fpm` | Development builds following upstream Nextcloud Server `master` | Changes independently of stable releases |
| `@sha256:<digest>` | Exact OCI image content | Immutable reference |

All currently defined application tags use the `fpm` runtime variant. The `master-fpm` channel is intended for testing and development, not production data.

## Web tags

The web image is not coupled to a Nextcloud release:

| Tag | Meaning |
| --- | --- |
| `:main` | Moving web image from the main development line |
| `:latest` | Compatibility alias of `:main` |
| `@sha256:<digest>` | Exact web image content |

## Production upgrade guidance

**Prefer a major-specific tag** such as `:35-fpm` when you want security and patch updates within the same Nextcloud major. For fully reproducible rollouts, resolve and pin an OCI digest.

Do **not** use the moving `:latest` or `:stable-fpm` application aliases with unattended production upgrades: a new Nextcloud major can require application, database, and data migrations. Back up your installation, confirm compatibility, and follow Nextcloud's supported upgrade path before changing majors.

When a major reaches end of life, it stops receiving rebuilt, maintained images after its removal is approved. Previously published GHCR tags are not automatically deleted, but an existing tag does **not** mean its Nextcloud major is still supported.

See the [official Nextcloud Server maintenance schedule](https://github.com/nextcloud/server/wiki/Maintenance-and-Release-Schedule) for current support dates.

## Image references

Examples of image identifiers:

```text
ghcr.io/librecodecoop/nextcloud-docker-app:35-fpm
ghcr.io/librecodecoop/nextcloud-docker-app:35.0.2-fpm
ghcr.io/librecodecoop/nextcloud-docker-app:master-fpm
ghcr.io/librecodecoop/nextcloud-docker-web:main
ghcr.io/librecodecoop/nextcloud-docker-app@sha256:<digest>
```

A release tag identifies the upstream Nextcloud version, but only an OCI digest identifies exact image content. Repository revision tags used during publishing are not necessarily immutable.

Published OCI metadata identifies the source, revision, build time, version or channel, and relevant runtime information where available. This helps with traceability but does not replace digest pinning.

For maintainers: [version discovery, security gates, and publication workflows](maintenance.md).
