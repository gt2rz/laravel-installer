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
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }

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

# --- Helper de stubs (definido temprano: varios bloques opcionales lo usan) ---
download_stub() {
  local STUB="$1" OUTPUT="${2:-$1}"
  mkdir -p "$(dirname "$OUTPUT")"
  # pipefail en subshell propio: sin esto, un curl fallido queda enmascarado
  # por el éxito de los sed posteriores y el fallo nunca se detecta.
  (
    set -o pipefail
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
  )
}

# Descarga un stub y solo imprime el ok si tuvo éxito (usado vía run_optional).
fetch_stub() {
  local label="$1" stub="$2" output="${3:-$2}"
  download_stub "$stub" "$output"
  ok "$label"
}

# --- Manejo de fallos para pasos opcionales ---
# Cada herramienta adicional (Octane, Reverb, Resend, Sentry, stubs, etc.) se
# instala de forma aislada: si una falla, se avisa y el resto del proceso
# continúa en lugar de abortar todo lo ya instalado.
FAILED_TOOLS=()

run_optional() {
  local label="$1"; shift
  set +e
  ( set -e; "$@" )
  local status=$?
  set -e
  if [ $status -ne 0 ]; then
    warn "$label falló — continuando sin esta herramienta."
    FAILED_TOOLS+=("$label")
  fi
  # Siempre devuelve 0: si el llamador usa el resultado en un && / || / if,
  # bash propaga esa condición hacia dentro del subshell de arriba y anula
  # su "set -e" interno, dejando que una herramienta fallida siga ejecutando
  # sus pasos siguientes. Aislar el estado por completo evita ese efecto.
  return 0
}

# --- Helpers de etiquetas ---
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

frontend_label() {
  case "$FRONTEND_STACK" in
    inertia-vue)   echo "Inertia + Vue" ;;
    inertia-react) echo "Inertia + React" ;;
    *)             echo "Blade" ;;
  esac
}

usage() {
  echo ""
  echo -e "${BOLD}Uso:${NC}"
  echo "  bash -s [nombre-proyecto] [opciones]"
  echo ""
  echo -e "${BOLD}Opciones (omiten las preguntas interactivas):${NC}"
  echo "  --mysql          MySQL en lugar de PostgreSQL"
  echo "  --sqlite         SQLite en lugar de PostgreSQL"
  echo "  --no-redis       Sin Redis (drivers: file/database)"
  echo "  --api            Solo API (Sanctum, sin Blade ni Vite)"
  echo "  --inertia-vue    Frontend con Inertia + Vue (starter kit oficial, incluye auth con Fortify)"
  echo "  --inertia-react  Frontend con Inertia + React (starter kit oficial, incluye auth con Fortify)"
  echo "  --reverb         Instalar Laravel Reverb (WebSockets)"
  echo "  --no-octane      Laravel sin Octane (PHP-CLI estándar)"
  echo "  --swoole         Octane con Swoole en lugar de FrankenPHP"
  echo "  --resend         Instalar Resend como proveedor de email"
  echo "  --sentry         Instalar Sentry para monitoreo de errores"
  echo "  --help           Mostrar esta ayuda"
  echo ""
  echo -e "${BOLD}Nota:${NC} --api es incompatible con --inertia-vue/--inertia-react (API only no usa Blade/Vite)."
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
FRONTEND_STACK="blade"
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
FRONTEND_FLAG=false

# --- Parse args ---
for arg in "$@"; do
  case $arg in
    --mysql)         USE_DB="mysql";        DB_FLAG=true ;;
    --sqlite)        USE_DB="sqlite";       DB_FLAG=true ;;
    --no-redis)      USE_REDIS=false;       REDIS_FLAG=true ;;
    --api)           API_ONLY=true;         API_FLAG=true ;;
    --inertia-vue)   FRONTEND_STACK="inertia-vue";   FRONTEND_FLAG=true ;;
    --inertia-react) FRONTEND_STACK="inertia-react"; FRONTEND_FLAG=true ;;
    --reverb)        USE_REVERB=true;       REVERB_FLAG=true ;;
    --no-octane)     USE_OCTANE=false;      OCTANE_FLAG=true ;;
    --swoole)        USE_OCTANE=true; USE_FRANKENPHP=false; OCTANE_FLAG=true; FRANKENPHP_FLAG=true ;;
    --resend)        USE_RESEND=true;  RESEND_FLAG=true ;;
    --sentry)        USE_SENTRY=true;  SENTRY_FLAG=true ;;
    --help|-h)   usage ;;
    -*)          fail "Opción desconocida: $arg. Usa --help para ver las opciones." ;;
    *)           [ -z "$PROJECT_NAME" ] && PROJECT_NAME="$arg" ;;
  esac
done

if [ "$API_ONLY" = true ] && [ "$FRONTEND_STACK" != "blade" ]; then
  fail "--api y --inertia-vue/--inertia-react son incompatibles (API only no usa Blade/Vite)."
fi

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

if [ "$FRONTEND_FLAG" = false ] && [ "$API_ONLY" = false ]; then
  choice=$(ask_choice "Frontend:" "Blade" "Inertia + Vue" "Inertia + React")
  case $choice in
    2) FRONTEND_STACK="inertia-vue" ;;
    3) FRONTEND_STACK="inertia-react" ;;
    *) FRONTEND_STACK="blade" ;;
  esac
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
printf "  %-18s %s\n" "Frontend:"      "$(frontend_label)"
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

# --- Cleanup en error (solo durante el bootstrap irreversible) ---
trap 'echo -e "\n  ${RED}✘ Error — limpiando $PROJECT_NAME...${NC}"; cd .. 2>/dev/null; rm -rf "$PROJECT_NAME" 2>/dev/null' ERR

# --- Dependencias ---
command -v composer &>/dev/null || fail "composer no está instalado."
command -v curl     &>/dev/null || fail "curl no está instalado."
command -v git      &>/dev/null || fail "git no está instalado."
command -v docker   &>/dev/null || warn "docker no encontrado — los archivos se crearán igualmente."

# --- Laravel ---
# Desde Laravel 13 el frontend Inertia ya no se monta con Breeze sobre el
# skeleton base: los starter kits oficiales (Fortify + Inertia + Vue/React)
# son el propio proyecto raíz, igual que laravel/laravel.
case "$FRONTEND_STACK" in
  inertia-vue)   BASE_PACKAGE="laravel/vue-starter-kit";   STABILITY_FLAG="--stability=dev" ;;
  inertia-react) BASE_PACKAGE="laravel/react-starter-kit"; STABILITY_FLAG="--stability=dev" ;;
  *)             BASE_PACKAGE="laravel/laravel";           STABILITY_FLAG="" ;;
esac

info "Creando proyecto Laravel..."
composer create-project "$BASE_PACKAGE" "$PROJECT_NAME" $STABILITY_FLAG --quiet
cd "$PROJECT_NAME"
ok "Proyecto creado"

# A partir de aquí ya existe un proyecto Laravel válido en disco: un fallo en
# una herramienta opcional no debe borrarlo, solo se avisa y se continúa.
trap - ERR

# --- Octane ---
install_octane() {
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
}
if [ "$USE_OCTANE" = true ]; then
  run_optional "Octane" install_octane
fi

# --- API only ---
configure_api_only() {
  info "Configurando proyecto como API..."
  php artisan install:api --no-interaction --quiet
  download_stub "routes/api.php" "routes/api.php"
  printf '<?php\n' > routes/web.php
  rm -f resources/views/welcome.blade.php vite.config.js package.json package-lock.json
  rm -rf resources/js resources/css
  ok "Sanctum instalado, proyecto configurado como solo-API (sin Blade ni Vite)"
}
if [ "$API_ONLY" = true ]; then
  run_optional "API only" configure_api_only
fi

# --- Reverb ---
install_reverb() {
  info "Instalando Laravel Reverb..."
  composer require laravel/reverb --quiet
  php artisan reverb:install --no-interaction
  ok "Reverb instalado"
}
if [ "$USE_REVERB" = true ]; then
  run_optional "Reverb" install_reverb
fi

# --- Pint & Larastan ---
install_quality_tools() {
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
}
run_optional "Larastan" install_quality_tools

# --- Resend ---
install_resend() {
  info "Instalando Resend..."
  composer require resend/resend-laravel --quiet
  ok "Resend instalado"
}
if [ "$USE_RESEND" = true ]; then
  run_optional "Resend" install_resend
fi

# --- Sentry ---
install_sentry() {
  info "Instalando Sentry..."
  composer require sentry/sentry-laravel --quiet
  ok "Sentry instalado"
}
if [ "$USE_SENTRY" = true ]; then
  run_optional "Sentry" install_sentry
fi

# --- Dockerfile: omite la etapa de build de assets en proyectos --api ---
prune_dockerfile_assets() {
  sed -i.bak '/# --- assets:start/,/# --- assets:end/d' Dockerfile
  sed -i.bak '/COPY --from=assets/d' Dockerfile
  rm -f Dockerfile.bak
  ok "Dockerfile sin build de assets (API only)"
}

info "Descargando archivos de infraestructura..."
run_optional "Dockerfile" fetch_stub "Dockerfile" "$DOCKERFILE_STUB" "Dockerfile"

if [ "$API_ONLY" = true ]; then
  run_optional "Dockerfile sin build de assets (API only)" prune_dockerfile_assets
fi

run_optional "docker-compose.yml" fetch_stub "docker-compose.yml" "docker-compose.yml"

run_optional "docker-compose.dev.yml" fetch_stub "docker-compose.dev.yml" "$DEV_COMPOSE_STUB" "docker-compose.dev.yml"

if [ "$USE_REVERB" = true ]; then
  run_optional "docker-compose.reverb.yml" fetch_stub "docker-compose.reverb.yml" "docker-compose.reverb.yml"
fi

run_optional "docker/php/api-optimizations.ini" fetch_stub "docker/php/api-optimizations.ini" "docker/php/api-optimizations.ini"

run_optional ".env.example" fetch_stub ".env.example" "$ENV_STUB" ".env.example"

run_optional "Makefile" fetch_stub "Makefile" "Makefile"

if [ "$API_ONLY" = false ] && [ "$FRONTEND_STACK" = "blade" ]; then
  run_optional "routes/web.php" fetch_stub "routes/web.php" "routes/web.php" "routes/web.php"
fi

run_optional "GenerateBrunoCollection" fetch_stub "GenerateBrunoCollection" "app/Console/Commands/GenerateBrunoCollection.php" "app/Console/Commands/GenerateBrunoCollection.php"

# --- .env (paso crítico: sin esto el proyecto no arranca) ---
[ -f .env.example ] || fail "No se pudo descargar .env.example — revisa manualmente el proyecto en $PROJECT_NAME."
cp .env.example .env
php artisan key:generate --quiet || fail "No se pudo generar APP_KEY — revisa .env manualmente en $PROJECT_NAME."
ok ".env generado"

generate_bruno() {
  info "Generando colección Bruno..."
  php artisan bruno:generate --force --no-interaction --quiet
  ok "Colección Bruno generada en docs/bruno"
}
run_optional "Colección Bruno" generate_bruno

configure_resend_env() {
  sed -i.bak 's/^MAIL_MAILER=.*/MAIL_MAILER=resend/' .env && rm -f .env.bak
  sed -i.bak 's/^MAIL_MAILER=.*/MAIL_MAILER=resend/' .env.example && rm -f .env.example.bak
  printf "\n# Resend\nRESEND_API_KEY=\n" >> .env
  printf "\n# Resend\nRESEND_API_KEY=\n" >> .env.example
  ok "Resend configurado en .env"
}
if [ "$USE_RESEND" = true ]; then
  run_optional "Resend (.env)" configure_resend_env
fi

configure_sentry_env() {
  printf "\n# Sentry\nSENTRY_LARAVEL_DSN=\n" >> .env
  printf "\n# Sentry\nSENTRY_LARAVEL_DSN=\n" >> .env.example
  ok "Sentry configurado en .env"
}
if [ "$USE_SENTRY" = true ]; then
  run_optional "Sentry (.env)" configure_sentry_env
fi

# --- Git ---
info "Inicializando repositorio..."
git init --quiet

install_git_hooks() {
  info "Instalando Git hooks..."
  download_stub ".githooks/pre-commit"
  chmod +x .githooks/pre-commit
  git config core.hooksPath .githooks
  ok "Git hooks instalados en .githooks (core.hooksPath)"
}
run_optional "Git hooks" install_git_hooks

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

# --- Resumen de fallos (si los hubo) ---
if [ ${#FAILED_TOOLS[@]} -gt 0 ]; then
  echo ""
  echo -e "  ${YELLOW}⚠ Algunas herramientas opcionales no se instalaron:${NC}"
  for t in "${FAILED_TOOLS[@]}"; do
    echo "    - $t"
  done
  echo "  El resto del proyecto está listo; puedes instalarlas manualmente."
fi

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
