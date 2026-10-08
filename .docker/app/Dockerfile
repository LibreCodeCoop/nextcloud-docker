ARG NEXTCLOUD_BASE_IMAGE=nextcloud:stable-fpm
ARG NEXTCLOUD_SOURCE=release

FROM ${NEXTCLOUD_BASE_IMAGE} AS release

FROM ${NEXTCLOUD_BASE_IMAGE} AS daily
ARG NEXTCLOUD_DAILY_URL
RUN set -eux; \
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
    chmod +x /usr/src/nextcloud/occ

FROM ${NEXTCLOUD_SOURCE} AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gzip \
        postgresql-client \
    && rm -rf /var/lib/apt/lists/*

COPY config/php.ini /usr/local/etc/php/conf.d/
