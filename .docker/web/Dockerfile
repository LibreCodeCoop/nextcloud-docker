FROM nginx:alpine@sha256:892bb2152464f0c5d8972593a5f5afaf8054552580b699d95a8c2d33d

RUN apk upgrade --no-cache

COPY nginx.conf /etc/nginx/nginx.conf
COPY nextcloud.conf /etc/nginx/nextcloud.conf
