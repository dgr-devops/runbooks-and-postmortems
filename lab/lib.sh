#!/usr/bin/env bash
# Funciones comunes de los laboratorios. Se carga con `source lab/lib.sh`.
# Cada función imprime la marca de tiempo, el comando ejecutado y su salida
# real, de modo que el fichero resultante sirva como evidencia del ensayo.

ts() { date '+%Y-%m-%d %H:%M:%S'; }

# Nota narrativa (no es un comando).
nota() { printf '\n[%s] ## %s\n' "$(ts)" "$*"; }

# Ejecuta un comando en el host mostrando comando, salida y código de salida.
h() {
  printf '[%s] $ %s\n' "$(ts)" "$*"
  bash -c "$*" 2>&1
  local rc=$?
  [ "$rc" -ne 0 ] && printf '(código de salida: %s)\n' "$rc"
  return 0
}

# Ejecuta un comando dentro del contenedor $CTR con bash.
c() {
  printf '[%s] (%s)$ %s\n' "$(ts)" "$CTR" "$*"
  docker exec "$CTR" bash -c "$*" 2>&1
  local rc=$?
  [ "$rc" -ne 0 ] && printf '(código de salida: %s)\n' "$rc"
  return 0
}

# Igual que c(), pero para contenedores basados en Alpine (sin bash).
ca() {
  printf '[%s] (%s)$ %s\n' "$(ts)" "$CTR" "$*"
  docker exec "$CTR" sh -c "$*" 2>&1
  local rc=$?
  [ "$rc" -ne 0 ] && printf '(código de salida: %s)\n' "$rc"
  return 0
}

# Elimina contenedores del laboratorio si existen (idempotente).
limpiar() { docker rm -f "$@" >/dev/null 2>&1 || true; }
