# Hallazgos detectados probando `laravel_sso` — para corregir en el instalador

Contexto: se probó de punta a punta un proyecto generado por este instalador (`laravel_sso`, stack Postgres + Redis, sin Octane) — build Docker, migraciones, seed y suite de tests. Esto documenta qué falló, por qué, y qué de eso es responsabilidad de `stubs/` (afecta a **todo** proyecto generado) vs. qué fue deriva local de ese proyecto (no aplica acá).

---

## 1. Bug confirmado — `make test` da falsos negativos en Docker dev

**Síntoma:** corriendo `make test` dentro del contenedor `api`, 22 de 52 tests fallaban con `419` (CSRF token mismatch) o "session missing key [errors]".

**Causa raíz:** `stubs/docker-compose.dev.yml` fija `APP_ENV: local` como variable de entorno del contenedor (línea `environment: APP_ENV: local`). `stubs/phpunit.xml` define `<env name="APP_ENV" value="testing"/>` — pero sin `force="true"`. PHPUnit **no pisa una variable de entorno del SO que ya existe**; solo la setea si no existe. Como el contenedor ya trae `APP_ENV=local` inyectada por Compose, `app()->environment()` resuelve a `local` en vez de `testing`, el middleware CSRF deja de saltarse (`runningUnitTests()` da `false`), y cualquier test que haga `POST`/`PATCH`/`DELETE` sin token CSRF explícito falla.

Esto **no es un bug de la app generada**, es un bug del propio andamiaje del instalador — afecta a cualquier proyecto generado con Docker dev, apenas tenga tests de features que escriban (settings, auth, etc.). Confirmado corriendo el mismo comando con `-e APP_ENV=testing` inyectado manualmente: pasa a 52/52.

**Archivos afectados:**
- `stubs/Makefile` (target `test`)
- Posiblemente todas las variantes de `stubs/docker-compose.dev*.yml` (todas fijan `APP_ENV: local` a nivel de contenedor)

**Fix recomendado (el más simple, ya validado en `laravel_sso`):**

```diff
 test:
-	$(DOCKER_DEV) exec $(CONTAINER_API) php artisan test --parallel
+	$(DOCKER_DEV) exec -e APP_ENV=testing $(CONTAINER_API) php artisan test --parallel
```

**Alternativa más robusta (defensa en profundidad, opcional además de la anterior):** agregar `force="true"` a los `<env>` de `stubs/phpunit.xml` para que el archivo de test siempre gane, sin depender de que cada invocación se acuerde de pasar `-e APP_ENV=testing`:

```diff
-<env name="APP_ENV" value="testing"/>
+<env name="APP_ENV" value="testing" force="true"/>
```

Cualquiera de las dos resuelve el problema; la combinación de ambas es lo más a prueba de errores.

---

## 2. Actualización — `paratest` faltante SÍ era responsabilidad del instalador

**Corrección (2026-07-29):** la verificación original de este punto estaba mal hecha — se comprobó `brianium/paratest` contra el `composer.json` de la raíz de *este* repo (laravel-installer), no contra lo que `install.sh` realmente genera. Los proyectos nuevos se crean con `composer create-project laravel/laravel` (o los starter kits de Inertia), cuyo skeleton base **no incluye `paratest`**. El `composer.json` de este repo ya lo tenía porque se agregó a mano en algún momento — eso no significa que `install.sh` lo instale en cada proyecto nuevo.

**Confirmado en la práctica:** al usar el instalador, `make test` (que corre `php artisan test --parallel`) falla apenas se genera el proyecto porque falta `paratest`, tal como predecía el hallazgo #1 de este documento para cualquier stack Docker — pero la causa aquí no es `APP_ENV`, es la dependencia ausente.

**Fix aplicado:** se agregó en `install.sh` un paso `install_paratest` (justo después de crear el proyecto, antes de Octane) que corre `composer require --dev brianium/paratest --quiet` incondicionalmente, ya que `stubs/Makefile` siempre usa `--parallel`.

Lo único que seguía sin ser responsabilidad del instalador:

- **Volumen de Postgres sin `/data`**: `laravel_sso/docker-compose.dev.yml` tenía `postgres_data:/var/lib/postgresql` (sin el sufijo `/data`), lo cual ya estaba documentado en el propio `plan.md` del proyecto como "bug preexistente". Verificado: `stubs/docker-compose.dev.yml` ya usa el path correcto (`/var/lib/postgresql/data`). No hace falta tocar nada acá — solo re-sincronizar ese archivo en `laravel_sso` desde el stub actual.

---

## 3. Sugerencia opcional (no es un bug, es hardening)

Durante el primer build desde cero (sin caché) del `Dockerfile`, hubo timeouts intermitentes bajando `php:8.4-cli`/`composer:2`/paquetes `apt` — causado por la red de la VM de Colima en la máquina de prueba, no por el Dockerfile en sí (se confirmó reiniciando Colima). Como hardening opcional y de bajo costo, se podría hacer el paso de `apt-get` en `stubs/Dockerfile` más tolerante a redes lentas/intermitentes:

```diff
-RUN apt-get update && apt-get install -y --no-install-recommends \
+RUN echo 'Acquire::Retries "5"; Acquire::http::Timeout "30";' > /etc/apt/apt.conf.d/80-retries \
+  && apt-get update && apt-get install -y --no-install-recommends \
   git \
   openssh-client \
   unzip \
   && rm -rf /var/lib/apt/lists/* \
   && install-php-extensions gd pdo_pgsql zip intl pcntl opcache redis
```

Prioridad baja — no bloquea nada, solo reduce la chance de tener que reintentar un build en redes inestables.

---

## Resumen de acción

| Ítem | Acción | Prioridad |
|---|---|---|
| `APP_ENV` no forzado en `make test` | Editar `stubs/Makefile` (+ opcional `stubs/phpunit.xml` con `force="true"`) | Alta — afecta a todo proyecto nuevo |
| Volumen Postgres sin `/data` | Nada que hacer en el instalador; re-sincronizar `laravel_sso` desde el stub | N/A (ya resuelto acá) |
| `paratest` faltante | Nada que hacer en el instalador; re-sincronizar `laravel_sso` | N/A (ya resuelto acá) |
| Retries de `apt-get` en Dockerfile | Opcional, hardening | Baja |
