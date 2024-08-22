ARG NEXTCLOUD_VERSION=stable-fpm

FROM nextcloud:${NEXTCLOUD_VERSION}

ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod uga+x /usr/local/bin/install-php-extensions && sync \
    && install-php-extensions \
    bz2

COPY config/php.ini /usr/local/etc/php/conf.d/
