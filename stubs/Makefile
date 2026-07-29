# Variables internas
DOCKER_DEV   = docker compose -f docker-compose.dev.yml
CONTAINER_API = api

# Configuración de Git
GIT_CONFIG_USER_NAME  = {{GIT_USER_NAME}}
GIT_CONFIG_USER_EMAIL = {{GIT_USER_EMAIL}}

# Definición de tareas
.PHONY: help up down restart status logs shell setup migrate fresh seed test install git-config install-hooks tag-list tag-patch tag-minor tag-major tag-push lint lint-check analyse format format-check types-check ci

# Comando por defecto: Muestra la ayuda
help:
	@echo "=== Desarrollo (Dockerfile.dev — sin Octane, recarga en cada request) ==="
	@echo "  make setup     - Configura el proyecto desde cero"
	@echo "  make up        - Levanta los contenedores en segundo plano"
	@echo "  make down      - Detiene los contenedores"
	@echo "  make restart   - Reinicia los contenedores"
	@echo "  make status    - Muestra el estado de los servicios"
	@echo "  make logs      - Muestra los logs en tiempo real"
	@echo "  make shell     - Entra a la terminal del contenedor de la API"
	@echo "  make install   - Ejecuta composer install"
	@echo "  make migrate   - Ejecuta las migraciones de la base de datos"
	@echo "  make fresh     - Borra y recrea la base de datos con migraciones"
	@echo "  make seed      - Ejecuta los seeders de Laravel"
	@echo "  make test      - Ejecuta las pruebas automatizadas (Pest/PHPUnit)"
	@echo ""
	@echo "=== Calidad / CI (corrible manualmente, igual que el pipeline de CI) ==="
	@echo "  make lint          - Corrige estilo de código (Pint)"
	@echo "  make lint-check    - Verifica estilo de código sin corregir (Pint --test)"
	@echo "  make analyse       - Análisis estático (Larastan/PHPStan)"
	# --- frontend:start (requiere Inertia+Vue/React con TS; se omite en Blade y API only) ---
	@echo "  make format        - Corrige formato del frontend (Prettier)"
	@echo "  make format-check  - Verifica formato del frontend sin corregir"
	@echo "  make types-check   - Verifica tipos del frontend (vue-tsc/tsc)"
	# --- frontend:end ---
	@echo "  make ci            - Corre el pipeline de CI en local (lint+analyse+tests)"
	@echo ""
	@echo "=== Git Tags (Versionado Semántico) ==="
	@echo "  make tag-list  - Lista todos los tags existentes"
	@echo "  make tag-patch - Crea un tag de patch (x.y.Z+1)"
	@echo "  make tag-minor - Crea un tag de minor (x.Y+1.0)"
	@echo "  make tag-major - Crea un tag de major (X+1.0.0)"
	@echo "  make tag-push  - Sube todos los tags al repositorio remoto"

# ── Desarrollo ────────────────────────────────────────────────────────────────

up:
	$(DOCKER_DEV) up -d
	@echo "🚀 API corriendo en http://localhost:8000"

down:
	$(DOCKER_DEV) down

restart:
	$(DOCKER_DEV) restart

status:
	$(DOCKER_DEV) ps

logs:
	$(DOCKER_DEV) logs -f $(CONTAINER_API)

shell:
	$(DOCKER_DEV) exec -it $(CONTAINER_API) sh

install:
	$(DOCKER_DEV) exec $(CONTAINER_API) composer install

migrate:
	$(DOCKER_DEV) exec $(CONTAINER_API) php artisan migrate

fresh:
	$(DOCKER_DEV) exec $(CONTAINER_API) php artisan migrate:fresh

seed:
	$(DOCKER_DEV) exec $(CONTAINER_API) php artisan db:seed

test:
	$(DOCKER_DEV) exec -e APP_ENV=testing $(CONTAINER_API) php artisan test --parallel

# ── Calidad / CI ────────────────────────────────────────────────────────────────

lint:
	$(DOCKER_DEV) exec $(CONTAINER_API) composer lint

lint-check:
	$(DOCKER_DEV) exec $(CONTAINER_API) composer lint:check

analyse:
	$(DOCKER_DEV) exec $(CONTAINER_API) composer types:check

ci:
	$(DOCKER_DEV) exec $(CONTAINER_API) composer ci:check

# --- frontend:start (requiere Inertia+Vue/React con TS; se omite en Blade y API only) ---
format:
	$(DOCKER_DEV) exec $(CONTAINER_API) npm run format

format-check:
	$(DOCKER_DEV) exec $(CONTAINER_API) npm run format:check

types-check:
	$(DOCKER_DEV) exec $(CONTAINER_API) npm run types:check
# --- frontend:end ---

# ── Git ───────────────────────────────────────────────────────────────────────

git-config:
	git config --global user.name "$(GIT_CONFIG_USER_NAME)"
	git config --global user.email $(GIT_CONFIG_USER_EMAIL)
	@echo "✅ Configuración global de Git establecida:"
	@echo "   Nombre: $(GIT_CONFIG_USER_NAME)"
	@echo "   Email: $(GIT_CONFIG_USER_EMAIL)"

install-hooks:
	@chmod +x .githooks/pre-commit
	@git config core.hooksPath .githooks
	@echo "✅ Git Hooks activados desde .githooks (core.hooksPath)."

# ── Git Tags ─────────────────────────────────────────────────────────────────

tag-list:
	@git tag --sort=-version:refname | head -20

tag-patch:
	@LATEST=$$(git tag --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
	if [ -z "$$LATEST" ]; then LATEST="v0.0.0"; fi; \
	MAJOR=$$(echo $$LATEST | sed 's/v\([0-9]*\)\..*/\1/'); \
	MINOR=$$(echo $$LATEST | sed 's/v[0-9]*\.\([0-9]*\)\..*/\1/'); \
	PATCH=$$(echo $$LATEST | sed 's/v[0-9]*\.[0-9]*\.\([0-9]*\).*/\1/'); \
	NEXT="v$$MAJOR.$$MINOR.$$((PATCH + 1))"; \
	git tag -a $$NEXT -m "Release $$NEXT"; \
	git push origin $$NEXT; \
	echo "Tag creado: $$NEXT"

tag-minor:
	@LATEST=$$(git tag --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
	if [ -z "$$LATEST" ]; then LATEST="v0.0.0"; fi; \
	MAJOR=$$(echo $$LATEST | sed 's/v\([0-9]*\)\..*/\1/'); \
	MINOR=$$(echo $$LATEST | sed 's/v[0-9]*\.\([0-9]*\)\..*/\1/'); \
	NEXT="v$$MAJOR.$$((MINOR + 1)).0"; \
	git tag -a $$NEXT -m "Release $$NEXT"; \
	git push origin $$NEXT; \
	echo "Tag creado: $$NEXT"

tag-major:
	@LATEST=$$(git tag --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
	if [ -z "$$LATEST" ]; then LATEST="v0.0.0"; fi; \
	MAJOR=$$(echo $$LATEST | sed 's/v\([0-9]*\)\..*/\1/'); \
	NEXT="v$$((MAJOR + 1)).0.0"; \
	git tag -a $$NEXT -m "Release $$NEXT"; \
	git push origin $$NEXT; \
	echo "Tag creado: $$NEXT"

tag-push:
	git push origin --tags
	@echo "Tags subidos al remoto."

# ── Setup ─────────────────────────────────────────────────────────────────────

setup:
	@if [ ! -f .env ]; then cp .env.example .env; echo "✅ Archivo .env creado."; fi
	$(DOCKER_DEV) up -d --build
	@echo "⏳ Esperando a que las bases de datos estén listas..."
	sleep 5
	$(DOCKER_DEV) exec $(CONTAINER_API) composer install
	$(DOCKER_DEV) exec $(CONTAINER_API) php artisan key:generate
	@if [ "$(FORCE)" = "1" ]; then \
		$(DOCKER_DEV) exec $(CONTAINER_API) php artisan migrate:fresh --seed; \
	elif [ "$(FORCE)" = "0" ]; then \
		$(DOCKER_DEV) exec $(CONTAINER_API) php artisan migrate --seed; \
	else \
		printf "  ¿Forzar migraciones? migrate:fresh --seed [y/N]: "; \
		read ANSWER; \
		if [ "$$ANSWER" = "y" ] || [ "$$ANSWER" = "Y" ]; then \
			$(DOCKER_DEV) exec $(CONTAINER_API) php artisan migrate:fresh --seed; \
		else \
			$(DOCKER_DEV) exec $(CONTAINER_API) php artisan migrate --seed; \
		fi; \
	fi
	@make install-hooks
	@echo "🎉 Entorno configurado con éxito."
