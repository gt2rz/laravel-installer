FROM dunglas/frankenphp AS base

ADD --chmod=0755 https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/

RUN apt-get update && apt-get install -y --no-install-recommends \
  git \
  openssh-client \
  unzip \
  && rm -rf /var/lib/apt/lists/* \
  && install-php-extensions gd pdo_pgsql zip intl pcntl opcache redis

COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer

WORKDIR /app

# --- Stage de Desarrollo / Construcción ---
FROM base AS builder
COPY composer.json composer.lock ./
RUN composer install --no-interaction --optimize-autoloader --no-dev --no-scripts
COPY . .
RUN composer dump-autoload --optimize --no-dev

# --- Stage de Producción ---
FROM base AS production
COPY --from=builder /app /app

# Copiar configuración de producción de PHP
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
COPY docker/php/api-optimizations.ini $PHP_INI_DIR/conf.d/

# Configurar variables de entorno de FrankenPHP para Octane
ENV PORT=8000

# Exponer el puerto interno que usará Dokploy
EXPOSE 8000

ENTRYPOINT ["php", "artisan", "octane:start", "--server=frankenphp", "--host=0.0.0.0", "--port=8000"]
