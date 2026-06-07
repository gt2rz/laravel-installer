# Laravel Custom Installer

Instalador personalizado para crear proyectos Laravel listos para Docker, con soporte para:

- Base de datos: PostgreSQL, MySQL o SQLite.
- Cache/sesiones/colas: Redis o modo sin Redis.
- Modo API only opcional (instala Sanctum).
- Reverb opcional (WebSockets).
- Servidor de app:
	- Octane + FrankenPHP (default).
	- Octane + Swoole.
	- Laravel sin Octane (php artisan serve).

El instalador crea un proyecto Laravel nuevo, aplica configuración en .env, descarga stubs de infraestructura y deja un primer commit de Git.

## Uso rápido

### 1) Ejecutar instalador remoto (wizard interactivo)

```bash
curl -fsSL https://raw.githubusercontent.com/gt2rz/test-frankenphp-octane/main/install.sh | bash
```

### 2) Ejecutar con nombre de proyecto y flags (sin wizard)

```bash
curl -fsSL https://raw.githubusercontent.com/gt2rz/test-frankenphp-octane/main/install.sh \
	| bash -s mi-proyecto -- --mysql --api --no-octane
```

### 3) Usar el script local del repo

```bash
chmod +x install.sh
./install.sh mi-proyecto --sqlite --no-redis
```

## Opciones soportadas

- --mysql: usa MySQL en lugar de PostgreSQL.
- --sqlite: usa SQLite en lugar de PostgreSQL.
- --no-redis: desactiva Redis (cache/colas/sesiones en database/file).
- --api: instala Laravel en modo API only (Sanctum, sin Blade/Vite scaffold).
- --reverb: instala Laravel Reverb.
- --no-octane: desactiva Octane y usa php artisan serve.
- --swoole: usa Octane con Swoole (en lugar de FrankenPHP).
- --help: muestra ayuda.

## Requisitos

Obligatorios:

- Bash
- composer
- curl
- git

Opcional (recomendado para desarrollo local con contenedores):

- Docker + Docker Compose

Nota: si Docker no esta instalado, el script igualmente genera archivos.

## Que genera el instalador

Dentro del proyecto creado:

- Proyecto base Laravel (composer create-project).
- Instalacion opcional de:
	- laravel/octane
	- laravel/reverb
	- install:api (Sanctum)
- Archivos descargados desde stubs:
	- Dockerfile (varia por servidor)
	- docker-compose.yml (produccion)
	- docker-compose.dev.yml (varia por DB/Redis)
	- docker-compose.reverb.yml (si --reverb)
	- docker/php/api-optimizations.ini
	- .env.example (normal o sqlite)
- .env generado con app key.
- Repositorio Git inicializado + primer commit.

## Matriz de stubs

### Dockerfile segun servidor

- Octane + FrankenPHP: stubs/Dockerfile
- Octane + Swoole: stubs/Dockerfile.swoole
- Sin Octane: stubs/Dockerfile.plain

### docker-compose.dev.yml segun DB y Redis

- PostgreSQL + Redis: stubs/docker-compose.dev.yml
- PostgreSQL sin Redis: stubs/docker-compose.dev.no-redis.yml
- MySQL + Redis: stubs/docker-compose.dev.mysql.yml
- MySQL sin Redis: stubs/docker-compose.dev.mysql.no-redis.yml
- SQLite + Redis: stubs/docker-compose.dev.sqlite.redis.yml
- SQLite sin Redis: stubs/docker-compose.dev.sqlite.yml

### .env.example segun DB

- PostgreSQL/MySQL: stubs/.env.example
- SQLite: stubs/.env.example.sqlite

## Ejemplos de combinaciones reales

### 1) API simple con SQLite sin Redis y sin Octane

```bash
./install.sh mi-api --sqlite --no-redis --api --no-octane
```

Resultado esperado:

- Base de datos: SQLite
- Redis: no
- Solo API: si
- Reverb: no
- Octane: no
- Dockerfile usado: stubs/Dockerfile.plain
- Compose dev usado: stubs/docker-compose.dev.sqlite.yml

Comando sugerido al final:

```bash
docker compose -f docker-compose.dev.yml up --build
```

### 2) API con MySQL + Redis + Octane (FrankenPHP)

```bash
./install.sh mi-api-pro --mysql --api
```

Resultado esperado:

- Base de datos: MySQL
- Redis: si
- Solo API: si
- Reverb: no
- Octane: si (FrankenPHP)
- Dockerfile usado: stubs/Dockerfile
- Compose dev usado: stubs/docker-compose.dev.mysql.yml

Comando sugerido al final:

```bash
docker compose -f docker-compose.dev.yml up --build
```

### 3) Full app con PostgreSQL sin Redis y con Swoole

```bash
./install.sh mi-app --no-redis --swoole
```

Resultado esperado:

- Base de datos: PostgreSQL
- Redis: no
- Solo API: no
- Reverb: no
- Octane: si (Swoole)
- Dockerfile usado: stubs/Dockerfile.swoole
- Compose dev usado: stubs/docker-compose.dev.no-redis.yml

Comando sugerido al final:

```bash
docker compose -f docker-compose.dev.yml up --build
```

### 4) PostgreSQL + Redis + Reverb (stack realtime)

```bash
./install.sh mi-realtime --reverb
```

Resultado esperado:

- Base de datos: PostgreSQL
- Redis: si
- Solo API: no
- Reverb: si
- Octane: si (FrankenPHP)
- Dockerfile usado: stubs/Dockerfile
- Compose dev usado: stubs/docker-compose.dev.yml
- Compose extra: stubs/docker-compose.reverb.yml

Comando sugerido al final:

```bash
docker compose -f docker-compose.dev.yml -f docker-compose.reverb.yml up --build
```

Nota: cuando usas flags, el wizard interactivo se omite para esas opciones y el script aplica esos valores directamente.

## Tabla rapida de flags y efectos

| Flag | Efecto principal | Impacto en stubs/servicios |
| --- | --- | --- |
| (sin flags) | PostgreSQL + Redis + Octane FrankenPHP | Dockerfile: stubs/Dockerfile, compose dev: stubs/docker-compose.dev.yml |
| --mysql | Cambia DB a MySQL | compose dev: stubs/docker-compose.dev.mysql.yml (o .no-redis) |
| --sqlite | Cambia DB a SQLite | .env.example.sqlite y compose dev sqlite |
| --no-redis | Desactiva Redis | CACHE_STORE=database, SESSION_DRIVER=file, QUEUE_CONNECTION=database; sin servicio redis |
| --api | API only | Ejecuta php artisan install:api (Sanctum) |
| --reverb | Habilita WebSockets Reverb | genera docker-compose.reverb.yml y agrega servicio reverb al levantar con -f extra |
| --no-octane | Sin Octane | Dockerfile: stubs/Dockerfile.plain, comando app: php artisan serve |
| --swoole | Octane con Swoole | Dockerfile: stubs/Dockerfile.swoole, comando app: octane:start --server=swoole |

Precedencia importante:

- --swoole implica Octane activo.
- --no-octane ignora el uso de servidor Octane (FrankenPHP/Swoole) y selecciona Dockerfile.plain.
- Para Redis y DB, el compose dev final se elige por combinacion (ver matriz de stubs).

## Comandos de arranque recomendados

Dentro del proyecto generado:

Sin Reverb:

```bash
docker compose -f docker-compose.dev.yml up --build
```

Con Reverb:

```bash
docker compose -f docker-compose.dev.yml -f docker-compose.reverb.yml up --build
```

## Produccion (referencia)

Se incluye stubs/docker-compose.yml para despliegue con imagen de la app y red externa dokploy-network.

## Personalizacion

Si haces fork, revisa estos valores en install.sh para apuntar a tu propio repositorio de stubs:

- GITHUB_USER
- GITHUB_REPO
- BRANCH

Tambien puedes modificar cualquier plantilla en stubs/ para adaptar Docker, extensiones PHP, variables de entorno o servicios.

## Troubleshooting rapido

### 1) composer no esta instalado

Error tipico:

```text
composer no está instalado.
```

Solucion:

- Instala Composer y verifica con: `composer --version`

### 2) Nombre de proyecto invalido

Error tipico:

```text
Nombre inválido. Solo minúsculas, números, guiones y underscores.
```

Solucion:

- Usa un nombre como: `mi_api`, `mi-api` o `miapi2`
- Evita mayusculas, espacios y caracteres especiales

### 3) El directorio del proyecto ya existe

Error tipico:

```text
Ya existe un directorio 'mi-proyecto'.
```

Solucion:

- Usa otro nombre de proyecto
- O elimina/mueve la carpeta existente antes de ejecutar el script

### 4) Docker no disponible

Mensaje tipico:

```text
docker no encontrado — los archivos se crearán igualmente.
```

Solucion:

- Instala Docker Desktop
- Si solo quieres generar plantilla y repo inicial, puedes ignorar este warning

### 5) Permiso denegado al ejecutar install.sh local

Error tipico:

```text
zsh: permission denied: ./install.sh
```

Solucion:

```bash
chmod +x install.sh
./install.sh mi-proyecto
```

### 6) Fallo descargando stubs (curl/GitHub)

Sintoma:

- El script falla al descargar Dockerfile o docker-compose desde BASE_URL

Solucion:

- Verifica conexion a internet
- Revisa que GITHUB_USER, GITHUB_REPO y BRANCH en install.sh apunten a rutas validas
- Prueba manualmente la URL raw del stub en navegador o con curl

## Documentacion adicional

- docs/frankenphp-migration-guide.md
- docs/concurrency.md
- docs/events-and-jobs.md

## Licencia

MIT.
