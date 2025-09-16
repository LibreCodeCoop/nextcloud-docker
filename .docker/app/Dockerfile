ARG NEXTCLOUD_VERSION=31-fpm

FROM nextcloud:${NEXTCLOUD_VERSION}

ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod uga+x /usr/local/bin/install-php-extensions && sync \
    && install-php-extensions \
    @composer \
    bz2 \
    xdebug

ENV PHP_PM_MAX_CHILDREN=30
ENV PHP_PM_START_SERVERS=10
ENV PHP_PM_MIN_SPARE_SERVERS=10
ENV PHP_PM_MAX_SPARE_SERVERS=30

RUN apt-get update \
    && apt-get install -y \
        locales \
        poppler-utils \
    && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

RUN set -eux; \
    mkdir -p /usr/local/etc/php-fpm.d; \
    echo '[www]' >> /usr/local/etc/php-fpm.d/zz-pm.conf; \
    echo "pm.max_children = ${PHP_PM_MAX_CHILDREN}" >> /usr/local/etc/php-fpm.d/zz-pm.conf; \
    echo "pm.start_servers = ${PHP_PM_START_SERVERS}" >> /usr/local/etc/php-fpm.d/zz-pm.conf; \
    echo "pm.min_spare_servers = ${PHP_PM_MIN_SPARE_SERVERS}" >> /usr/local/etc/php-fpm.d/zz-pm.conf; \
    echo "pm.max_spare_servers = ${PHP_PM_MAX_SPARE_SERVERS}" >> /usr/local/etc/php-fpm.d/zz-pm.conf;

COPY config/php.ini /usr/local/etc/php/conf.d/

