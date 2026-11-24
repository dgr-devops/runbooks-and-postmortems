#!/usr/bin/env bash
# Laboratorio 03 — Proceso terminado por el OOM killer dentro de un contenedor con límite de memoria.
# Salida: stdout (redirigir a fichero).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"
cd "$DIR/.."
LEAK_CTR=lab-oom
FIX_CTR=lab-oom-fix

nota "Preparación: limpiar restos de ejecuciones anteriores"
limpiar "$LEAK_CTR" "$FIX_CTR"

nota "T0: arranca el servicio (límite de memoria 96 MB, reinicio automático hasta 2 veces)"
T0="$(date +%s)"
h "docker run -d --name $LEAK_CTR --memory 96m --memory-swap 96m --restart on-failure:2 -v \$PWD/lab/leak-app.js:/app/leak.js:ro node:22-alpine node /app/leak.js | cut -c1-12"

nota "Observación mientras crece el consumo"
sleep 3
h "docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}' $LEAK_CTR"
h "docker logs --tail 3 $LEAK_CTR"
sleep 8
h "docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}' $LEAK_CTR"

nota "Espera a que se agoten los reinicios automáticos (máximo 150 s)"
for _ in $(seq 1 75); do
  [ "$(docker inspect -f '{{.State.Running}}' "$LEAK_CTR")" = "false" ] && break
  sleep 2
done

nota "Síntoma: el contenedor está parado"
h "docker ps -a --filter name=^${LEAK_CTR}\$ --format 'table {{.Names}}\t{{.Status}}'"

nota "Diagnóstico: ¿lo mató el OOM killer?"
h "docker inspect $LEAK_CTR --format 'OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}} RestartCount={{.RestartCount}} MemLimit={{.HostConfig.Memory}}'"
h "docker logs --tail 4 $LEAK_CTR"
h "docker events --since $T0 --until \$(date +%s) --filter container=$LEAK_CTR --filter event=oom --format '{{.Time}} {{.Type}} {{.Action}} {{.Actor.Attributes.name}}'"
h "journalctl -k --since '10 min ago' --no-pager 2>&1 | grep -i 'memory cgroup out of memory' | tail -n 2"

nota "Resolución: desplegar la versión corregida (caché acotada) con el mismo límite"
T1="$(date +%s)"
h "docker run -d --name $FIX_CTR --memory 96m --memory-swap 96m --restart on-failure:2 -e LEAK=off -v \$PWD/lab/leak-app.js:/app/leak.js:ro node:22-alpine node /app/leak.js | cut -c1-12"
sleep 15

nota "Verificación: memoria estable y sin reinicios"
h "docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}' $FIX_CTR"
h "docker logs --tail 2 $FIX_CTR"
h "docker inspect $FIX_CTR --format 'OOMKilled={{.State.OOMKilled}} RestartCount={{.RestartCount}} Running={{.State.Running}}'"

nota "Limpieza"
limpiar "$LEAK_CTR" "$FIX_CTR"
echo "contenedores $LEAK_CTR y $FIX_CTR eliminados"
