COMPOSE ?= docker compose
GARAGES3_COMPOSE_FILE ?= docker-compose-garages3.yml

.PHONY: up-garages3 down-garages3 bootstrap-garages3 garage-status-garages3 start-garages3 wait-nextcloud-garages3 setup-garages3

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
