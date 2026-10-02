FROM nginx:alpine

# Refresh the Alpine packages at build time.
#
# The upstream tag is not rebuilt the moment a security fix lands in the Alpine
# repository, so an image built straight from it can ship CVEs that are already
# fixed. Upgrading here keeps the runtime patched without waiting for the
# upstream rebuild. The scan policy in trivy.yaml is what verifies this.
RUN apk upgrade --no-cache

COPY nginx.conf /etc/nginx/nginx.conf
COPY nextcloud.conf /etc/nginx/nextcloud.conf
