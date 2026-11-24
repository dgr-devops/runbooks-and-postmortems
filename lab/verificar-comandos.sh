#!/usr/bin/env bash
# Verificación de sintaxis y ejecución de los comandos de los runbooks.
#
# Sin argumentos: orquesta contenedores Docker (ubuntu:24.04, postgres:16,
# archlinux:base) y una comprobación de SOLO LECTURA en el equipo anfitrión.
# Con un argumento (ubuntu | arch | postgres | host): ejecuta esa sección;
# lo usa el propio script dentro de cada entorno.
#
# Solo imprime OK/FALLO por comando (sin su salida) para no exponer datos
# del equipo anfitrión. No demuestra que el runbook resuelva un incidente:
# solo que el comando existe, tiene la sintaxis correcta y se ejecuta.
set -u

# chk "descripción" "comando"   (RC_OK="0 1" admite varios códigos válidos)
chk() {
  local desc="$1" cmd="$2" out rc ok=0 c
  out="$(bash -c "$cmd" 2>&1)"; rc=$?
  for c in ${RC_OK:-0}; do [ "$rc" -eq "$c" ] && ok=1; done
  if [ "$ok" -eq 1 ]; then
    printf 'OK    | %s\n' "$desc"
  else
    printf 'FALLO | %s (código %s)\n' "$desc" "$rc"
    printf '%s\n' "$out" | head -n 2 | sed 's/^/        /'
  fi
}

sudo() { "$@"; }   # en los contenedores somos root; los runbooks usan sudo
export -f sudo

seccion_ubuntu() {
  echo "## Ubuntu 24.04 ($(. /etc/os-release; echo "$PRETTY_NAME"))"
  echo "### Disco lleno"
  chk "du por directorio" "sudo du -xh / --max-depth=1 2>/dev/null | sort -h | tail -n 10"
  chk "find ficheros grandes" "sudo find /var -xdev -type f -size +200M -exec ls -lh {} + 2>/dev/null"
  RC_OK="0 1" chk "lsof +L1" "sudo lsof +L1"
  chk "find -printf inodos" "sudo find /var -xdev -printf '%h\n' | sort | uniq -c | sort -nr | head -n 10"
  chk "truncate -s 0" "echo datos > /tmp/x.log && sudo truncate -s 0 /tmp/x.log && [ ! -s /tmp/x.log ]"
  echo "### Alta carga / CPU"
  chk "uptime y nproc" "uptime && nproc"
  chk "top -b -n1" "top -b -n1 | head -n 15"
  chk "ps ordenado por CPU" "ps -eo pid,ppid,user,%cpu,%mem,etime,stat,cmd --sort=-%cpu | head -n 10"
  chk "vmstat 1 2" "vmstat 1 2"
  chk "procesos en estado D (awk)" "ps -eo pid,stat,wchan:20,cmd | awk '\$2 ~ /^D/' | head"
  chk "mpstat -P ALL" "mpstat -P ALL 1 1"
  chk "pidstat" "pidstat 1 1"
  chk "iostat -x" "iostat -x 1 1"
  chk "renice +10" "sleep 30 & sudo renice +10 -p \$!; kill %1"
  echo "### Memoria"
  chk "free -h y swapon --show" "free -h && swapon --show"
  chk "ps ordenado por memoria" "ps -eo pid,user,%mem,rss,etime,cmd --sort=-%mem | head -n 10"
  chk "presión de memoria (PSI)" "cat /proc/pressure/memory"
  chk "fichero de swap: fallocate, chmod, mkswap" "sudo fallocate -l 16M /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile"
  echo "### DNS"
  chk "getent hosts" "getent hosts localhost"
  chk "dig -v" "dig -v"
  chk "ip route" "ip route"
  chk "nsswitch hosts" "grep '^hosts:' /etc/nsswitch.conf"
  echo "### Certificado TLS"
  chk "generar certificado de prueba (60 días)" "openssl req -x509 -newkey rsa:2048 -nodes -days 60 -subj /CN=localhost -keyout /tmp/k.pem -out /tmp/c.pem 2>/dev/null"
  chk "openssl x509 -enddate (fichero)" "sudo openssl x509 -in /tmp/c.pem -noout -enddate"
  chk "-checkend 30 días: debe pasar (60 días de vigencia)" "openssl x509 -in /tmp/c.pem -noout -checkend 2592000"
  RC_OK="1" chk "-checkend 90 días: debe fallar (caducaría antes)" "openssl x509 -in /tmp/c.pem -noout -checkend 7776000"
  ( openssl s_server -accept 8443 -cert /tmp/c.pem -key /tmp/k.pem -www >/dev/null 2>&1 & ); sleep 1
  chk "s_client | x509 (subject, issuer, dates)" "echo | openssl s_client -connect localhost:8443 -servername localhost 2>/dev/null | openssl x509 -noout -subject -issuer -dates"
  chk "s_client | x509 -checkend" "echo | openssl s_client -connect localhost:8443 -servername localhost 2>/dev/null | openssl x509 -noout -checkend 2592000"
  echo "### Backup"
  chk "crear tar.gz y listarlo (tar -tzf)" "mkdir -p /tmp/d && echo hola > /tmp/d/a && tar -czf /tmp/b.tar.gz -C /tmp d && tar -tzf /tmp/b.tar.gz >/dev/null"
  chk "gzip -t" "echo datos | gzip > /tmp/b.gz && gzip -t /tmp/b.gz"
  chk "sha256sum -c" "cd /tmp && sha256sum b.tar.gz > b.sha256 && sha256sum -c b.sha256"
  chk "restauración de prueba (tar -xzf)" "mkdir -p /tmp/r && tar -xzf /tmp/b.tar.gz -C /tmp/r && ls /tmp/r/d"
  RC_OK="1 2" chk "un backup truncado se detecta (debe fallar)" "head -c 50 /tmp/b.tar.gz > /tmp/roto.tar.gz && tar -tzf /tmp/roto.tar.gz >/dev/null"
  echo "### Usuario bloqueado"
  chk "useradd de prueba" "useradd -m usuprueba"
  chk "getent passwd / id" "getent passwd usuprueba && id usuprueba"
  chk "passwd -S" "sudo passwd -S usuprueba"
  chk "chage -l" "sudo chage -l usuprueba"
  chk "faillock --user" "sudo faillock --user usuprueba"
  chk "faillock --reset" "sudo faillock --user usuprueba --reset"
  chk "contraseña de prueba aleatoria (chpasswd)" "echo usuprueba:\$(openssl rand -hex 12) | chpasswd"
  chk "passwd -l (bloquear)" "passwd -l usuprueba && passwd -S usuprueba | grep -q ' L '"
  chk "passwd -u (desbloquear)" "passwd -u usuprueba && passwd -S usuprueba | grep -q ' P '"
  RC_OK="3" chk "passwd -u se niega si la cuenta no tiene contraseña" "useradd sinclave && passwd -u sinclave"
  chk "chage -d 0 (cambio obligatorio)" "sudo chage -d 0 usuprueba"
  chk "chage -E -1 (sin caducidad de cuenta)" "sudo chage -E -1 usuprueba"
  RC_OK="0 1" chk "lastb / last" "(sudo lastb | head -n 10); (last usuprueba | head -n 5)"
  echo "### SSH"
  chk "sshd -t (configuración válida)" "mkdir -p /run/sshd && sudo sshd -t"
  chk "sshd -T filtrado" "sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|allowusers|allowgroups) '"
  ( /usr/sbin/sshd ); sleep 1
  chk "ss -tlnp | grep sshd" "sudo ss -tlnp | grep sshd"
  chk "nc -vz -w 5 (puerto abierto)" "nc -vz -w 5 127.0.0.1 22"
  RC_OK="1" chk "nc a puerto cerrado falla (rechazado)" "nc -vz -w 5 127.0.0.1 2299"
  RC_OK="255" chk "ssh sin clave: Permission denied (esperado)" "ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 usuprueba@127.0.0.1 true"
  cp /etc/ssh/sshd_config /tmp/sshd_config.bak; echo "DirectivaInventada si" >> /etc/ssh/sshd_config
  RC_OK="255" chk "sshd -t detecta una configuración rota (debe fallar)" "sudo sshd -t"
  cp /tmp/sshd_config.bak /etc/ssh/sshd_config
  chk "sshd -t tras revertir" "sudo sshd -t"
  echo "### Servicio caído (parte sin systemd)"
  chk "ss -tlnp" "sudo ss -tlnp"
}

seccion_arch() {
  echo "## archlinux:base"
  pacman -Syu --noconfirm pacman-contrib bind sysstat >/dev/null 2>&1; echo "instalación de paquetes: rc=$?"
  chk "paccache -dk2 (simulación)" "paccache -dk2"
  chk "dig (paquete bind)" "dig -v"
  chk "mpstat (paquete sysstat)" "mpstat -V"
  chk "faillock" "faillock --user root"
  chk "passwd -S root" "passwd -S root"
  chk "ss -tlnp" "ss -tlnp"
  chk "free -h" "free -h"
  chk "ps ordenado por CPU" "ps -eo pid,ppid,user,%cpu,%mem,etime,stat,cmd --sort=-%cpu | head -n 5"
}

seccion_postgres() {
  echo "## postgres:16 (consultas del runbook «Base de datos lenta»; psql -U postgres sustituye a sudo -u postgres psql)"
  local P="psql -U postgres"
  chk "pg_stat_activity: consultas activas" "$P -c \"SELECT pid, now() - query_start AS duracion, state, wait_event_type, left(query, 80) AS consulta FROM pg_stat_activity WHERE state <> 'idle' ORDER BY duracion DESC LIMIT 10;\""
  chk "conexiones frente a max_connections" "$P -c \"SELECT count(*) AS conexiones, current_setting('max_connections') AS maximo FROM pg_stat_activity;\""
  chk "sesiones bloqueadas (pg_blocking_pids)" "$P -c \"SELECT pid, pg_blocking_pids(pid) AS bloqueada_por, left(query, 60) AS consulta FROM pg_stat_activity WHERE cardinality(pg_blocking_pids(pid)) > 0;\""
  ( $P -c "SELECT pg_sleep(60);" >/dev/null 2>&1 & ); sleep 1
  chk "pg_cancel_backend sobre una consulta real de prueba" "PID=\$($P -Atc \"SELECT pid FROM pg_stat_activity WHERE query LIKE 'SELECT pg_sleep%' AND pid <> pg_backend_pid() LIMIT 1;\"); $P -Atc \"SELECT pg_cancel_backend(\$PID);\" | grep -q t"
}

seccion_host() {
  echo "## Equipo anfitrión (Arch-based, solo lectura, sin mostrar salida)"
  chk "systemctl status (unidad existente)" "systemctl status systemd-journald --no-pager -l"
  chk "systemctl is-active" "systemctl is-active systemd-journald"
  chk "systemctl --failed" "systemctl --failed"
  chk "systemctl list-timers" "systemctl list-timers --no-pager"
  chk "journalctl -u -n" "journalctl -u systemd-journald -n 5 --no-pager"
  chk "journalctl --disk-usage" "journalctl --disk-usage"
  RC_OK="0 1" chk "journalctl -k | grep oom" "journalctl -k --since '2 hours ago' --no-pager | grep -i -E 'out of memory|oom-killer|killed process'"
  chk "resolvectl status" "resolvectl status"
  chk "timedatectl" "timedatectl"
  chk "findmnt /" "findmnt /"
  chk "swapon --show" "swapon --show"
  chk "systemctl list-dependencies" "systemctl list-dependencies systemd-journald --no-pager"
}

orquestar() {
  local self dir ctr
  self="$(readlink -f "$0")"; dir="$(dirname "$self")"
  for ctr in ver-ubuntu ver-arch ver-pg; do docker rm -f "$ctr" >/dev/null 2>&1; done

  docker run -d --name ver-ubuntu ubuntu:24.04 sleep infinity >/dev/null
  docker exec ver-ubuntu bash -c 'apt-get update -qq >/dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sysstat procps lsof openssl openssh-server openssh-client netcat-openbsd iproute2 dnsutils util-linux login passwd libpam-modules-bin tar gzip >/dev/null 2>&1; echo "instalación de paquetes: rc=$?"'
  docker cp "$self" ver-ubuntu:/verif.sh
  docker exec ver-ubuntu bash /verif.sh ubuntu

  docker run -d --name ver-arch archlinux:base sleep infinity >/dev/null
  docker cp "$self" ver-arch:/verif.sh
  docker exec ver-arch bash /verif.sh arch

  docker run -d --name ver-pg -e POSTGRES_HOST_AUTH_METHOD=trust postgres:16 >/dev/null
  for _ in $(seq 1 30); do docker exec ver-pg pg_isready -U postgres -q && break; sleep 1; done
  sleep 2
  docker cp "$self" ver-pg:/verif.sh
  docker exec ver-pg bash /verif.sh postgres

  seccion_host
  for ctr in ver-ubuntu ver-arch ver-pg; do docker rm -f "$ctr" >/dev/null 2>&1; done
  echo "contenedores de verificación eliminados"
}

case "${1:-}" in
  ubuntu) seccion_ubuntu ;;
  arch) seccion_arch ;;
  postgres) seccion_postgres ;;
  host) seccion_host ;;
  "") orquestar ;;
  *) echo "uso: $0 [ubuntu|arch|postgres|host]" >&2; exit 2 ;;
esac
