# Laravel Custom Installer

Instalador personalizado para crear proyectos Laravel listos para Docker, con soporte para:

- Base de datos: PostgreSQL, MySQL o SQLite.
- Cache/sesiones/colas: Redis o modo sin Redis.
- Frontend: Blade (default), Inertia + Vue o Inertia + React (starter kits oficiales de Laravel, con auth vía Fortify).
- Modo API only opcional (instala Sanctum, sin Blade ni Vite).
- Reverb opcional (WebSockets).
- Servidor de app:
	- Octane + FrankenPHP (default).
	- Octane + Swoole.
	- Laravel sin Octane (php artisan serve).

El instalador crea un proyecto Laravel nuevo, aplica configuración en .env, descarga stubs de infraestructura y deja un primer commit de Git. Cada herramienta opcional (Octane, Reverb, Resend, Sentry, stubs individuales, etc.) se instala de forma independiente: si una falla, el script avisa y continúa con el resto en lugar de abortar todo el proceso.

## Uso rápido

### 1) Ejecutar instalador remoto (wizard interactivo)

```bash
curl -fsSL https://raw.githubusercontent.com/gt2rz/laravel-installer/main/install.sh | bash
```

### 2) Ejecutar con nombre de proyecto y flags (sin wizard)

```bash
curl -fsSL https://raw.githubusercontent.com/gt2rz/laravel-installer/main/install.sh \
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
- --inertia-vue: frontend con Inertia + Vue (starter kit oficial laravel/vue-starter-kit, incluye páginas de auth vía Fortify).
- --inertia-react: frontend con Inertia + React (starter kit oficial laravel/react-starter-kit, incluye páginas de auth vía Fortify).
- --reverb: instala Laravel Reverb.
- --no-octane: desactiva Octane y usa php artisan serve.
- --swoole: usa Octane con Swoole (en lugar de FrankenPHP).
- --help: muestra ayuda.

Nota: --api es incompatible con --inertia-vue/--inertia-react (API only no usa Blade/Vite).

## Requisitos

Obligatorios:

- Bash
- composer
- curl
- git

Opcional (recomendado para desarrollo local con contenedores):

- Docker + Docker Compose

Nota: si Docker no esta instalado, el script igualmente genera archivos.

Nota: Node/npm no son requisito del instalador ni del host. Para proyectos con Inertia (o el Blade + Vite por defecto), el build de los assets del frontend ocurre dentro de la imagen Docker de produccion (etapa `assets` en el Dockerfile), no en la maquina donde corres install.sh.

## Que genera el instalador

Dentro del proyecto creado:

- Proyecto base Laravel (composer create-project). Para frontend Inertia, el paquete base es directamente laravel/vue-starter-kit o laravel/react-starter-kit (incluyen Fortify + Inertia + Vite ya configurados) en lugar de laravel/laravel.
- Instalacion opcional de:
	- laravel/octane
	- laravel/reverb
	- install:api (Sanctum), con limpieza de resources/js, resources/css, vite.config.js y package.json cuando es API only
- Archivos descargados desde stubs:
	- Dockerfile (varia por servidor; incluye build de assets con Node salvo en modo API only)
	- docker-compose.yml (produccion)
	- docker-compose.dev.yml (varia por DB/Redis)
	- docker-compose.reverb.yml (si --reverb)
	- docker/php/api-optimizations.ini
	- routes/web.php (solo en frontend Blade; se omite en modo API only y en Inertia, donde ya vienen las rutas del starter kit)
	- .env.example (normal o sqlite)
- .env generado con app key.
- Repositorio Git inicializado + primer commit.

Si alguna herramienta opcional falla (por ejemplo un `composer require` que no responde, o la descarga de un stub), el instalador lo avisa en el momento y sigue con el resto. Al final se imprime un resumen tipo:

```text
⚠ Algunas herramientas opcionales no se instalaron:
    - Reverb
    - Colección Bruno
  El resto del proyecto está listo; puedes instalarlas manualmente.
```

Solo un fallo en la creación del proyecto base (`composer create-project`) o en la generación de `.env`/`APP_KEY` aborta el instalador por completo (ahí sí se limpia el directorio creado, porque no queda un proyecto usable).

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

### 5) Frontend con Inertia + Vue

```bash
./install.sh mi-app-vue --inertia-vue
```

Resultado esperado:

- Base de datos: PostgreSQL
- Redis: si
- Solo API: no
- Frontend: Inertia + Vue (via laravel/vue-starter-kit, incluye paginas de auth con Fortify)
- Reverb: no
- Octane: si (FrankenPHP)
- Dockerfile usado: stubs/Dockerfile (con etapa de build de assets Node)

Comando sugerido al final:

```bash
docker compose -f docker-compose.dev.yml up --build
```

Nota: cuando usas flags, el wizard interactivo se omite para esas opciones y el script aplica esos valores directamente.

## Tabla rapida de flags y efectos

| Flag | Efecto principal | Impacto en stubs/servicios |
| --- | --- | --- |
| (sin flags) | PostgreSQL + Redis + Octane FrankenPHP + Blade | Dockerfile: stubs/Dockerfile, compose dev: stubs/docker-compose.dev.yml |
| --mysql | Cambia DB a MySQL | compose dev: stubs/docker-compose.dev.mysql.yml (o .no-redis) |
| --sqlite | Cambia DB a SQLite | .env.example.sqlite y compose dev sqlite |
| --no-redis | Desactiva Redis | CACHE_STORE=database, SESSION_DRIVER=file, QUEUE_CONNECTION=database; sin servicio redis |
| --api | API only | Ejecuta php artisan install:api (Sanctum); elimina Blade/Vite y omite routes/web.php |
| --inertia-vue | Frontend Inertia + Vue | Proyecto base = laravel/vue-starter-kit (Fortify + Inertia); Dockerfile incluye build de assets con Node |
| --inertia-react | Frontend Inertia + React | Proyecto base = laravel/react-starter-kit (Fortify + Inertia); Dockerfile incluye build de assets con Node |
| --reverb | Habilita WebSockets Reverb | genera docker-compose.reverb.yml y agrega servicio reverb al levantar con -f extra |
| --no-octane | Sin Octane | Dockerfile: stubs/Dockerfile.plain, comando app: php artisan serve |
| --swoole | Octane con Swoole | Dockerfile: stubs/Dockerfile.swoole, comando app: octane:start --server=swoole |

Precedencia importante:

- --swoole implica Octane activo.
- --no-octane ignora el uso de servidor Octane (FrankenPHP/Swoole) y selecciona Dockerfile.plain.
- --api es incompatible con --inertia-vue/--inertia-react; combinarlos aborta el instalador con un mensaje de error.
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

## Mantenimiento de versiones

Los paquetes de Composer (Laravel, Octane, Reverb, Larastan, Resend, Sentry) se instalan siempre sin version fijada, por lo que ya resuelven a la ultima version estable disponible. Los starter kits de Inertia (laravel/vue-starter-kit, laravel/react-starter-kit) se instalan con `--stability=dev` porque su rama estable aun no soporta Laravel 13; revisa periodicamente si ya hay tag estable compatible para quitar ese flag.

Las imagenes base de Docker si quedan fijadas a una version concreta (por estabilidad: un mayor de base de datos no debe cambiar solo sin que el desarrollador lo note). Version actual de cada pin:

- php:8.4-cli (stubs/Dockerfile.plain, stubs/Dockerfile.swoole)
- composer:2 (todas las variantes de Dockerfile, flotando en la mayor 2.x)
- dunglas/frankenphp (stubs/Dockerfile, sin tag, siempre latest)
- postgres:18-alpine
- mysql:8.4
- redis:8-alpine

Revisa estos pines cada pocos meses (o cuando notes que Docker Hub ya tiene una version mayor mas reciente) y actualizalos manualmente en los stubs correspondientes. No hay CI ni bots de actualizacion automatica en este repo; si en el futuro se quiere automatizar, Dependabot con el ecosistema Docker es la opcion estandar de bajo mantenimiento.

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

- El instalador muestra `⚠ <archivo> falló — continuando sin esta herramienta` para un Dockerfile, docker-compose u otro stub, y lo lista en el resumen final

Nota: desde que el manejo de fallos es por herramienta, esto ya no aborta el instalador completo; el proyecto se termina de generar igual, pero el archivo afectado puede faltar o quedar vacio.

Solucion:

- Verifica conexion a internet
- Revisa que GITHUB_USER, GITHUB_REPO y BRANCH en install.sh apunten a rutas validas
- Prueba manualmente la URL raw del stub en navegador o con curl
- Vuelve a descargar el archivo a mano (`curl -fsSL <BASE_URL>/<stub> -o <archivo>`) o re-ejecuta el instalador

## Documentacion adicional

- docs/frankenphp-migration-guide.md
- docs/concurrency.md
- docs/events-and-jobs.md

## Licencia

MIT.
