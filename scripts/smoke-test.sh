#!/bin/bash
# Smoke-test end-to-end del instalador.
#
# Sirve el repo local (con cambios sin commitear incluidos, a diferencia de
# correr install.sh normalmente, que siempre baja los stubs desde GitHub) y
# genera proyectos reales para una matriz de combinaciones representativas de
# flags, corriendo lint/analyse/test sobre cada uno.
#
# Pensado para correr antes de pushear cambios a stubs/ o install.sh — varios
# bugs reales (paratest faltante, phpstan.neon pisado en starter kits de
# Inertia, tests rotos en modo --api) solo se detectan generando un proyecto
# de verdad, no leyendo el código.
#
# Uso:
#   scripts/smoke-test.sh                # corre todos los escenarios
#   scripts/smoke-test.sh blade api      # corre solo los escenarios nombrados
#
# Requiere: bash, curl, python3, composer, php, git (los mismos requisitos que
# install.sh). Nunca corre npm — los targets de frontend del Makefile se
# validan solo por presencia/ausencia, no ejecutándolos, ya que Node/npm no
# son requisito de este proyecto.

set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$(mktemp -d)"
PORT=$(( (RANDOM % 5000) + 20000 ))
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
  fi
  rm -rf "$RUN_DIR"
}
trap cleanup EXIT

echo "→ Sirviendo $REPO_ROOT en http://127.0.0.1:$PORT (incluye cambios sin commitear)"
( cd "$REPO_ROOT" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 ) >"$RUN_DIR/http-server.log" 2>&1 &
SERVER_PID=$!

READY=false
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:$PORT/stubs/Makefile" >/dev/null 2>&1; then
    READY=true
    break
  fi
  sleep 0.2
done
if [ "$READY" != true ]; then
  echo "✘ No se pudo levantar el servidor local de stubs (ver $RUN_DIR/http-server.log)"
  exit 1
fi

# Copia de install.sh apuntando al servidor local en vez de GitHub.
LOCAL_INSTALL="$RUN_DIR/install.local.sh"
sed "s|BASE_URL=\"https://raw.githubusercontent.com/\$GITHUB_USER/\$GITHUB_REPO/\$BRANCH/stubs\"|BASE_URL=\"http://127.0.0.1:$PORT/stubs\"|" \
  "$REPO_ROOT/install.sh" > "$LOCAL_INSTALL"

# --- Matriz de escenarios: nombre|flags ---
SCENARIOS=(
  "blade|--sqlite --no-redis --no-octane"
  "api|--api --sqlite --no-redis --no-octane"
  "inertia-vue|--inertia-vue --sqlite --no-redis --no-octane"
  "inertia-react|--inertia-react --sqlite --no-redis --no-octane"
)

PASSED=()
FAILED=()

run_scenario() {
  local name="$1" flags="$2"
  local project_dir="$RUN_DIR/$name"
  # TMPDIR aislado por escenario: PHPStan cachea su contenedor compilado en el
  # tmpdir del sistema y dos proyectos con phpstan.neon idéntico pueden
  # colisionar ahí si comparten TMPDIR (visto en la práctica al validar esto).
  local scenario_tmp="$RUN_DIR/tmp-$name/"

  echo ""
  echo "══════════════════════════════════════════════════════"
  echo "  Escenario: $name ($flags)"
  echo "══════════════════════════════════════════════════════"

  mkdir -p "$project_dir" "$scenario_tmp"

  ( cd "$project_dir" && bash "$LOCAL_INSTALL" proyecto $flags )
  if [ $? -ne 0 ]; then
    echo "  ✘ install.sh falló"
    FAILED+=("$name (install.sh)")
    return
  fi

  if ! cd "$project_dir/proyecto"; then
    echo "  ✘ no se pudo entrar al proyecto generado"
    FAILED+=("$name (cd)")
    return
  fi

  local ok=true

  echo "  -- composer lint:check --"
  composer lint:check || ok=false

  # Se invoca phpstan directo (no via `composer types:check`) para poder fijar
  # memory_limit=-1: los starter kits de Inertia no pasan --memory-limit en su
  # propio script, y sus workers paralelos heredan el límite del php.ini del
  # host (128M por defecto), insuficiente para el nivel 7 de su phpstan.neon.
  echo "  -- phpstan analyse (types:check) --"
  TMPDIR="$scenario_tmp" php -d memory_limit=-1 vendor/bin/phpstan analyse || ok=false

  echo "  -- php artisan test --parallel (lo que corre 'make test') --"
  php artisan test --parallel || ok=false

  cd "$REPO_ROOT" || exit 1

  if [ "$ok" = true ]; then
    echo "  ✔ $name OK"
    PASSED+=("$name")
  else
    echo "  ✘ $name con fallos (ver arriba)"
    FAILED+=("$name")
  fi
}

WANTED=("$@")
for entry in "${SCENARIOS[@]}"; do
  name="${entry%%|*}"
  flags="${entry#*|}"

  if [ ${#WANTED[@]} -gt 0 ]; then
    match=false
    for want in "${WANTED[@]}"; do
      [ "$want" = "$name" ] && match=true
    done
    [ "$match" = true ] || continue
  fi

  run_scenario "$name" "$flags"
done

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Resumen"
echo "══════════════════════════════════════════════════════"
if [ ${#PASSED[@]} -gt 0 ]; then
  for p in "${PASSED[@]}"; do echo "  ✔ $p"; done
fi
if [ ${#FAILED[@]} -gt 0 ]; then
  for f in "${FAILED[@]}"; do echo "  ✘ $f"; done
  exit 1
fi
exit 0
