# NextCloud with SSL and Docker

## Before first run

Edit the `.env` file to set your database password.

Create a network 

```bash
docker network create reverse-proxy
```

## Run

```bash
docker-compsoe up -d
docker-compose -f docker-compose.proxy.yml up -d
```