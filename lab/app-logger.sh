#!/usr/bin/env bash
# Aplicación simulada del laboratorio 01: escribe un log sin rotación.
# Mantiene el descriptor 3 abierto durante toda su vida, igual que hacen
# muchos servicios reales con su fichero de log.
#
# Variables opcionales:
#   THROTTLE  segundos de pausa entre líneas (por defecto, sin pausa)

PAYLOAD="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
echo "$$" > /tmp/app.pid
exec 3>> /var/log/app/app.log

while true; do
  if ! printf '%(%T)T INFO request id=%s payload=%s\n' -1 "$RANDOM" "$PAYLOAD" >&3 2>/dev/null; then
    printf '%(%T)T ERROR no se puede escribir en /var/log/app/app.log\n' -1 >> /tmp/app.err
    sleep 1
  fi
  [ -n "${THROTTLE:-}" ] && sleep "$THROTTLE"
done
