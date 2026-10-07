FROM nginx:alpine

RUN apk upgrade --no-cache

COPY nginx.conf /etc/nginx/nginx.conf
COPY nextcloud.conf /etc/nginx/nextcloud.conf
