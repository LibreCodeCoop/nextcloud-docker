ARG NEXTCLOUD_BASE_IMAGE=nextcloud:stable-fpm

FROM ${NEXTCLOUD_BASE_IMAGE}

ARG NEXTCLOUD_SOURCE=release
ARG NEXTCLOUD_DAILY_URL=
ARG PHP_EXTENSION_INSTALLER_VERSION=2.12.0
ARG PHP_EXTENSION_INSTALLER_SHA256=3f49c71fa66c79b8b2b96bc0ce92885dafd7946f3b5a46f545b390d6f1617e2c

RUN set -eux; \
    case "${NEXTCLOUD_SOURCE}" in \
        release) \
            ;; \
        daily) \
            test -n "${NEXTCLOUD_DAILY_URL}"; \
            archive_name="$(basename "${NEXTCLOUD_DAILY_URL}")"; \
            curl -fsSL "${NEXTCLOUD_DAILY_URL}" -o "/tmp/${archive_name}"; \
            curl -fsSL "${NEXTCLOUD_DAILY_URL}.sha512" -o "/tmp/${archive_name}.sha512"; \
            expected_sha512="$(awk -v archive="${archive_name}" '$2 == archive { print $1; exit }' "/tmp/${archive_name}.sha512")"; \
            test -n "${expected_sha512}"; \
            echo "${expected_sha512}  /tmp/${archive_name}" | sha512sum -c -; \
            rm -rf /usr/src/nextcloud; \
            tar -xjf "/tmp/${archive_name}" -C /usr/src/; \
            rm -f "/tmp/${archive_name}" "/tmp/${archive_name}.sha512"; \
            rm -rf /usr/src/nextcloud/updater; \
            mkdir -p /usr/src/nextcloud/data /usr/src/nextcloud/custom_apps; \
            chmod +x /usr/src/nextcloud/occ; \
            ;; \
        *) \
            echo "Unsupported NEXTCLOUD_SOURCE: ${NEXTCLOUD_SOURCE}" >&2; \
            exit 2; \
            ;; \
    esac

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gzip \
        locales \
        postgresql-client \
        poppler-utils \
    && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

RUN set -eux; \
    curl -fsSL \
        "https://github.com/mlocati/docker-php-extension-installer/releases/download/${PHP_EXTENSION_INSTALLER_VERSION}/install-php-extensions" \
        -o /usr/local/bin/install-php-extensions; \
    echo "${PHP_EXTENSION_INSTALLER_SHA256}  /usr/local/bin/install-php-extensions" | sha256sum -c -; \
    chmod uga+x /usr/local/bin/install-php-extensions; \
    install-php-extensions bz2 imagick

COPY config/php.ini /usr/local/etc/php/conf.d/
