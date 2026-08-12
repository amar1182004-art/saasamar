SHELL := /bin/sh

.PHONY: setup up down restart logs ps test smoke clean

setup:
	@test -f .env || cp .env.example .env
	docker compose build

down:
	docker compose down

up:
	@test -f .env || cp .env.example .env
	docker compose up -d --build

restart: down up

logs:
	docker compose logs -f --tail=200

ps:
	docker compose ps

test: smoke

smoke:
	sh scripts/smoke.sh

clean:
	docker compose down -v --remove-orphans
