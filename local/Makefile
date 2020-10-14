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
