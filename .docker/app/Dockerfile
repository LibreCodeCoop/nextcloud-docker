ARG NEXTCLOUD_BASE_IMAGE=nextcloud:stable-fpm
ARG NEXTCLOUD_SOURCE=release

FROM mlocati/php-extension-installer:2.12.0 AS php-extension-installer

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

# Stop builds before publication when upstream PHP still lacks the October 2026 RCE fixes.
# CVE-2026-109618 / CVE-2026-109619; unsupported PHP branches fail closed.
RUN php -r '$minimum = ["8.2" => "8.2.35", "8.3" => "8.3.36", "8.4" => "8.4.27", "8.5" => "8.5.12"]; $series = PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION; if (!isset($minimum[$series]) || version_compare(PHP_VERSION, $minimum[$series], "<")) { fwrite(STDERR, "Unpatched or unsupported PHP runtime: " . PHP_VERSION . PHP_EOL); exit(1); }'


RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        locales \
        poppler-utils \
    && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

COPY --from=php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/install-php-extensions
RUN install-php-extensions \
        bz2 \
    && rm /usr/local/bin/install-php-extensions

COPY config/php.ini /usr/local/etc/php/conf.d/
