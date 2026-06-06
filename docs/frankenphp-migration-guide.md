# Llevar FrankenPHP + Octane a otro proyecto Laravel

## Opción A: Proyecto nuevo desde cero

```bash
laravel new mi-proyecto
cd mi-proyecto
composer require laravel/octane
php artisan octane:install --server=frankenphp
```

Luego copia los archivos de infraestructura de este proyecto.

## Opción B: Proyecto Laravel existente

```bash
composer require laravel/octane
php artisan octane:install --server=frankenphp
```

## Archivos que debes copiar

### Obligatorios

| Archivo | Por qué |
|---|---|
| `Dockerfile` | Imagen multi-stage con `dunglas/frankenphp`, extensiones PHP y entrypoint de Octane |
| `docker-compose.yml` | Stack de producción (red Dokploy, volumen de storage) |
| `docker-compose.dev.yml` | Stack local con PostgreSQL, Redis y `--watch` |
| `docker/php/api-optimizations.ini` | OPcache tuneado para producción sin validación de timestamps |
| `public/frankenphp-worker.php` | Worker entry point requerido por Octane en modo worker |
| `config/octane.php` | Configuración del servidor — verifica que `server = 'frankenphp'` |

### Opcionales pero recomendados

| Archivo | Por qué |
|---|---|
| `.env.example` | Variables con `OCTANE_SERVER=frankenphp`, `DB_CONNECTION=pgsql`, `REDIS_*` |

## Ajustes manuales en el proyecto destino

### Cambiar el nombre de la imagen en `docker-compose.yml`

```yaml
image: mi-nuevo-proyecto:latest
```

### Si no usas PostgreSQL, cambiar la extensión en el `Dockerfile`

```dockerfile
RUN install-php-extensions gd pdo_mysql zip intl pcntl opcache redis
```

### Actualizar las variables de entorno

```env
OCTANE_SERVER=frankenphp
DB_CONNECTION=pgsql
REDIS_HOST=redis
CACHE_STORE=redis
SESSION_DRIVER=redis
QUEUE_CONNECTION=redis
```

## Verificación

```bash
# Desarrollo (con hot-reload)
docker compose -f docker-compose.dev.yml up --build

# Producción
docker compose up --build
```

El worker arranca en `http://localhost:8000`.
