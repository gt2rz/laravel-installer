#!/bin/bash
set -e

# --- Config ---
GITHUB_USER="gt2rz"
GITHUB_REPO="laravel-installer"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$BRANCH/stubs"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✔${NC} $1"; }
info() { echo -e "  ${YELLOW}→${NC} $1"; }
fail() { echo -e "  ${RED}✘ $1${NC}"; exit 1; }

# --- Interactive helpers (funcionan incluso piped desde curl) ---

# prompt: pregunta a usuario con opción de valor por defecto
ask_input() {
  local prompt="$1" default="$2" answer
  if [ -n "$default" ]; then
    printf "  %s [%s]: " "$prompt" "$default" >/dev/tty
  else
    printf "  %s: " "$prompt" >/dev/tty
  fi
  read -r answer </dev/tty
  echo "${answer:-$default}"
}

# prompt: pregunta sí/no con opción por defecto (default: y)
ask_yn() {
  local prompt="$1" default="${2:-y}" hint answer
  [ "$default" = "y" ] && hint="Y/n" || hint="y/N"
  printf "  %s [%s]: " "$prompt" "$hint" >/dev/tty
  read -r answer </dev/tty
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy] ]]
}

# prompt: pregunta al usuario con opciones numeradas, devuelve la opción elegida (default: 1)
ask_choice() {
  local prompt="$1" choice
  shift
  local options=("$@")
  echo -e "  ${CYAN}$prompt${NC}" >/dev/tty
  for i in "${!options[@]}"; do
    printf "    ${DIM}%d)${NC} %s\n" "$((i+1))" "${options[$i]}" >/dev/tty
  done
  printf "  Selección [1]: " >/dev/tty
  read -r choice </dev/tty
  echo "${choice:-1}"
}

# --- Helpers ---
db_label() {
  case "$USE_DB" in
    mysql)  echo "MySQL" ;;
    sqlite) echo "SQLite" ;;
    *)      echo "PostgreSQL" ;;
  esac
}

octane_label() {
  if [ "$USE_OCTANE" = false ]; then
    echo "no"
  elif [ "$USE_FRANKENPHP" = true ]; then
    echo "sí (FrankenPHP)"
  else
    echo "sí (Swoole)"
  fi
}

usage() {
  echo ""
  echo -e "${BOLD}Uso:${NC}"
  echo "  bash -s [nombre-proyecto] [opciones]"
  echo ""
  echo -e "${BOLD}Opciones (omiten las preguntas interactivas):${NC}"
  echo "  --mysql       MySQL en lugar de PostgreSQL"
  echo "  --sqlite      SQLite en lugar de PostgreSQL"
  echo "  --no-redis    Sin Redis (drivers: file/database)"
  echo "  --api         Solo API (Sanctum, sin Blade ni Vite)"
  echo "  --reverb      Instalar Laravel Reverb (WebSockets)"
  echo "  --no-octane   Laravel sin Octane (PHP-CLI estándar)"
  echo "  --swoole      Octane con Swoole en lugar de FrankenPHP"
  echo "  --resend      Instalar Resend como proveedor de email"
  echo "  --sentry      Instalar Sentry para monitoreo de errores"
  echo "  --help        Mostrar esta ayuda"
  echo ""
  echo -e "${BOLD}Ejemplo:${NC}"
  echo "  curl -fsSL https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$BRANCH/install.sh \\"
  echo "    | bash -s mi-api -- --mysql --api --no-octane"
  echo ""
  exit 0
}

# --- Defaults ---
USE_DB="pgsql"
USE_REDIS=true
API_ONLY=false
USE_REVERB=false
USE_OCTANE=true
USE_FRANKENPHP=true
USE_RESEND=false
USE_SENTRY=false
PROJECT_NAME=""
GIT_USER_NAME=""
GIT_USER_EMAIL=""

DB_FLAG=false
REDIS_FLAG=false
API_FLAG=false
REVERB_FLAG=false
OCTANE_FLAG=false
FRANKENPHP_FLAG=false
RESEND_FLAG=false
SENTRY_FLAG=false

GIST_HOOK_URL="https://gist.githubusercontent.com/gt2rz/39499fe47b687c4f2d5df06a5d2eaab8/raw/06cb67fe3d0a9fc3124ce71f4c57028f261c87db/gistfile1.txt"

# --- Parse args ---
for arg in "$@"; do
  case $arg in
    --mysql)     USE_DB="mysql";        DB_FLAG=true ;;
    --sqlite)    USE_DB="sqlite";       DB_FLAG=true ;;
    --no-redis)  USE_REDIS=false;       REDIS_FLAG=true ;;
    --api)       API_ONLY=true;         API_FLAG=true ;;
    --reverb)    USE_REVERB=true;       REVERB_FLAG=true ;;
    --no-octane) USE_OCTANE=false;      OCTANE_FLAG=true ;;
    --swoole)    USE_OCTANE=true; USE_FRANKENPHP=false; OCTANE_FLAG=true; FRANKENPHP_FLAG=true ;;
    --resend)    USE_RESEND=true;  RESEND_FLAG=true ;;
    --sentry)    USE_SENTRY=true;  SENTRY_FLAG=true ;;
    --help|-h)   usage ;;
    -*)          fail "Opción desconocida: $arg. Usa --help para ver las opciones." ;;
    *)           [ -z "$PROJECT_NAME" ] && PROJECT_NAME="$arg" ;;
  esac
done

# --- Header ---
echo ""
echo -e "${BOLD}  Laravel Installer${NC}"
echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# --- Nombre del proyecto ---
if [ -z "$PROJECT_NAME" ]; then
  PROJECT_NAME=$(ask_input "Nombre del proyecto")
fi
[ -z "$PROJECT_NAME" ] && fail "Debes indicar un nombre de proyecto."

[[ "$PROJECT_NAME" =~ ^[a-z0-9_-]+$ ]] \
  || fail "Nombre inválido. Solo minúsculas, números, guiones y underscores."
[ -d "$PROJECT_NAME" ] \
  && fail "Ya existe un directorio '$PROJECT_NAME'."

echo ""

# --- Wizard (solo para opciones no especificadas por flag) ---
if [ "$DB_FLAG" = false ]; then
  choice=$(ask_choice "Base de datos:" "PostgreSQL" "MySQL" "SQLite")
  case $choice in
    2) USE_DB="mysql" ;;
    3) USE_DB="sqlite" ;;
    *) USE_DB="pgsql" ;;
  esac
fi

echo ""

if [ "$REDIS_FLAG" = false ]; then
  if [ "$USE_DB" = "sqlite" ]; then
    ask_yn "¿Usar Redis?" "n" && USE_REDIS=true || USE_REDIS=false
  else
    ask_yn "¿Usar Redis? (cache, sesiones, colas)" "y" && USE_REDIS=true || USE_REDIS=false
  fi
fi

echo ""

if [ "$API_FLAG" = false ]; then
  ask_yn "¿Solo API? (Sanctum, sin Blade ni Vite)" "n" && API_ONLY=true || API_ONLY=false
fi

echo ""

if [ "$REVERB_FLAG" = false ]; then
  ask_yn "¿Instalar Laravel Reverb? (WebSockets)" "n" && USE_REVERB=true || USE_REVERB=false
fi

echo ""

if [ "$OCTANE_FLAG" = false ]; then
  ask_yn "¿Usar Laravel Octane? (workers persistentes, alto rendimiento)" "y" && USE_OCTANE=true || USE_OCTANE=false
fi

echo ""

if [ "$USE_OCTANE" = true ] && [ "$FRANKENPHP_FLAG" = false ]; then
  ask_yn "¿Usar FrankenPHP como servidor de Octane?" "y" && USE_FRANKENPHP=true || USE_FRANKENPHP=false
fi

echo ""

if [ "$RESEND_FLAG" = false ]; then
  ask_yn "¿Usar Resend como proveedor de email?" "n" && USE_RESEND=true || USE_RESEND=false
fi

echo ""

if [ "$SENTRY_FLAG" = false ]; then
  ask_yn "¿Usar Sentry para monitoreo de errores?" "n" && USE_SENTRY=true || USE_SENTRY=false
fi

echo ""

DEFAULT_GIT_NAME=$(git config --global user.name 2>/dev/null || echo "")
DEFAULT_GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")
GIT_USER_NAME=$(ask_input "Tu nombre (git config)" "$DEFAULT_GIT_NAME")
echo ""
GIT_USER_EMAIL=$(ask_input "Tu email (git config)" "$DEFAULT_GIT_EMAIL")

# --- Resolver config: DB ---
case "$USE_DB" in
  mysql)
    DB_EXTENSION="pdo_mysql"
    DB_CONNECTION="mysql"
    DB_HOST="mysql"
    DB_PORT="3306"
    ENV_STUB=".env.example"
    ;;
  sqlite)
    DB_EXTENSION="pdo_sqlite"
    DB_CONNECTION="sqlite"
    DB_HOST=""
    DB_PORT=""
    ENV_STUB=".env.example.sqlite"
    ;;
  *)
    DB_EXTENSION="pdo_pgsql"
    DB_CONNECTION="pgsql"
    DB_HOST="postgres"
    DB_PORT="5432"
    ENV_STUB=".env.example"
    ;;
esac

# --- Resolver config: Redis ---
if [ "$USE_REDIS" = true ]; then
  CACHE_STORE="redis"
  SESSION_DRIVER="redis"
  QUEUE_CONNECTION="redis"
else
  CACHE_STORE="database"
  SESSION_DRIVER="file"
  QUEUE_CONNECTION="database"
fi

# --- Resolver config: Octane / servidor ---
if [ "$USE_OCTANE" = false ]; then
  OCTANE_SERVER=""
  APP_DEV_CMD="php artisan serve --host=0.0.0.0 --port=8000"
  DOCKERFILE_STUB="Dockerfile.plain"
elif [ "$USE_FRANKENPHP" = true ]; then
  OCTANE_SERVER="frankenphp"
  APP_DEV_CMD="php artisan octane:start --server=frankenphp --host=0.0.0.0 --port=8000 --watch"
  DOCKERFILE_STUB="Dockerfile"
else
  OCTANE_SERVER="swoole"
  APP_DEV_CMD="php artisan octane:start --server=swoole --host=0.0.0.0 --port=8000 --watch"
  DOCKERFILE_STUB="Dockerfile.swoole"
fi

# --- Resolver config: docker-compose dev stub ---
if [ "$USE_DB" = "sqlite" ] && [ "$USE_REDIS" = true ]; then
  DEV_COMPOSE_STUB="docker-compose.dev.sqlite.redis.yml"
elif [ "$USE_DB" = "sqlite" ]; then
  DEV_COMPOSE_STUB="docker-compose.dev.sqlite.yml"
elif [ "$USE_DB" = "mysql" ] && [ "$USE_REDIS" = false ]; then
  DEV_COMPOSE_STUB="docker-compose.dev.mysql.no-redis.yml"
elif [ "$USE_DB" = "mysql" ]; then
  DEV_COMPOSE_STUB="docker-compose.dev.mysql.yml"
elif [ "$USE_REDIS" = false ]; then
  DEV_COMPOSE_STUB="docker-compose.dev.no-redis.yml"
else
  DEV_COMPOSE_STUB="docker-compose.dev.yml"
fi

# --- Resumen + confirmación ---
echo ""
echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
printf "  %-18s %s\n" "Proyecto:"      "$PROJECT_NAME"
printf "  %-18s %s\n" "Base de datos:" "$(db_label)"
printf "  %-18s %s\n" "Redis:"         "$([ "$USE_REDIS"  = true ] && echo "sí" || echo "no")"
printf "  %-18s %s\n" "Solo API:"      "$([ "$API_ONLY"   = true ] && echo "sí" || echo "no")"
printf "  %-18s %s\n" "Reverb:"        "$([ "$USE_REVERB" = true ] && echo "sí" || echo "no")"
printf "  %-18s %s\n" "Octane:"        "$(octane_label)"
printf "  %-18s %s\n" "Resend:"        "$([ "$USE_RESEND" = true ] && echo "sí" || echo "no")"
printf "  %-18s %s\n" "Sentry:"        "$([ "$USE_SENTRY" = true ] && echo "sí" || echo "no")"
printf "  %-18s %s\n" "Git nombre:"    "${GIT_USER_NAME:-(sin configurar)}"
printf "  %-18s %s\n" "Git email:"     "${GIT_USER_EMAIL:-(sin configurar)}"
echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

ask_yn "¿Continuar?" "y" || { echo "  Cancelado."; exit 0; }
echo ""

# --- Cleanup en error ---
trap 'echo -e "\n  ${RED}✘ Error — limpiando $PROJECT_NAME...${NC}"; cd .. 2>/dev/null; rm -rf "$PROJECT_NAME" 2>/dev/null' ERR

# --- Dependencias ---
command -v composer &>/dev/null || fail "composer no está instalado."
command -v curl     &>/dev/null || fail "curl no está instalado."
command -v git      &>/dev/null || fail "git no está instalado."
command -v docker   &>/dev/null \
  || echo -e "  ${YELLOW}⚠${NC}  docker no encontrado — los archivos se crearán igualmente."

# --- Laravel ---
info "Creando proyecto Laravel..."
composer create-project laravel/laravel "$PROJECT_NAME" --quiet
cd "$PROJECT_NAME"
ok "Proyecto creado"

# --- Octane ---
if [ "$USE_OCTANE" = true ]; then
  if [ "$USE_FRANKENPHP" = true ]; then
    info "Instalando Laravel Octane con FrankenPHP..."
    composer require laravel/octane --quiet
    php artisan octane:install --server=frankenphp --no-interaction
    ok "Octane + FrankenPHP instalado"
  else
    info "Instalando Laravel Octane con Swoole..."
    composer require laravel/octane --quiet
    php artisan octane:install --server=swoole --no-interaction
    ok "Octane + Swoole instalado"
  fi
fi

# --- API only ---
if [ "$API_ONLY" = true ]; then
  info "Configurando proyecto como API..."
  php artisan install:api --no-interaction --quiet
  download_stub "routes/api.php" "routes/api.php"
  ok "Sanctum instalado, rutas API configuradas"
fi

# --- Reverb ---
if [ "$USE_REVERB" = true ]; then
  info "Instalando Laravel Reverb..."
  composer require laravel/reverb --quiet
  php artisan reverb:install --no-interaction
  ok "Reverb instalado"
fi

# --- Pint & Larastan ---
info "Instalando herramientas de calidad de código (Pint + Larastan)..."
composer require --dev larastan/larastan --quiet
cat > phpstan.neon << 'PHPSTAN'
includes:
    - vendor/larastan/larastan/extension.neon

parameters:
    paths:
        - app/

    level: 5
PHPSTAN
ok "Larastan instalado"

# --- Resend ---
if [ "$USE_RESEND" = true ]; then
  info "Instalando Resend..."
  composer require resend/resend-laravel --quiet
  ok "Resend instalado"
fi

# --- Sentry ---
if [ "$USE_SENTRY" = true ]; then
  info "Instalando Sentry..."
  composer require sentry/sentry-laravel --quiet
  ok "Sentry instalado"
fi

# --- Helper de stubs ---
download_stub() {
  local STUB="$1" OUTPUT="${2:-$1}"
  mkdir -p "$(dirname "$OUTPUT")"
  curl -fsSL "$BASE_URL/$STUB" \
    | sed "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
    | sed "s|{{DB_EXTENSION}}|$DB_EXTENSION|g" \
    | sed "s|{{DB_CONNECTION}}|$DB_CONNECTION|g" \
    | sed "s|{{DB_HOST}}|$DB_HOST|g" \
    | sed "s|{{DB_PORT}}|$DB_PORT|g" \
    | sed "s|{{CACHE_STORE}}|$CACHE_STORE|g" \
    | sed "s|{{SESSION_DRIVER}}|$SESSION_DRIVER|g" \
    | sed "s|{{QUEUE_CONNECTION}}|$QUEUE_CONNECTION|g" \
    | sed "s|{{OCTANE_SERVER}}|$OCTANE_SERVER|g" \
    | sed "s|{{APP_DEV_CMD}}|$APP_DEV_CMD|g" \
    | sed "s|{{GIT_USER_NAME}}|$GIT_USER_NAME|g" \
    | sed "s|{{GIT_USER_EMAIL}}|$GIT_USER_EMAIL|g" \
    > "$OUTPUT"
}

info "Descargando archivos de infraestructura..."
download_stub "$DOCKERFILE_STUB" "Dockerfile"
ok "Dockerfile"

download_stub "docker-compose.yml"
ok "docker-compose.yml"

download_stub "$DEV_COMPOSE_STUB" "docker-compose.dev.yml"
ok "docker-compose.dev.yml"

if [ "$USE_REVERB" = true ]; then
  download_stub "docker-compose.reverb.yml"
  ok "docker-compose.reverb.yml"
fi

download_stub "docker/php/api-optimizations.ini"
ok "docker/php/api-optimizations.ini"

download_stub "$ENV_STUB" ".env.example"
ok ".env.example"

download_stub "Makefile"
ok "Makefile"

download_stub "routes/web.php" "routes/web.php"
ok "routes/web.php"

# --- .env ---
cp .env.example .env
php artisan key:generate --quiet
ok ".env generado"

if [ "$USE_RESEND" = true ]; then
  sed -i.bak 's/^MAIL_MAILER=.*/MAIL_MAILER=resend/' .env && rm -f .env.bak
  sed -i.bak 's/^MAIL_MAILER=.*/MAIL_MAILER=resend/' .env.example && rm -f .env.example.bak
  printf "\n# Resend\nRESEND_API_KEY=\n" >> .env
  printf "\n# Resend\nRESEND_API_KEY=\n" >> .env.example
  ok "Resend configurado en .env"
fi

if [ "$USE_SENTRY" = true ]; then
  printf "\n# Sentry\nSENTRY_LARAVEL_DSN=\n" >> .env
  printf "\n# Sentry\nSENTRY_LARAVEL_DSN=\n" >> .env.example
  ok "Sentry configurado en .env"
fi

# --- Git ---
info "Inicializando repositorio..."
git init --quiet

info "Instalando Git hooks..."
mkdir -p .git/hooks
curl -sS "$GIST_HOOK_URL" -o .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
ok "Git hooks instalados"

git add .

if [ "$USE_OCTANE" = false ]; then
  COMMIT_MSG="chore: initial setup with Laravel"
elif [ "$USE_FRANKENPHP" = true ]; then
  COMMIT_MSG="chore: initial setup with FrankenPHP + Octane"
else
  COMMIT_MSG="chore: initial setup with Octane + Swoole"
fi

git commit --quiet --no-verify -m "$COMMIT_MSG"
ok "Primer commit creado"

# --- Done ---
echo ""
echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}${BOLD}✔ $PROJECT_NAME listo${NC}"
echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  cd $PROJECT_NAME"
if [ "$USE_REVERB" = true ]; then
  echo "  docker compose -f docker-compose.dev.yml -f docker-compose.reverb.yml up --build"
else
  echo "  docker compose -f docker-compose.dev.yml up --build"
fi
echo ""
