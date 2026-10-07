ARG NCDD_APP_IMAGE=ghcr.io/librecodecoop/nextcloud-docker-app:35
FROM composer:2 AS composer
FROM ${NCDD_APP_IMAGE}

RUN apt-get update \
    && apt-get install -y --no-install-recommends git unzip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer /usr/bin/composer /usr/local/bin/composer
