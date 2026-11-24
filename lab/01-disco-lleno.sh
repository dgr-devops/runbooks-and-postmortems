#!/usr/bin/env bash
# Laboratorio 01 — Disco lleno por un log sin rotación.
# Usa un tmpfs de 16 MB montado en /var/log/app dentro de un contenedor
# ubuntu:24.04. No toca el disco del host. Salida: stdout (redirigir a fichero).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"
CTR=lab-disco

nota "Preparación (fuera del incidente): contenedor con tmpfs de 16 MB y herramientas"
limpiar "$CTR"
h "docker run -d --name $CTR --tmpfs /var/log/app:size=16m,mode=0755 ubuntu:24.04 sleep infinity | cut -c1-12"
docker cp "$DIR/app-logger.sh" "$CTR:/opt/app-logger.sh" && docker exec "$CTR" chmod +x /opt/app-logger.sh
docker exec "$CTR" bash -c 'apt-get update -qq >/dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq lsof logrotate >/dev/null 2>&1; echo "apt rc=$?"'

nota "Estado inicial"
c 'df -h /var/log/app'

nota "T0: arranca la aplicación (sin rotación de logs)"
c 'nohup /opt/app-logger.sh >/dev/null 2>&1 & sleep 1; echo "pid app: $(cat /tmp/app.pid)"'
sleep 2

nota "Síntoma: el sistema de ficheros está al 100 % y la app registra errores"
c 'df -h /var/log/app'
c 'tail -n 3 /tmp/app.err'

nota "Diagnóstico: ¿espacio o inodos? ¿qué ocupa?"
c 'df -i /var/log/app'
c 'du -ah /var/log/app | sort -h | tail -n 3'
c 'ls -lh /var/log/app'

nota "Intento incorrecto: borrar el fichero que la app mantiene abierto"
c 'rm /var/log/app/app.log'
c 'df -h /var/log/app'
c 'lsof +L1 /var/log/app'

nota "Corrección: liberar el espacio en el descriptor retenido y parar la app"
c 'PID=$(cat /tmp/app.pid); : > /proc/$PID/fd/3; df -h /var/log/app'
c 'kill "$(cat /tmp/app.pid)"; sleep 1; df -h /var/log/app; ls -la /var/log/app'

nota "Prevención: reiniciar la app con ritmo normal y rotación con logrotate"
c 'THROTTLE=0.05 nohup /opt/app-logger.sh >/dev/null 2>&1 & sleep 3; ls -lh /var/log/app'
c 'cat > /etc/logrotate.d/app <<"EOF"
/var/log/app/app.log {
    su root root
    size 50k
    rotate 3
    compress
    copytruncate
    missingok
    notifempty
}
EOF
echo ok'
c 'logrotate -d /etc/logrotate.d/app 2>&1 | head -n 12'
c 'logrotate -f /etc/logrotate.d/app; sleep 1; ls -lh /var/log/app; df -h /var/log/app'

nota "Limpieza"
limpiar "$CTR"
echo "contenedor $CTR eliminado"
