# Postmortem 01 — Disco lleno por un log sin rotación

> **Incidente simulado en laboratorio.** Este incidente no ocurrió en
> producción ni afectó a ningún usuario, empresa o cliente. Lo provoqué a
> propósito en un contenedor Docker de mi equipo para practicar el diagnóstico
> y documentarlo. Los comandos y las salidas son reales (ver
> [evidencia completa](evidencias/01-disco-lleno.log)); los tiempos son los del
> ensayo y no representan un servicio real.

| Campo | Valor |
| --- | --- |
| Fecha del ensayo | 2026-11-24 |
| Entorno | Contenedor `ubuntu:24.04` con un `tmpfs` de 16 MB en `/var/log/app` |
| Script | [`lab/01-disco-lleno.sh`](../lab/01-disco-lleno.sh) |
| Gravedad (ficticia) | SEV2 — el servicio no puede escribir su log |
| Runbook relacionado | [Disco lleno](../runbooks/disco-lleno.md) |

## Resumen

Una aplicación simulada escribe su log en `/var/log/app/app.log` sin ninguna
rotación ni límite. El sistema de ficheros de 16 MB llegó al 100 % en unos
segundos y la aplicación empezó a registrar errores de escritura. Un primer
intento de arreglo (borrar el fichero con `rm`) **no liberó espacio**, porque la
aplicación mantenía el fichero abierto. El espacio se recuperó vaciando el
descriptor retenido y se previno la repetición con `logrotate`.

## Impacto

- **Impacto en el ensayo:** la aplicación simulada dejó de poder escribir en su
  log (`ERROR no se puede escribir en /var/log/app/app.log`).
- **Usuarios afectados:** ninguno; es un laboratorio.
- **Datos perdidos:** el contenido de `app.log` (16 MB de líneas generadas).
  En un sistema real esto significaría perder la evidencia de lo ocurrido; es
  una de las razones de preferir rotar/comprimir antes que borrar.
- **Duración:** unos 5 segundos entre el síntoma y la recuperación. Es el
  tiempo de un script, **no** representa un tiempo de respuesta humano.

## Cronología

Las horas son las del equipo anfitrión (CET, UTC+1). Los logs internos del
contenedor están en UTC, una hora por detrás.

| Hora | Evento |
| --- | --- |
| 09:16:15 | Se crea el contenedor con un `tmpfs` de 16 MB en `/var/log/app` |
| 09:16:39 | **T0:** arranca la aplicación (sin rotación de logs) |
| 09:16:42 | `df -h` muestra 100 % y `/tmp/app.err` contiene errores de escritura |
| 09:16:42 | Diagnóstico: `df -i` descarta falta de inodos; `du` señala `app.log` |
| 09:16:43 | Intento incorrecto: `rm app.log`. `df` sigue al 100 % |
| 09:16:43 | `lsof +L1` revela el fichero `(deleted)` retenido por la aplicación |
| 09:16:43 | Se vacía el descriptor (`: > /proc/PID/fd/3`); `df` marca 0 usado |
| 09:16:44 | Se detiene la aplicación y se reinicia con ritmo normal de escritura |
| 09:16:47 | Se instala la configuración de `logrotate`; `logrotate -f` rota el log |
| 09:16:48 | Verificación: `df` al 1 %, `app.log` y `app.log.1.gz` presentes |

## Qué se ejecutó y qué se vio

### Síntoma: el sistema de ficheros está lleno

```text
(lab-disco)$ df -h /var/log/app
Filesystem      Size  Used Avail Use% Mounted on
tmpfs            16M   16M     0 100% /var/log/app
(lab-disco)$ tail -n 3 /tmp/app.err
08:16:42 ERROR no se puede escribir en /var/log/app/app.log
```

### Diagnóstico: ¿espacio o inodos? ¿qué ocupa?

```text
(lab-disco)$ df -i /var/log/app
Filesystem      Inodes IUsed   IFree IUse% Mounted on
tmpfs          4050431     2 4050429    1% /var/log/app
(lab-disco)$ du -ah /var/log/app | sort -h | tail -n 3
16M	/var/log/app
16M	/var/log/app/app.log
```

Los inodos están al 1 %, así que el problema es de **bloques** (espacio), y un
único fichero lo ocupa casi todo.

### El intento que no funcionó

```text
(lab-disco)$ rm /var/log/app/app.log
(lab-disco)$ df -h /var/log/app
Filesystem      Size  Used Avail Use% Mounted on
tmpfs            16M   16M     0 100% /var/log/app
(lab-disco)$ lsof +L1 /var/log/app
COMMAND  PID USER   FD   TYPE DEVICE SIZE/OFF NLINK NODE NAME
bash    2482 root    3w   REG  0,160 16777216     0    2 /var/log/app/app.log (deleted)
sleep   2490 root    3w   REG  0,160 16777216     0    2 /var/log/app/app.log (deleted)
```

El fichero ya no tiene nombre (`NLINK 0`, `(deleted)`) pero el kernel no libera
los bloques mientras algún proceso tenga el descriptor abierto. Aparece
también `sleep` porque el proceso hijo hereda el descriptor 3.

### Corrección

```text
(lab-disco)$ PID=$(cat /tmp/app.pid); : > /proc/$PID/fd/3; df -h /var/log/app
Filesystem      Size  Used Avail Use% Mounted on
tmpfs            16M     0   16M   0% /var/log/app
```

Vaciar el fichero a través de `/proc/PID/fd/N` libera el espacio sin reiniciar
el proceso. Después se detuvo la aplicación y se reinició con un ritmo de
escritura normal.

### Prevención verificada

```text
(lab-disco)$ logrotate -f /etc/logrotate.d/app; sleep 1; ls -lh /var/log/app; df -h /var/log/app
total 8.0K
-rw-r--r-- 1 root root 1.8K Nov 24 08:16 app.log
-rw-r--r-- 1 root root  391 Nov 24 08:16 app.log.1.gz
Filesystem      Size  Used Avail Use% Mounted on
tmpfs            16M  8.0K   16M   1% /var/log/app
```

La opción `copytruncate` permite rotar sin reiniciar una aplicación que
mantiene el fichero abierto en modo *append*.

## Causa raíz

La aplicación escribía un log **sin límite de tamaño ni rotación** en una
partición pequeña. No hubo ningún mecanismo que impidiera el crecimiento ni
ninguna alerta antes de llegar al 100 %.

Cadena de causas (los «5 porqués»):

1. La aplicación no pudo escribir porque el sistema de ficheros estaba lleno.
2. Estaba lleno porque un único fichero de log creció sin parar.
3. Creció porque no había rotación configurada.
4. No había rotación porque el servicio se desplegó sin definir su política de
   logs (en el ensayo, a propósito).
5. Nadie lo detectó antes porque no había monitorización de uso de disco.

## Qué fue bien

- El flujo de diagnóstico `df -h` → `df -i` → `du` distinguió rápido entre falta
  de espacio y falta de inodos y localizó el fichero culpable.
- `lsof +L1` explicó por qué `rm` no había liberado espacio.
- La solución no requirió reiniciar el sistema entero.

## Qué fue mal

- El primer intento (`rm`) no funcionó y se perdió el contenido del log. Fue un
  error incluido a propósito en el ensayo para documentarlo, pero es un error
  muy habitual: conviene comprobar con `lsof +L1` antes de borrar logs en uso.
- No existía rotación de logs ni alerta de espacio.

## Acciones

| Acción | Tipo | Estado |
| --- | --- | --- |
| Rotación con `logrotate` (`copytruncate`, `rotate 3`, `compress`) | Prevención | Verificada en el ensayo |
| Alerta al 80 % de uso de disco (p. ej. con un script de cron) | Detección | Propuesta, sin implementar |
| Añadir «comprobar `lsof +L1` antes de borrar» al runbook | Proceso | Hecho en [Disco lleno](../runbooks/disco-lleno.md) |
| Dimensionar particiones de logs con margen y separadas de `/` | Prevención | Propuesta |

## Lecciones

- Borrar un fichero abierto **no** libera espacio; hay que cerrar el proceso o
  vaciar el descriptor.
- Un `df` al 100 % no siempre significa «hay que borrar cosas»: primero hay que
  saber qué crece y por qué.
- Rotar es mejor que borrar: se conserva la evidencia y se acota el uso.

## Cómo reproducirlo

```bash
bash lab/01-disco-lleno.sh > salida.log 2>&1
```

Requiere Docker y la imagen `ubuntu:24.04` (el script instala `lsof` y
`logrotate` con `apt`, por lo que necesita acceso a Internet).
