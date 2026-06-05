FROM dunglas/frankenphp AS base

# Instalar dependencias del sistema y extensiones de PHP necesarias
RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
  git \
  openssh-client \
  libpng-dev \
  libjpeg62-turbo-dev \
  libfreetype6-dev \
  zip \
  libzip-dev \
  libicu-dev \
  autoconf \
  dpkg-dev \
  file \
  g++ \
  gcc \
  libc-dev \
  make \
  pkg-config \
  re2c \
  && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
  && docker-php-ext-install -j$(nproc) gd pdo_mysql zip intl pcntl opcache \
  && pecl install redis \
  && docker-php-ext-enable redis

# Instalar Composer
COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer

WORKDIR /app

# --- Stage de Desarrollo / Construcción ---
FROM base AS builder
COPY . .
RUN composer install --no-interaction --optimize-autoloader --no-dev

# --- Stage de Producción ---
FROM base AS production
COPY --from=builder /app /app

# Copiar configuración de producción de PHP
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
COPY docker/php/api-optimizations.ini $PHP_INI_DIR/conf.d/

# Configurar variables de entorno de FrankenPHP para Octane
ENV AUTORELOAD=false
ENV FRANKENPHP_CONFIG="worker ./public/frankenphp-worker.php"
ENV PORT=8000

# Exponer el puerto interno que usará Dokploy
EXPOSE 8000

ENTRYPOINT ["php", "artisan", "octane:start", "--server=frankenphp", "--host=0.0.0.0", "--port=8000"]
