Languages avaliable: [pt-BR](docs/README_ptBR.md)

# Nextcloud with SSL and Docker

- [Nextcloud with SSL and Docker](#nextcloud-with-ssl-and-docker)
  - [Setup of docker](#setup-of-docker)
  - [Setup of proxy](#setup-of-proxy)
  - [Before first run](#before-first-run)
  - [After setup](#after-setup)
  - [Custom setup](#custom-setup)
    - [Customize docker-compose content](#customize-docker-compose-content)
    - [PHP](#php)
  - [Run Nextcloud](#run-nextcloud)
  - [Use a specific version of Nextcloud](#use-a-specific-version-of-nextcloud)
  - [Logs](#logs)

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

### PHP

- Create your `.ini` file at `volumes/php/` folder. Example: `volumes/php/xdebug.ini`
- Alter the file `docker-compose.override.yml` adding your volume
```yaml
services:
  app:
    volumes:
      - ./volumes/php/xdebug.ini:/usr/local/etc/php/conf.d/xdebug.ini
```

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
