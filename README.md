# Nextcloud with Docker

[Português](docs/README_ptBR.md)

A configurable Docker environment for organizations and teams running their own Nextcloud. Maintained by [LibreCode](https://librecode.coop/), this repository combines the Nextcloud application, web server, caching, and database integration in a deployment you can adapt to your infrastructure.

## Why use this project?

- **Control upgrades.** Choose a specific Nextcloud major and plan upgrades instead of unexpectedly moving to a new major.
- **Keep deployment choices open.** Use Docker Compose with Nginx, Redis, PostgreSQL, and optional Garage S3 storage.
- **Use tested image channels.** Published application images follow supported Nextcloud releases; image builds go through vulnerability scanning and runtime checks before publication.
- **Separate production from development.** Versioned stable images and the `master-fpm` development channel serve different needs.

This project is intended for teams that manage their own infrastructure or deliver Nextcloud as a service. It provides deployment tooling, not a hosted Nextcloud subscription.

## Get started

You need Docker Engine with Docker Compose, a domain for public access, and a reverse proxy. This example uses the [LibreCode Nginx proxy](https://github.com/LibreCodeCoop/nginx-proxy); the PostgreSQL Compose extension is included in this repository.

```bash
cp .env.example .env
# Edit .env: domain, credentials, administrator account, and your Nextcloud version.
docker network create reverse-proxy
docker network create postgres
docker compose -f docker-compose.yml -f docker-compose-postgres.yml pull
docker compose -f docker-compose.yml -f docker-compose-postgres.yml up -d
```

The external `reverse-proxy` network must have a configured proxy attached. Set up the proxy and DNS before expecting HTTPS to work. For production, review the PostgreSQL version in the Compose example, your backup strategy, and volume migrations.

For environment variables, existing deployments, storage options, and troubleshooting, see the [deployment guide](docs/deployment.md).

## Nextcloud versions and image updates

Set `NEXTCLOUD_VERSION` in `.env` to select the **published LibreCode application image tag** for both `app` and `cron`. The `web` service uses the independent `nextcloud-docker-web:main` image. The default Compose deployment does not build images locally.

Prebuilt LibreCode application images use versioned tags, such as:

```text
ghcr.io/librecodecoop/nextcloud-docker-app:35-fpm
```

For production, **pin a Nextcloud major or an OCI digest** and plan major upgrades deliberately. The moving `:latest` and `:stable-fpm` aliases can switch to a newer major; they are not safe defaults for unattended production upgrades.

See [image names, tags, and upgrade policy](docs/images.md) for the complete image options.

## Documentation

| Guide | Purpose |
| --- | --- |
| [Deployment and customization](docs/deployment.md) | Installation, configuration, storage, PHP tuning, and logs |
| [Container images](docs/images.md) | Available image tags, compatibility, and safe upgrades |
| [Nextcloud Talk](https://github.com/LibreCodeCoop/nextcloud-docker-talk) | Additional services for Talk |
| [Development commands](docs/ncdd.md) | The `bin/ncdd` interface for local development |
| [Image maintenance](docs/maintenance.md) | Version discovery, workflows, CI checks, and release publication |
