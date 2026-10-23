# Deployment and customization

This guide covers the example Docker Compose stack shipped with this repository. The default stack **uses the prebuilt LibreCode GHCR images**: `app` and `cron` share a versioned application image, while `web` uses the published Nginx image. Image maintainers can still use the repository's explicit build commands.

Return to the [project overview](../README.md) or see the [published image tags](images.md).

## Prerequisites

Install Docker Engine and the Docker Compose plugin. See the [Docker installation documentation](https://docs.docker.com/engine/install/).

The standard deployment expects a public domain, a reverse proxy that handles HTTPS (for example, [LibreCode nginx-proxy](https://github.com/LibreCodeCoop/nginx-proxy)), and two external Docker networks:

```bash
docker network create reverse-proxy
docker network create postgres
```

Create these networks **once** if they do not exist. Configure the proxy service, DNS, and any Let's Encrypt integration separately. A publicly resolvable domain is required to obtain a public TLS certificate; Let's Encrypt will not issue a certificate for localhost.

## Configure the environment

```bash
cp .env.example .env
```

Edit `.env` before running the services. At a minimum, provide administrator credentials, the database password, and your public domain.

| Variable | Purpose |
| --- | --- |
| `NEXTCLOUD_VERSION` | Tag of the **published LibreCode GHCR application image** used by `app` and `cron`, e.g. `35-fpm` |
| `VIRTUAL_HOST`, `LETSENCRYPT_HOST` | Public domain passed to the external proxy |
| `LETSENCRYPT_EMAIL` | Contact email for certificate management |
| `NEXTCLOUD_TRUSTED_DOMAINS` | Trusted hostnames, including the public domain and the internal `web` host where applicable |
| `NEXTCLOUD_ADMIN_USER`, `NEXTCLOUD_ADMIN_PASSWORD` | Initial administrator credentials |
| `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` | Database name, username, and password |
| `POSTGRES_HOST` | Database host; defaults to `postgres` in the standard Compose extension |
| `TZ` | Container timezone |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE` | Outgoing mail transport |
| `SMTP_NAME`, `SMTP_PASSWORD`, `SMTP_AUTHTYPE` | Optional mail authentication |
| `MAIL_FROM_ADDRESS`, `MAIL_DOMAIN` | Sender address settings |

See `docker-compose.yml` and `.env.example` for the values consumed by the stack.

## Start Nextcloud

The standard setup uses the base Compose file plus the PostgreSQL extension:

```bash
docker compose -f docker-compose.yml -f docker-compose-postgres.yml pull
docker compose -f docker-compose.yml -f docker-compose-postgres.yml up -d
```

The main Compose file provides Nextcloud FPM, an Nginx web container, Redis, and cron. The additional Compose file supplies PostgreSQL and connects the app and cron services to its network.

**Database compatibility:** `docker-compose-postgres.yml` currently uses `postgres:11-alpine`, which is no longer a supported PostgreSQL major. This is a legacy example, not a production-ready database policy. Before a production deployment, choose a supported PostgreSQL version compatible with your Nextcloud release and plan any existing volume migration. Do not simply swap PostgreSQL majors against an existing data directory. The Garage S3 example uses a separate PostgreSQL 16 service; its volume is not interchangeable without migration.

After setup, open `https://your-domain.example/settings/admin/overview` to check the administrator overview.

For maintenance commands, run `occ` as the web-server user:

```bash
docker compose -f docker-compose.yml -f docker-compose-postgres.yml \
  exec -u www-data app php occ status
```

## Choosing and upgrading Nextcloud

Change `NEXTCLOUD_VERSION` in `.env` to select a published LibreCode application image tag for both `app` and `cron`. This setting **does not control** which GHCR images LibreCode builds and publishes.

```bash
docker compose -f docker-compose.yml -f docker-compose-postgres.yml pull app cron web
docker compose -f docker-compose.yml -f docker-compose-postgres.yml up -d
```

Back up the database, application configuration, and persistent files before an upgrade. Check Nextcloud's upgrade requirements and compatibility first: downgrades and skipping unsupported upgrade paths can leave stored data unusable. Use a controlled major-version upgrade process instead of unattended `:latest` changes.

See the [image selection and upgrade policy](images.md) before changing major versions or using immutable OCI digests.

## Optional Garage S3 primary storage

Use the separate `docker-compose-garages3.yml` example if Nextcloud should store primary files in Garage instead of the standard local data directory. This layout uses its own PostgreSQL 16 service.

Set up the required Garage values in `.env`:

- `GARAGES3_BUCKET`, `GARAGES3_KEY_ID`, `GARAGES3_SECRET`
- `GARAGES3_HOSTNAME` (default `host.docker.internal`), `GARAGES3_PORT` (default `3900`)
- `GARAGES3_REGION` (default `garage`), plus TLS/path-style settings as needed

Replace the placeholder `rpc_secret` in `garage/garage.toml` before deployment. Create the bucket and access key for Nextcloud, or use the project's bootstrap commands:

```bash
make up-garages3
make bootstrap-garages3
make setup-garages3
```

The bootstrap may update `.env` with generated credentials. Review its effects before using it on an existing deployment. Do not switch primary storage on a live installation without a migration plan.

## Advanced customization

Add services or override service options in `docker-compose.override.yml`. For example, to load a PHP configuration file:

```yaml
services:
  app:
    volumes:
      - ./volumes/php/custom.ini:/usr/local/etc/php/conf.d/custom.ini:ro
```

PHP-FPM pool settings can also be mounted into `/usr/local/etc/php-fpm.d/`. Keep changes compatible with the underlying Nextcloud PHP version and workload.

## Logs and troubleshooting

```bash
docker compose -f docker-compose.yml -f docker-compose-postgres.yml logs -f --tail=100
```

To inspect available development commands, see [NCDD](ncdd.md). To configure calling and conferencing services, see [Nextcloud Talk](https://github.com/LibreCodeCoop/nextcloud-docker-talk).
