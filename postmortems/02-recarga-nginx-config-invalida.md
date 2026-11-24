# Postmortem 02 — Configuración de nginx inválida y caída tras reinicio

> **Incidente simulado en laboratorio.** Este incidente no ocurrió en
> producción ni afectó a ningún usuario, empresa o cliente. Lo provoqué a
> propósito en un contenedor Docker de mi equipo para practicar el diagnóstico
> y documentarlo. Los comandos y las salidas son reales (ver
> [evidencia completa](evidencias/02-recarga-nginx.log)); los tiempos son los
> del ensayo y no representan un servicio real.

| Campo | Valor |
| --- | --- |
| Fecha del ensayo | 2026-11-24 |
| Entorno | Contenedor `nginx:1.27-alpine`, configuración montada desde el host |
| Script | [`lab/02-recarga-nginx.sh`](../lab/02-recarga-nginx.sh) |
| Gravedad (ficticia) | SEV1 durante la caída; sin impacto hasta el reinicio |
| Runbook relacionado | [Servicio caído](../runbooks/servicio-caido.md) |

## Resumen

Se guardó un cambio en la configuración de nginx que apuntaba a un host
inexistente (`app-backend`). El intento de recarga **falló con un error**, pero
en el ensayo ese error no se atendió: el servicio siguió respondiendo con la
configuración anterior y parecía sano. Un reinicio posterior aplicó la
configuración rota y nginx **no arrancó** (`Exited (1)`). Se restauró la
configuración buena, se validó con `nginx -t` y el servicio volvió a responder.

Lo importante: el fallo estaba «escondido» entre el cambio y el siguiente
reinicio.

## Impacto

- **Ensayo:** el servicio estuvo parado desde el reinicio (09:17:14) hasta el
  arranque con la configuración restaurada (09:17:19), unos 5 segundos de
  laboratorio.
- **Usuarios afectados:** ninguno; es un laboratorio.
- **Cambio no entregado:** tras restaurar la configuración, el servicio sirve
  la versión anterior (`ok v1`). El cambio original (`ok v2` con `/api/`) sigue
  pendiente de corregirse.

## Cronología

Horas del equipo anfitrión (CET, UTC+1); los logs de nginx van en UTC.

| Hora | Evento |
| --- | --- |
| 09:17:09 | Arranca el contenedor con la configuración válida (v1) |
| 09:17:12 | `nginx -t` correcto; `wget` devuelve `ok v1` |
| 09:17:12 | **T0:** se guarda una configuración con `proxy_pass http://app-backend:8080;` |
| 09:17:12 | **T1:** `nginx -s reload` devuelve error y código de salida 1 |
| 09:17:13 | El servicio sigue respondiendo `ok v1` (configuración antigua); `nginx -t` ya falla |
| 09:17:13 | **T3:** reinicio del contenedor (`docker restart`) |
| 09:17:16 | El contenedor está en `Exited (1)`; no hay servicio |
| 09:17:16 | **T4:** diagnóstico con un contenedor desechable: `nginx -t` falla |
| 09:17:16 | **T5:** se restaura la configuración buena; `nginx -t` correcto |
| 09:17:17 | `docker start`; a las 09:17:19 el servicio responde `ok v1` |

## Qué se ejecutó y qué se vio

### La recarga falla, pero el servicio no se entera

```text
(lab-nginx)$ nginx -s reload; echo "rc de nginx -s reload = $?"
2026/11/24 08:17:12 [emerg] 59#59: host not found in upstream "app-backend" in /etc/nginx/conf.d/default.conf:7
nginx: [emerg] host not found in upstream "app-backend" in /etc/nginx/conf.d/default.conf:7
rc de nginx -s reload = 1
```

Observación importante: el error solo aparece en la salida de quien ejecuta el
comando. Los logs del contenedor (`docker logs`) **no lo muestran**, así que
alguien que mire solo los logs del servicio no ve nada raro.

```text
$ docker ps --filter name=lab-nginx --format 'table {{.Names}}\t{{.Status}}'
NAMES       STATUS
lab-nginx   Up 3 seconds
(lab-nginx)$ wget -qO- http://127.0.0.1/
ok v1
(lab-nginx)$ nginx -t
2026/11/24 08:17:13 [emerg] 65#65: host not found in upstream "app-backend" in /etc/nginx/conf.d/default.conf:7
nginx: [emerg] host not found in upstream "app-backend" in /etc/nginx/conf.d/default.conf:7
nginx: configuration file /etc/nginx/nginx.conf test failed
(código de salida: 1)
```

Estado engañoso: el contenedor está `Up`, el servicio responde, pero el
fichero de configuración en disco ya no es válido.

### El reinicio convierte el fallo latente en caída

```text
$ docker ps -a --filter name=lab-nginx --format 'table {{.Names}}\t{{.Status}}'
NAMES       STATUS
lab-nginx   Exited (1) 2 seconds ago
$ docker inspect lab-nginx --format 'ExitCode={{.State.ExitCode}} Running={{.State.Running}}'
ExitCode=1 Running=false
$ docker logs --tail 5 lab-nginx
/docker-entrypoint.sh: Launching /docker-entrypoint.d/20-envsubst-on-templates.sh
/docker-entrypoint.sh: Launching /docker-entrypoint.d/30-tune-worker-processes.sh
/docker-entrypoint.sh: Configuration complete; ready for start up
2026/11/24 08:17:14 [emerg] 1#1: host not found in upstream "app-backend" in /etc/nginx/conf.d/default.conf:7
nginx: [emerg] host not found in upstream "app-backend" in /etc/nginx/conf.d/default.conf:7
```

### Resolución: validar sin tocar el servicio y restaurar

```text
$ docker run --rm -v /tmp/tmp.EPBG3URqlQ/conf.d:/etc/nginx/conf.d:ro nginx:1.27-alpine nginx -t
...
nginx: [emerg] host not found in upstream "app-backend" in /etc/nginx/conf.d/default.conf:7
nginx: configuration file /etc/nginx/nginx.conf test failed
(código de salida: 1)
```

Tras restaurar la configuración buena:

```text
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
$ docker start lab-nginx
lab-nginx
(lab-nginx)$ wget -qO- http://127.0.0.1/
ok v1
$ docker ps --filter name=lab-nginx --format 'table {{.Names}}\t{{.Status}}'
NAMES       STATUS
lab-nginx   Up 2 seconds
```

(En la salida completa de la evidencia se ven líneas de
`docker-entrypoint.sh` sobre un sistema de ficheros de solo lectura: son
informativas y no afectan al resultado.)

### Prevención: validar antes de recargar

```text
(lab-nginx)$ nginx -t && nginx -s reload; echo "rc = $?"
nginx: [emerg] host not found in upstream "app-backend" in /etc/nginx/conf.d/default.conf:7
nginx: configuration file /etc/nginx/nginx.conf test failed
rc = 1
(lab-nginx)$ wget -qO- http://127.0.0.1/
ok v1
```

## Causa raíz

Se guardó una configuración sin validar que referenciaba un nombre de host
(`app-backend`) que no se resolvía desde ese contenedor. nginx comprueba los
nombres de los `proxy_pass` estáticos al cargar la configuración y se niega a
arrancar si no los encuentra.

Factores que lo hicieron posible (sobre el proceso, no sobre personas):

1. La configuración en disco y la configuración en ejecución podían divergir sin
   que nada lo señalara.
2. El error de recarga solo llegó a la salida de quien ejecutó el comando; no
   quedó en los logs del servicio ni generó alerta.
3. No había validación (`nginx -t`) como paso obligatorio antes de dar el
   cambio por terminado.
4. No había una comprobación posterior (healthcheck o prueba de humo) ligada al
   cambio.

## Qué fue bien

- El servicio no se cayó en la recarga fallida: nginx conservó la
  configuración anterior.
- `docker logs` y `docker inspect` dieron el motivo de la caída en una sola
  línea (`host not found in upstream`).
- Se pudo validar la configuración con un contenedor desechable (`--rm`) sin
  tocar el servicio.

## Qué fue mal

- El error de la recarga se pasó por alto; el sistema parecía sano.
- El fallo solo se manifestó en el siguiente reinicio, lejos del cambio que lo
  causó, lo que complica relacionarlos.
- No existía una versión anterior de la configuración controlada (en el
  ensayo se restauró desde el propio script).

## Acciones

| Acción | Tipo | Estado |
| --- | --- | --- |
| Ejecutar `nginx -t` y comprobar su código de salida antes de recargar | Prevención | Verificada en el ensayo |
| Que cualquier automatización falle si `nginx -s reload` devuelve ≠ 0 | Prevención | Propuesta |
| Guardar la configuración en control de versiones para poder revertir | Prevención | Propuesta |
| Healthcheck y alerta si el contenedor queda en `Exited` | Detección | Propuesta, sin implementar |
| Prueba de humo (`curl`) tras cada cambio de configuración | Detección | Propuesta |

## Lecciones

- «Recargado» no significa «correcto»: hay que mirar el código de salida y
  volver a probar el servicio.
- Una configuración inválida en disco es una caída aplazada hasta el próximo
  reinicio.
- Validar (`nginx -t`) es barato y debe ir siempre antes de recargar.

## Cómo reproducirlo

```bash
bash lab/02-recarga-nginx.sh > salida.log 2>&1
```

Requiere Docker y la imagen `nginx:1.27-alpine`. No necesita Internet.
