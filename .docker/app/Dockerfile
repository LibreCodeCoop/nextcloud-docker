FROM nextcloud:stable-fpm

RUN apt-get update

# Install Imagick
RUN apt-get install -y libmagickwand-dev
RUN docker-php-ext-enable imagick

COPY config/php.ini /usr/local/etc/php/conf.d/
