# Verificación de los comandos de los runbooks

Este documento dice con precisión **qué comprobé y qué no** de los comandos que
aparecen en los [runbooks](../runbooks/README.md). Existe para que nadie (ni yo)
confunda «el comando se ejecuta» con «el runbook resuelve un incidente real».

## Qué significa «comprobado»

Un comando se considera comprobado cuando lo ejecuté con éxito en uno de estos
entornos, con el script [`lab/verificar-comandos.sh`](../lab/verificar-comandos.sh):

- Contenedor `ubuntu:24.04` (Debian/Ubuntu).
- Contenedor `archlinux:base` (Arch).
- Contenedor `postgres:16` (consultas de diagnóstico).
- Mi propio equipo, basado en Arch, **solo con comandos de lectura** (sin
  mostrar su salida, porque contiene datos del equipo).

El registro con el resultado de cada comprobación está en
[`postmortems/evidencias/05-verificacion-comandos.log`](../postmortems/evidencias/05-verificacion-comandos.log):
79 comprobaciones, todas con el resultado esperado en la ejecución final.

Hubo una ejecución previa con dos fallos que sirvieron para mejorar el material:

- Instalé paquetes en Arch con `pacman -Sy` (actualización parcial, algo que no
  se debe hacer) y `dig` dejó de funcionar por una librería incompatible. Era un
  error de mi prueba, no del runbook; repetí con `pacman -Syu`.
- `passwd -u` se negó a desbloquear una cuenta sin contraseña. Es un
  comportamiento real que ahora recoge el runbook de
  [usuario bloqueado](../runbooks/usuario-bloqueado.md).

## Resumen por runbook

| Runbook | Reproducido como incidente | Comandos comprobados |
| --- | --- | --- |
| [Disco lleno](../runbooks/disco-lleno.md) | Sí ([postmortem 01](../postmortems/01-disco-lleno-log-sin-rotacion.md)) | `df`, `du`, `find`, `lsof +L1`, `truncate`, vaciado por `/proc/PID/fd`, `logrotate`. En el anfitrión: `journalctl --disk-usage` |
| [Servicio caído](../runbooks/servicio-caido.md) | Sí, nginx en Docker ([postmortem 02](../postmortems/02-recarga-nginx-config-invalida.md)) | `nginx -t`, `docker logs/inspect`, `ss -tlnp`. En el anfitrión (solo lectura): `systemctl status/is-active/--failed/list-timers`, `journalctl -u`, `list-dependencies` |
| [Alta carga / CPU](../runbooks/alta-carga-cpu.md) | No | `uptime`, `nproc`, `top`, `ps`, `vmstat`, `mpstat`, `pidstat`, `iostat`, `renice` |
| [Memoria / OOM](../runbooks/memoria-agotada-oom.md) | Sí, con Docker ([postmortem 03](../postmortems/03-oom-fuga-de-memoria.md)) | `docker inspect/stats/events`, `journalctl -k`, `free`, `ps`, `/proc/pressure/memory`, `fallocate`+`chmod`+`mkswap` |
| [Fallo DNS](../runbooks/fallo-dns.md) | Sí, con Docker ([postmortem 04](../postmortems/04-fallo-resolucion-dns.md)) | `getent hosts`, `dig @servidor`, conexión TCP por IP, `ip route`, `nsswitch`. En el anfitrión: `resolvectl status` |
| [Certificado TLS](../runbooks/certificado-tls-caducado.md) | No | `openssl x509 -enddate/-checkend`, `openssl s_client`, con un certificado autofirmado de prueba |
| [Backup fallido](../runbooks/backup-fallido.md) | No | `tar -tzf`, `gzip -t`, `sha256sum -c`, restauración de prueba, detección de un fichero truncado |
| [Usuario bloqueado](../runbooks/usuario-bloqueado.md) | No | `passwd -S/-l/-u`, `chage -l/-d/-E`, `faillock`, `last/lastb`, con un usuario de prueba |
| [SSH inaccesible](../runbooks/ssh-inaccesible.md) | No | `sshd -t` (válido y roto), `sshd -T`, `ss`, `nc -vz`, `ssh` con rechazo de autenticación |
| [Base de datos lenta](../runbooks/base-de-datos-lenta.md) | No | Consultas de PostgreSQL (`pg_stat_activity`, `pg_blocking_pids`, `pg_cancel_backend` sobre una consulta de prueba) |

## Lo que NO he comprobado

Sé que es una lista larga; prefiero dejarla a la vista:

- **Ningún incidente de producción.** Todo lo anterior es laboratorio o
  comprobación de comandos.
- `systemctl restart`, `reset-failed` y `set-property` (CPU y memoria):
  ejecuté solo comandos de lectura de systemd, y solo en el anfitrión.
- `systemd-resolved` y NetworkManager reales (`resolvectl flush-caches`,
  `nmcli`), y la edición de DNS en un servidor real.
- `ufw`, `nftables`, `fail2ban` y reglas de cortafuegos o grupos de seguridad.
- `certbot` (emisión y renovación) y cualquier validación ACME.
- `pam_faillock` bloqueando de verdad tras intentos fallidos: comprobé que
  `faillock` se ejecuta y se reinicia, pero no provoqué el bloqueo.
- MySQL/MariaDB (las consultas del runbook no se ejecutaron), y cualquier
  ajuste de parámetros de bases de datos.
- LVM (`lvextend`), `docker system prune` y la creación real de swap
  (`swapon`: un contenedor sin privilegios no puede).
- Cron/`cronie` y los nombres de unidad de servicios de backup concretos:
  los nombres de los runbooks son ejemplos.
- Distribuciones fuera de Debian/Ubuntu/Arch (RHEL y derivadas).

Si usas estos runbooks, ajusta los nombres de servicios, rutas y políticas a tu
entorno y prueba antes en un sistema que no sea de producción.
