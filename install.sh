#!/bin/bash
set -e

# --- Config ---
GITHUB_USER="gt2rz"
GITHUB_REPO="test-frankenphp-octane"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$BRANCH/stubs"

STUBS=(
  "Dockerfile"
  "docker-compose.yml"
  "docker-compose.dev.yml"
  "docker/php/api-optimizations.ini"
  ".env.example"
)

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✔${NC} $1"; }
info() { echo -e "${YELLOW}→${NC} $1"; }
fail() { echo -e "${RED}✘ $1${NC}"; exit 1; }

# --- Args ---
PROJECT_NAME="${1:-}"
if [ -z "$PROJECT_NAME" ]; then
  read -rp "Nombre del proyecto: " PROJECT_NAME
fi

[ -z "$PROJECT_NAME" ] && fail "Debes indicar un nombre de proyecto."

# --- Dependencies ---
command -v composer &>/dev/null || fail "composer no está instalado."
command -v curl    &>/dev/null || fail "curl no está instalado."

# --- Laravel ---
info "Creando proyecto Laravel: $PROJECT_NAME"
composer create-project laravel/laravel "$PROJECT_NAME" --quiet
cd "$PROJECT_NAME"
ok "Proyecto Laravel creado"

# --- Octane ---
info "Instalando Laravel Octane con FrankenPHP"
composer require laravel/octane --quiet
php artisan octane:install --server=frankenphp --no-interaction
ok "Octane instalado"

# --- Stubs ---
info "Descargando archivos de infraestructura"
for STUB in "${STUBS[@]}"; do
  mkdir -p "$(dirname "$STUB")"
  curl -fsSL "$BASE_URL/$STUB" \
    | sed "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" \
    > "$STUB"
  ok "$STUB"
done

# --- .env ---
cp .env.example .env
php artisan key:generate --quiet
ok ".env generado"

echo ""
echo -e "${GREEN}Proyecto listo: $PROJECT_NAME${NC}"
echo ""
echo "Próximos pasos:"
echo "  cd $PROJECT_NAME"
echo "  docker compose -f docker-compose.dev.yml up --build"
