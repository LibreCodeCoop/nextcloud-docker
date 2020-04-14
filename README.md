# NextCloud with SSL and Docker

## Before first run

Edit the `.env` file to set your database password.

Create a network 

```bash
docker network create reverse-proxy
```

Edit the `docker-compose.yml` and `docker-compose.proxy.yml` and change the environments to your necessity:
| Environment |
|-------------|
| [`VIRTUAL_HOST`](https://github.com/nginx-proxy/nginx-proxy#usage) |
| [`LETSENCRYPT_HOST`](https://github.com/nginx-proxy/docker-letsencrypt-nginx-proxy-companion/blob/master/docs/Basic-usage.md#step-3---proxyed-containers) |
| [`LETSENCRYPT_EMAIL`](https://github.com/nginx-proxy/docker-letsencrypt-nginx-proxy-companion/blob/master/docs/Let's-Encrypt-and-ACME.md#contact-address) |
| [`DEBUG`](https://github.com/nginx-proxy/docker-letsencrypt-nginx-proxy-companion/wiki/Container-configuration#optional-container-environment-variables-for-custom-configuration) |

## Run

```bash
docker-compsoe up -d
docker-compose -f docker-compose.proxy.yml up -d
```
