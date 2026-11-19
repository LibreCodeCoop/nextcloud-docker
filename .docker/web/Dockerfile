FROM nginx:alpine@sha256:a3554c0d0b48177b1413c26e01f695334428020d9df01243fbae3e11cfd17417

RUN apk upgrade --no-cache

COPY nginx.conf /etc/nginx/nginx.conf
COPY nextcloud.conf /etc/nginx/nextcloud.conf
