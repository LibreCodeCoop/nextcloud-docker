ARG NEXTCLOUD_VERSION=31-fpm

FROM nextcloud:${NEXTCLOUD_VERSION}

ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod uga+x /usr/local/bin/install-php-extensions && sync \
    && install-php-extensions \
    bz2
RUN cat > /usr/local/etc/php/conf.d/php.ini << 'EOF'
post_max_size=20G
upload_max_filesize=20G
opcache.interned_strings_buffer=64
opcache.memory_consumption=256
EOF
