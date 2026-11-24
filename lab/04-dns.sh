#!/usr/bin/env bash
# Laboratorio 04 — Fallo de resolución DNS por un servidor DNS inalcanzable.
# Contenedor ubuntu:24.04 configurado con un resolvedor inexistente
# (192.0.2.53, rango TEST-NET-1 reservado para documentación).
# Salida: stdout (redirigir a fichero).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib.sh"
CTR=lab-dns

nota "Preparación (fuera del incidente): contenedor con DNS normal e instalación de dig"
limpiar "$CTR"
h "docker run -d --name $CTR ubuntu:24.04 sleep infinity | cut -c1-12"
docker exec "$CTR" bash -c 'apt-get update -qq >/dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq dnsutils >/dev/null 2>&1; echo "apt rc=$?"'
c 'time getent hosts example.com'

nota "T0: cambio que provoca el incidente: el resolvedor pasa a ser 192.0.2.53 (simula un DHCP o una edición errónea)"
c 'echo "nameserver 192.0.2.53" > /etc/resolv.conf; grep ^nameserver /etc/resolv.conf'

nota "T1: síntoma reportado: «no abre ninguna web / el servicio no conecta con example.com»"
c 'grep ^nameserver /etc/resolv.conf'
c 'time getent hosts example.com'

nota "Diagnóstico 1: ¿hay conectividad IP? (conexión TCP directa a una IP, sin DNS)"
c 'timeout 5 bash -c "echo > /dev/tcp/1.1.1.1/443" && echo "TCP a 1.1.1.1:443 OK"'

nota "Diagnóstico 2: ¿responde el servidor DNS configurado?"
c 'dig @192.0.2.53 example.com +time=2 +tries=1 | tail -n 4'

nota "Diagnóstico 3: ¿resuelve otro servidor DNS desde esta máquina?"
c 'dig @1.1.1.1 example.com A +short +time=3 +tries=3'

nota "Resolución: apuntar el resolvedor a un servidor DNS que responde"
c 'echo "nameserver 1.1.1.1" > /etc/resolv.conf; grep ^nameserver /etc/resolv.conf'

nota "Verificación"
c 'time getent hosts example.com'

nota "Limpieza"
limpiar "$CTR"
echo "contenedor $CTR eliminado"
