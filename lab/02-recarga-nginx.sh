#!/usr/bin/env bash
# Laboratorio 02 — Recarga de nginx con configuración inválida y reinicio posterior.
# Contenedor nginx:1.27-alpine con la configuración montada desde un directorio
# temporal del host. Salida: stdout (redirigir a fichero).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"
CTR=lab-nginx
WORK="$(mktemp -d)"
CONF="$WORK/conf.d"
mkdir -p "$CONF"
trap 'rm -rf "$WORK"' EXIT

buena() {
  cat > "$CONF/default.conf" <<'EOF'
server {
    listen 80;
    location / {
        return 200 "ok v1\n";
    }
}
EOF
}

mala() {
  cat > "$CONF/default.conf" <<'EOF'
server {
    listen 80;
    location / {
        return 200 "ok v2\n";
    }
    location /api/ {
        proxy_pass http://app-backend:8080;
    }
}
EOF
}

nota "Preparación: contenedor nginx con configuración válida (v1)"
limpiar "$CTR"
buena
h "docker run -d --name $CTR -v $CONF:/etc/nginx/conf.d:ro nginx:1.27-alpine | cut -c1-12"
sleep 2
ca 'nginx -t'
ca 'wget -qO- http://127.0.0.1/'

nota "T0: alguien añade un bloque /api/ que apunta a un host inexistente (app-backend) y guarda el fichero"
mala
h "cat $CONF/default.conf"

nota "T1: recarga SIN validar antes (nginx -s reload)"
ca 'nginx -s reload; echo "rc de nginx -s reload = $?"'
sleep 1
h "docker logs --tail 4 $CTR"

nota "T2: el servicio sigue respondiendo con la configuración ANTIGUA (fallo latente)"
h "docker ps --filter name=$CTR --format 'table {{.Names}}\t{{.Status}}'"
ca 'wget -qO- http://127.0.0.1/'
ca 'nginx -t'

nota "T3: un reinicio posterior (mantenimiento, actualización, reinicio del host) aplica la configuración rota"
h "docker restart $CTR"
sleep 2
h "docker ps -a --filter name=$CTR --format 'table {{.Names}}\t{{.Status}}'"
h "docker inspect $CTR --format 'ExitCode={{.State.ExitCode}} Running={{.State.Running}}'"
h "docker logs --tail 5 $CTR"
ca 'wget -qO- -T 3 http://127.0.0.1/'

nota "T4: diagnóstico sin tocar nada: validar la configuración con un contenedor desechable"
h "docker run --rm -v $CONF:/etc/nginx/conf.d:ro nginx:1.27-alpine nginx -t"

nota "T5: resolución: restaurar la última configuración buena y validar antes de arrancar"
buena
h "docker run --rm -v $CONF:/etc/nginx/conf.d:ro nginx:1.27-alpine nginx -t"
h "docker start $CTR"
sleep 2
ca 'wget -qO- http://127.0.0.1/'
h "docker ps --filter name=$CTR --format 'table {{.Names}}\t{{.Status}}'"

nota "Prevención: validar y recargar solo si la validación pasa"
mala
ca 'nginx -t && nginx -s reload; echo "rc = $?"'
ca 'wget -qO- http://127.0.0.1/'
buena
ca 'nginx -t && nginx -s reload; echo "rc = $?"'

nota "Limpieza"
limpiar "$CTR"
echo "contenedor $CTR eliminado"
