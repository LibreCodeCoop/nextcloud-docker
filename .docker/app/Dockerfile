# syntax=docker/dockerfile:1
#
# Reusable Nextcloud (FPM) runtime image.
#
# One Dockerfile covers both build channels:
#
#   * release (default): the official Nextcloud image content, plus the
#     LibreCode runtime tooling shared by every environment.
#   * daily: the same runtime tooling on top of the current Nextcloud master
#     daily tarball, for development environments that must follow the
#     Nextcloud public APIs without waiting for an alpha/beta/RC.
#
# Build args (see docs/images.md for the full policy):
#
#   NEXTCLOUD_VERSION          upstream image tag (e.g. 34-fpm, stable-fpm)
#   NEXTCLOUD_SOURCE           "release" (default) or "daily"
#   NEXTCLOUD_MAJOR            optional assertion, e.g. "35" for the daily build
#   NEXTCLOUD_DAILY_URL        daily tarball URL
#   PHP_EXTENSION_INSTALLER_VERSION  pinned installer release
#   VCS_REF / BUILD_DATE       injected by CI for traceability
#
# Nothing LibreSign-specific belongs here. Environments that need extra tools
# must extend this image (FROM ...) or mount their own configuration.

ARG NEXTCLOUD_VERSION=stable-fpm

FROM nextcloud:${NEXTCLOUD_VERSION}

# --- Traceability metadata ----------------------------------------------------
# Filled in by CI; local builds keep the "unknown" defaults.
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown
ARG NEXTCLOUD_MAJOR=

LABEL org.opencontainers.image.title="Nextcloud app runtime" \
      org.opencontainers.image.description="Reusable Nextcloud FPM runtime foundation maintained by LibreCode" \
      org.opencontainers.image.source="https://github.com/LibreCodeCoop/nextcloud-docker" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${NEXTCLOUD_VERSION}" \
      org.librecode.nextcloud.base-image="nextcloud:${NEXTCLOUD_VERSION}" \
      org.librecode.nextcloud.major="${NEXTCLOUD_MAJOR}"

# --- Optional development overlay --------------------------------------------
# Replaces /usr/src/nextcloud (the seed the official entrypoint copies into
# /var/www/html) with the current Nextcloud master. Verified against the
# published .sha512 before being unpacked.
ARG NEXTCLOUD_SOURCE=release
ARG NEXTCLOUD_DAILY_URL=https://download.nextcloud.com/server/daily/latest-master.tar.bz2

RUN set -eux; \
    case "${NEXTCLOUD_SOURCE}" in \
      release) \
        echo "Using the upstream Nextcloud sources shipped in the base image" \
        ;; \
      daily) \
        archive="${NEXTCLOUD_DAILY_URL##*/}"; \
        curl -fsSL "${NEXTCLOUD_DAILY_URL}" -o "/tmp/${archive}"; \
        curl -fsSL "${NEXTCLOUD_DAILY_URL}.sha512" -o "/tmp/${archive}.sha512"; \
        cd /tmp; \
        expected_sha512="$(awk -v name="${archive}" '$2 == name { print $1 }' "${archive}.sha512")"; \
        test -n "${expected_sha512}"; \
        echo "${expected_sha512}  ${archive}" | sha512sum -c -; \
        rm -rf /usr/src/nextcloud; \
        tar -xjf "${archive}" -C /usr/src/; \
        nextcloud_major="$(php -r 'require "/usr/src/nextcloud/version.php"; echo $OC_Version[0];')"; \
        if [ -n "${NEXTCLOUD_MAJOR}" ]; then test "${nextcloud_major}" = "${NEXTCLOUD_MAJOR}"; fi; \
        rm -f "/tmp/${archive}" "/tmp/${archive}.sha512"; \
        rm -rf /usr/src/nextcloud/updater; \
        mkdir -p /usr/src/nextcloud/data /usr/src/nextcloud/custom_apps; \
        chmod +x /usr/src/nextcloud/occ \
        ;; \
      *) \
        echo "unsupported NEXTCLOUD_SOURCE=${NEXTCLOUD_SOURCE}" >&2; exit 1 \
        ;; \
    esac

# --- Shared runtime tooling ---------------------------------------------------
# Kept identical for every channel so stable and development images follow the
# same maintenance and security rules.
#
# The upgrade step matters: the upstream Nextcloud tag is not rebuilt the moment
# a security fix lands in Debian, so building straight from it can ship CVEs
# that are already fixed. Refreshing the packages here keeps the runtime patched
# without waiting for an upstream rebuild. trivy.yaml is what verifies it.
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        gzip \
        locales \
        postgresql-client \
        poppler-utils \
    && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Pinned so image builds are reproducible and traceable to a released installer.
ARG PHP_EXTENSION_INSTALLER_VERSION=2.12.0
ADD https://github.com/mlocati/docker-php-extension-installer/releases/download/${PHP_EXTENSION_INSTALLER_VERSION}/install-php-extensions /usr/local/bin/
RUN chmod uga+x /usr/local/bin/install-php-extensions && sync \
    && install-php-extensions \
        bz2 \
        imagick

COPY config/php.ini /usr/local/etc/php/conf.d/
