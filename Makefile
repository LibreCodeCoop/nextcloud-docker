COMPOSE ?= docker compose
GARAGES3_COMPOSE_FILE ?= docker-compose-garages3.yml
APP_TEST_IMAGE ?= nextcloud-app:acceptance
# Maintainer builds use the latest reviewed upstream base, not the deployment image channel.
APP_BASE_IMAGE ?= $(shell jq -er '.versions[-1].image' .github/nextcloud-supported.json)

.PHONY: up-garages3 down-garages3 bootstrap-garages3 garage-status-garages3 start-garages3 wait-nextcloud-garages3 setup-garages3 test-scan-images test-ci-scripts test-development-image-scripts test-ncdd test-app-image test-web-image test-current-app-image scan-images

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

test-scan-images:
	bats tests/ci/scan-images.bats

# Each Bats suite auto-discovers tests from its category directory.
# New tests do not require any Makefile or CI workflow changes.
test-ci-scripts:
	bats tests/ci/*.bats

test-development-image-scripts:
	bats tests/development/*.bats

test-ncdd:
	bats tests/cli/*.bats

test-app-image:
	@test -n "$(APP_IMAGE)" || { echo 'Usage: make test-app-image APP_IMAGE=<local-image>' >&2; exit 2; }
	APP_IMAGE="$(APP_IMAGE)" bats tests/app/*.bats

test-web-image:
	@test -n "$(WEB_IMAGE)" || { echo 'Usage: make test-web-image WEB_IMAGE=<local-image>' >&2; exit 2; }
	WEB_IMAGE="$(WEB_IMAGE)" bats tests/web/*.bats

test-current-app-image:
	@set -e; \
	  base_image='$(APP_BASE_IMAGE)'; \
	  test -n "$$base_image" || { echo 'No approved Nextcloud image in .github/nextcloud-supported.json' >&2; exit 1; }; \
	  docker buildx build --platform linux/amd64 --load --tag "$(APP_TEST_IMAGE)" \
	    --build-arg "NEXTCLOUD_BASE_IMAGE=$$base_image" --file .docker/app/Dockerfile .docker/app; \
	  $(MAKE) test-app-image APP_IMAGE="$(APP_TEST_IMAGE)"

scan-images:
	@set -e; \
	  base_image='$(APP_BASE_IMAGE)'; \
	  test -n "$$base_image" || { echo 'No approved Nextcloud image in .github/nextcloud-supported.json' >&2; exit 1; }; \
	  docker buildx build --platform linux/amd64 --load --tag nextcloud-app:scan-amd64 \
	    --build-arg "NEXTCLOUD_BASE_IMAGE=$$base_image" --file .docker/app/Dockerfile .docker/app; \
	  docker buildx build --platform linux/arm64 --load --tag nextcloud-app:scan-arm64 \
	    --build-arg "NEXTCLOUD_BASE_IMAGE=$$base_image" --file .docker/app/Dockerfile .docker/app; \
	  docker buildx build --platform linux/amd64 --load --tag nextcloud-web:scan-amd64 \
	    --file .docker/web/Dockerfile .docker/web; \
	  docker buildx build --platform linux/arm64 --load --tag nextcloud-web:scan-arm64 \
	    --file .docker/web/Dockerfile .docker/web; \
	  bash scripts/scan-images.sh \
	    'app@linux/amd64=nextcloud-app:scan-amd64' \
	    'app@linux/arm64=nextcloud-app:scan-arm64' \
	    'web@linux/amd64=nextcloud-web:scan-amd64' \
	    'web@linux/arm64=nextcloud-web:scan-arm64'
