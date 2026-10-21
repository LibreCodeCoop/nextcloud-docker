ARG NGINX_BASE_IMAGE=nginx:alpine
FROM ${NGINX_BASE_IMAGE}

RUN apk upgrade --no-cache

COPY nginx.conf /etc/nginx/nginx.conf
COPY nextcloud.conf /etc/nginx/nextcloud.conf
