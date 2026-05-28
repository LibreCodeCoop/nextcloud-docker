all: init-all

init-all: init-db init-proxy init-app set-locale set-config init-cron

init-db:
	docker-compose up -d db
	until docker-compose exec db pg_isready; do echo "Awaiting for Postgres"; sleep 5; done

init-proxy:
	docker-compose up -d nginx-proxy mkcert

init-app: 
	docker-compose up -d web app
	until docker-compose exec --user www-data app php occ status --output=json | grep -e "{\"installed\":true,"; do echo "Awaiting for NextCloud installation"; sleep 10; done

LANG=pt_BR
set-locale:
	docker-compose exec --user www-data app php occ config:system:set default_locale --value ${LANG} 
	docker-compose exec --user www-data app php occ config:system:set default_language --value ${LANG} 
	docker-compose exec --user www-data app sh -c "php occ user:setting \$$NEXTCLOUD_ADMIN_USER core lang ${LANG}"

set-config:
	docker-compose exec --user www-data app php occ config:system:set skeletondirectory --value  ""

init-cron: 
	docker-compose up -d cron

GARAGES3_COMPOSE_FILE=docker-compose-garages3.yml

init-all-garages3: init-garages3-db init-garages3-bootstrap init-garages3-volume init-garages3-perms init-garages3-app set-locale-garages3 set-config-garages3 init-garages3-cron

setup-garages3: init-all-garages3

reset-garages3: down-garages3 clean-garages3-state setup-garages3

down-garages3:
	docker compose -f $(GARAGES3_COMPOSE_FILE) down

clean-garages3-state:
	docker run --rm -v $(CURDIR)/volumes/postgres/data:/data alpine:3.20 sh -lc 'rm -rf /data/* /data/.[!.]* /data/..?*'
	docker run --rm -v $(CURDIR)/volumes/nextcloud:/data alpine:3.20 sh -lc 'rm -rf /data/* /data/.[!.]* /data/..?*'
	docker run --rm -v $(CURDIR)/garage:/data alpine:3.20 sh -lc 'mkdir -p /data/meta /data/data && rm -rf /data/meta/* /data/data/*'
	rm -f .env

init-garages3-db:
	docker compose -f $(GARAGES3_COMPOSE_FILE) up -d db
	until docker compose -f $(GARAGES3_COMPOSE_FILE) exec db pg_isready; do echo "Awaiting for Postgres"; sleep 5; done

init-garages3-bootstrap:
	GARAGES3_COMPOSE_FILE=$(GARAGES3_COMPOSE_FILE) GARAGES3_GARAGE_TOML=garage/garage.toml GARAGES3_ENV_FILE=.env GARAGES3_HOSTNAME=garage GARAGES3_AUTO_LAYOUT=true GARAGES3_LAYOUT_ZONE=local GARAGES3_LAYOUT_CAPACITY=1TB ../scripts/bootstrap-garages3.sh

init-garages3-volume:
	docker compose -f $(GARAGES3_COMPOSE_FILE) run --rm --user root --entrypoint sh app -lc 'if [ ! -f /var/www/html/lib/versioncheck.php ]; then cd /usr/src/nextcloud && tar --exclude=./config/s3.config.php -cf - . | tar -xf - -C /var/www/html/; fi'

init-garages3-perms:
	docker compose -f $(GARAGES3_COMPOSE_FILE) run --rm --user root --entrypoint sh app -lc 'find /var/www/html \( -path /var/www/html/config/s3.config.php \) -prune -o -exec chown www-data:www-data {} +'

init-garages3-app:
	docker compose -f $(GARAGES3_COMPOSE_FILE) up -d app
	if ! docker compose -f $(GARAGES3_COMPOSE_FILE) exec -w /var/www/html --user www-data app php occ status --output=json | grep -q "{\"installed\":true,"; then docker compose -f $(GARAGES3_COMPOSE_FILE) exec -w /var/www/html --user www-data app sh -lc 'php occ maintenance:install --database pgsql --database-host "$$POSTGRES_HOST" --database-name "$$POSTGRES_DB" --database-user "$$POSTGRES_USER" --database-pass "$$POSTGRES_PASSWORD" --admin-user "$$NEXTCLOUD_ADMIN_USER" --admin-pass "$$NEXTCLOUD_ADMIN_PASSWORD" --no-interaction'; fi
	until docker compose -f $(GARAGES3_COMPOSE_FILE) exec -w /var/www/html --user www-data app php occ status --output=json | grep -e "{\"installed\":true,"; do echo "Awaiting for NextCloud installation"; sleep 10; done

set-locale-garages3:
	docker compose -f $(GARAGES3_COMPOSE_FILE) exec -w /var/www/html --user www-data app php occ config:system:set default_locale --value ${LANG} 
	docker compose -f $(GARAGES3_COMPOSE_FILE) exec -w /var/www/html --user www-data app php occ config:system:set default_language --value ${LANG} 
	docker compose -f $(GARAGES3_COMPOSE_FILE) exec -w /var/www/html --user www-data app sh -c "php occ user:setting \$$NEXTCLOUD_ADMIN_USER core lang ${LANG}"

set-config-garages3:
	docker compose -f $(GARAGES3_COMPOSE_FILE) exec -w /var/www/html --user www-data app php occ config:system:set skeletondirectory --value  ""

init-garages3-cron:
	docker compose -f $(GARAGES3_COMPOSE_FILE) up -d cron
