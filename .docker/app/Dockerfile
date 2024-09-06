ARG NEXTCLOUD_VERSION=stable-fpm

ENV PHP_PM_MAX_CHILDREN=10
ENV PHP_PM_START_SERVERS=2
ENV PHP_PM_MIN_SPARE_SERVERS=1
ENV PHP_PM_MAX_SPARE_SERVERS=3

FROM nextcloud:${NEXTCLOUD_VERSION}

ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod uga+x /usr/local/bin/install-php-extensions && sync \
    && install-php-extensions \
    bz2


    
RUN set -eux; \
    echo '[www]' > /usr/local/etc/php-fpm.d/zz-pm.conf; \
    echo "pm.max_children = ${PHP_PM_MAX_CHILDREN}" >> /usr/local/etc/php-fpm.d/zz-pm.conf; \
    echo "pm.start_servers = ${PHP_PM_START_SERVERS}" >> /usr/local/etc/php-fpm.d/zz-pm.conf; \
    echo "pm.min_spare_servers = ${PHP_PM_MIN_SPARE_SERVERS}" >> /usr/local/etc/php-fpm.d/zz-pm.conf; \
    echo "pm.max_spare_servers = ${PHP_PM_MAX_SPARE_SERVERS}" >> /usr/local/etc/php-fpm.d/zz-pm.conf

COPY config/php.ini /usr/local/etc/php/conf.d/