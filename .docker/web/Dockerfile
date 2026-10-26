FROM nginx:alpine@sha256:892bb2152464f0c5d8972593a5f5afaf8054552580b699d95f8ff4af08c2d33d AS runtime

RUN apk upgrade --no-cache

COPY nginx.conf /etc/nginx/nginx.conf
COPY nextcloud.conf /etc/nginx/nextcloud.conf
