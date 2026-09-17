COMPOSE ?= docker compose
GARAGES3_COMPOSE_FILE ?= docker-compose-garages3.yml

.PHONY: up-garages3 down-garages3 bootstrap-garages3 garage-status-garages3 start-garages3 wait-nextcloud-garages3 setup-garages3 test-hooks test-scan-images scan-images

up-garages3:
	$(COMPOSE) -f $(GARAGES3_COMPOSE_FILE) up -d garage

down-garages3:
	$(COMPOSE) -f $(GARAGES3_COMPOSE_FILE) down

garage-status-garages3:
	$(COMPOSE) -f $(GARAGES3_COMPOSE_FILE) exec -T garage /garage status

bootstrap-garages3:
	./scripts/bootstrap-garages3.sh

start-garages3:
	$(COMPOSE) -f $(GARAGES3_COMPOSE_FILE) up -d db app web cron

wait-nextcloud-garages3:
	@until $(COMPOSE) -f $(GARAGES3_COMPOSE_FILE) exec --user www-data app php occ status --output=json 2>/dev/null | grep -q '"installed":true'; do echo "Awaiting Nextcloud"; sleep 10; done

setup-garages3:
	$(MAKE) bootstrap-garages3
	$(MAKE) start-garages3
	$(MAKE) wait-nextcloud-garages3

test-hooks:
	bash tests/test-hooks.sh

test-scan-images:
	bash tests/test-scan-images.sh

scan-images:
	@set -e; \
	  version="$$(sed -n 's/^NEXTCLOUD_VERSION=//p' .env.example | head -n 1)"; \
	  test -n "$$version" || { echo 'NEXTCLOUD_VERSION is missing from .env.example' >&2; exit 1; }; \
	  docker buildx build --platform linux/amd64 --load --tag nextcloud-app:scan-amd64 \
	    --build-arg "NEXTCLOUD_VERSION=$$version" --file .docker/app/Dockerfile .docker/app; \
	  docker buildx build --platform linux/arm64 --load --tag nextcloud-app:scan-arm64 \
	    --build-arg "NEXTCLOUD_VERSION=$$version" --file .docker/app/Dockerfile .docker/app; \
	  docker buildx build --platform linux/amd64 --load --tag nextcloud-web:scan-amd64 \
	    --file .docker/web/Dockerfile .docker/web; \
	  docker buildx build --platform linux/arm64 --load --tag nextcloud-web:scan-arm64 \
	    --file .docker/web/Dockerfile .docker/web; \
	  bash scripts/scan-images.sh \
	    'app-amd64@linux/amd64=nextcloud-app:scan-amd64' \
	    'app-arm64@linux/arm64=nextcloud-app:scan-arm64' \
	    'web-amd64@linux/amd64=nextcloud-web:scan-amd64' \
	    'web-arm64@linux/arm64=nextcloud-web:scan-arm64'
