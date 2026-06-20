Languages avaliable: [pt-BR](docs/README_ptBR.md)

# Nextcloud with SSL and Docker

- [Nextcloud with SSL and Docker](#nextcloud-with-ssl-and-docker)
  - [Setup of docker](#setup-of-docker)
  - [Setup of proxy](#setup-of-proxy)
  - [Setup of database](#setup-of-database)
  - [Before first run](#before-first-run)
  - [After setup](#after-setup)
  - [Custom setup](#custom-setup)
    - [Customize docker-compose content](#customize-docker-compose-content)
    - [Nextcloud upgrade hooks](#nextcloud-upgrade-hooks)
    - [PHP](#php)
  - [Run Nextcloud](#run-nextcloud)
  - [Use a specific version of Nextcloud](#use-a-specific-version-of-nextcloud)
  - [Logs](#logs)
  - [Nextcloud Talk](#talk)

## Setup of docker

You need to have, on your server, the installed docker. The installation can be done with an official script, following the following steps:
- Download the docker
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
```
- run the script
```bash
sh get-docker.sh
```
- Give permissions to execute the Docker command to your user
```bash
sudo usermod -aG docker $USER
```
- Remove the installation script
```bash
rm get-docker.sh
```

## Setup of proxy

Follow the instructions of this repository:

https://github.com/LibreCodeCoop/nginx-proxy

## Setup of database

Follow the instructions of this repository:

https://github.com/LibreCodeCoop/postgres-docker

## Before first run

Copy the `.env.example` to `.env` and set the values.

```bash
cp .env.example .env
```

| Environment | service | Description |
|-------------|---------|-------|
| [`VIRTUAL_HOST`](https://github.com/nginx-proxy/nginx-proxy#usage) | `web` | Your domain |
| [`LETSENCRYPT_HOST`](https://github.com/nginx-proxy/docker-letsencrypt-nginx-proxy-companion/blob/master/docs/Basic-usage.md#step-3---proxyed-containers) | `web` | Your domain |
| [`LETSENCRYPT_EMAIL`](https://github.com/nginx-proxy/docker-letsencrypt-nginx-proxy-companion/blob/master/docs/Let's-Encrypt-and-ACME.md#contact-address) | `web` | Your sysadmin email |
| `NEXTCLOUD_TRUSTED_DOMAINS` | `app` | domains separated by comma. The domain web is mandatory, add your domain together with whe domain web. The domain `web` is the domain of Nginx service. |
| `POSTGRES_DB` | `db` | PostgreSQL database name (default: nextcloud) |
| `POSTGRES_USER` | `db` | PostgreSQL database user (default: nextcloud) |
| `POSTGRES_PASSWORD` | `db` | PostgreSQL database user password |
| `POSTGRES_HOST` | `app` | PostgreSQL server host (default: postgres) |
| `NEXTCLOUD_ADMIN_USER` | `app` | Nextcloud administrator username |
| `NEXTCLOUD_ADMIN_PASSWORD` | `app` | Nextcloud administrator password |
| `NEXTCLOUD_ADMIN_EMAIL` | `app` | Nextcloud administrator email |
| `SMTP_HOST` | `app` | SMTP server for email sending |
| `SMTP_SECURE` | `app` | SMTP security type (ssl, tls, or empty) |
| `SMTP_PORT` | `app` | SMTP server port |
| `SMTP_AUTHTYPE` | `app` | SMTP authentication type (LOGIN, PLAIN, NTLM) |
| `SMTP_NAME` | `app` | Username for SMTP authentication |
| `SMTP_PASSWORD` | `app` | Password for SMTP authentication |
| `MAIL_FROM_ADDRESS` | `app` | Sender email address |
| `MAIL_DOMAIN` | `app` | Sender email domain |
| `TZ` | `app` | Timezone (e.g., America/Sao_Paulo) |
| `TRASHBIN_RETENTION_OBLIGATION` | `app` | Number of days files should remain in the recycle bin before being cleaned. |

> **PS**: Let's Encrypt only work in servers when the `VIRTUAL_HOST` and `LETSENCRYPT_HOST` have a valid public domain registered in a DNS server. Don't try to use in localhost, don't work!

Create a network 

```bash
docker network create reverse-proxy
docker network create postgres
```

## After setup

After finish the setup, access this url: https://yourdomain.tld/settings/admin/overview.

If is necessary run any occ command, run like this:

```bash
docker compose exec -u www-data app ./occ db:add-missing-indices
docker compose exec -u www-data app ./occ db:convert-filecache-bigint
```

## Custom setup

### Customize docker-compose content

You can do this using environments and creating a file called `docker-compose.override.yml` to add new services.

### Redis

The main compose files now include a `redis` service by default. This keeps the stack self-contained for Nextcloud installations that already use Redis in `config.php` and avoids depending on a host-specific external network.

### Nextcloud upgrade hooks

This repository mounts the official Nextcloud Docker hook directories so you can extend install and upgrade flows without touching the image entrypoint.

The `app` service uses these mounts:

```yaml
services:
  app:
    volumes:
      - ./volumes/nextcloud:/var/www/html
      - ./backups:/backups
      - ./app-hooks/pre-installation:/docker-entrypoint-hooks.d/pre-installation
      - ./app-hooks/post-installation:/docker-entrypoint-hooks.d/post-installation
      - ./app-hooks/pre-upgrade:/docker-entrypoint-hooks.d/pre-upgrade
      - ./app-hooks/post-upgrade:/docker-entrypoint-hooks.d/post-upgrade
      - ./app-hooks/before-starting:/docker-entrypoint-hooks.d/before-starting
```

The upgrade hooks behave like this:

- `pre-upgrade`: checks free disk space on the Nextcloud volume and the backup volume
- `pre-upgrade`: creates a compressed PostgreSQL dump at `/backups`
- `post-upgrade`: runs the extra `occ` commands needed after a major upgrade

The following variables control the safety check and backup location:

- `NEXTCLOUD_BACKUP_DIR`, defaulting to `/backups`
- `NEXTCLOUD_UPGRADE_MIN_FREE_MB`, defaulting to `2048`

The `./backups` directory on the host must be writable by `www-data` inside the container. The recommended host-side ownership is `www-data:www-data` with mode `0755`.

### Garage S3 primary storage

Use `docker-compose-garages3.yml` when you want Nextcloud to store files in a Garage S3 bucket instead of the local `data/` directory.

The stack expects these values in `.env`:

- `GARAGES3_BUCKET`
- `GARAGES3_KEY`
- `GARAGES3_KEY_ID`
- `GARAGES3_SECRET`
- `GARAGES3_HOSTNAME`, defaulting to `host.docker.internal`
- `GARAGES3_PORT`, defaulting to `3900`
- `GARAGES3_REGION`, defaulting to `garage`

Create the bucket and access key in Garage before starting Nextcloud with this compose file. `GARAGES3_KEY_ID` must contain the Garage access key ID used by Nextcloud.

The Garage service uses `garage/garage.toml`. Update `rpc_secret` before using it in a real environment.

Use `make up-garages3` to start Garage, and `make bootstrap-garages3` to create the Garage bucket and access key.
The bootstrap updates `.env` in place with the generated Garage credentials.
Use `make setup-garages3` to run the full setup and wait for Nextcloud to report as installed.
The stack now uses PostgreSQL 16. If you already created the database volume with an older PostgreSQL major version, recreate or migrate that volume once before starting the updated compose file.

For a clean local installation, use `make reset-garages3`.
Use `make setup-garages3` if you want to keep the existing local state and only rerun the setup steps.

Basic flow:

1. Copy `.env.example` to `.env` if needed.
2. Update `garage/garage.toml` and replace the placeholder `rpc_secret`.
3. Run `make setup-garages3`.
4. Open the Nextcloud URL and finish the initial admin setup if it is still pending.

### PHP

- Create your `.ini` file at `volumes/php/` folder. Example: `volumes/php/xdebug.ini`
- Alter the file `docker-compose.override.yml` adding your volume
```yaml
services:
  app:
    volumes:
      - ./volumes/php/xdebug.ini:/usr/local/etc/php/conf.d/xdebug.ini
```


### PHP-FPM

- For PHP-FPM modifications, include the following volume to the app service in `docker-compose.override.yml` file:
```yaml
services:
  app:
    volumes:
      - ./volumes/php/pm.conf:/usr/local/etc/php-fpm.d/www2.conf
```
- Create a file  `./volumes/php/pm.conf` with the following content (see references for tunning according your setup):
```yaml
[www]
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
```

- References:
- https://docs.nextcloud.com/server/21/admin_manual/installation/server_tuning.html#tune-php-fpm
- https://spot13.com/pmcalculator/

## Run Nextcloud

```bash
# The postgres service is executed separated to be possible reuse this service to other applications that use PostgreSQL
docker compose up -f docker-compose-postgres.yml -d
docker compose up -d
docker compose -d
```
## Use a specific version of Nextcloud

Change the value of NEXTCLOUD_VERSION at `.env` file and put the tag name that you want to use. Check the availables tags here: https://hub.docker.com/_/nextcloud/tags

Build the images, down the containers and get up again:

```bash
docker compose build --pull
docker compose up -d
```

## Logs

If you want to see the logs, run:

```bash
docker compose logs -f --tail=100
```
You will see this message in the logs and other many upgrade messages:

```log
app_1      | 2020-04-28T19:49:38.568623133Z Initializing nextcloud 18.0.4.2 ...
app_1      | 2020-04-28T19:49:38.577733913Z Upgrading nextcloud from 18.0.3.0 ...
```

## Talk

For setting up Nextcloud Talk with all services, see [here](https://github.com/LibreCodeCoop/nextcloud-docker-talk).
