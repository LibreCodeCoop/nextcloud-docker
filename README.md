# NextCloud with SSL and Docker

## Before first run

Edit the `.env` file to set your database password.

Create a network 

```bash
docker network create reverse-proxy
```

Edit the `docker-compose.yml` and `docker-compose.proxy.yml` and change the environments to your necessity:
| Environment | service | 
|-------------|---------|
| [`VIRTUAL_HOST`](https://github.com/nginx-proxy/nginx-proxy#usage) | `web` |
| [`LETSENCRYPT_HOST`](https://github.com/nginx-proxy/docker-letsencrypt-nginx-proxy-companion/blob/master/docs/Basic-usage.md#step-3---proxyed-containers) | `web` |
| [`LETSENCRYPT_EMAIL`](https://github.com/nginx-proxy/docker-letsencrypt-nginx-proxy-companion/blob/master/docs/Let's-Encrypt-and-ACME.md#contact-address) | `web` |
| [`DEBUG`](https://github.com/nginx-proxy/docker-letsencrypt-nginx-proxy-companion/wiki/Container-configuration#optional-container-environment-variables-for-custom-configuration) | `nginx-letsencrypt` |

> **PS**: Let's Encrypt only work in servers when the `VIRTUAL_HOST` and `LETSENCRYPT_HOST` have a valid public domain registered in a DNS server. Don't try to yse in localhost, don't work!

## PHP custom settings

If you need custom settings in PHP, change the file [`.docker/app/config/php.ini`](/.docker/app/config/php.ini).

## Run

```bash
docker-compose up -d
docker-compose -f docker-compose.proxy.yml up -d
```
## Use a specific version of NextCloud

Change the [Dockerfile](/.docker/app/Dockerfile#L1) in line 1 and put your prefered version of NextCloud.

> I suggest to fork this project, change the Dockerfile and make a pull request to me for other people benefit from this change.

Build the images, down the containers and get up again:

```bash
docker-compose build
docker-compose down
docker-compose up -d
```

If you want to see the changes, run:
```bash
docker-compsoe logs -ft
```
You will see this message in the logs and other many upgrade messages:

```
app_1      | 2020-04-28T19:49:38.568623133Z Initializing nextcloud 18.0.4.2 ...
app_1      | 2020-04-28T19:49:38.577733913Z Upgrading nextcloud from 18.0.3.0 ...
```
