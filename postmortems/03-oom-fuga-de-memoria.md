# Postmortem 03 — Servicio terminado por falta de memoria (OOM)

> **Incidente simulado en laboratorio.** Este incidente no ocurrió en
> producción ni afectó a ningún usuario, empresa o cliente. Lo provoqué a
> propósito en un contenedor Docker de mi equipo para practicar el diagnóstico
> y documentarlo. Los comandos y las salidas son reales (ver
> [evidencia completa](evidencias/03-oom.log)); los tiempos son los del ensayo
> y no representan un servicio real.

| Campo | Valor |
| --- | --- |
| Fecha del ensayo | 2026-11-24 |
| Entorno | Contenedores `node:22-alpine` con límite de memoria de 96 MB |
| Script | [`lab/03-oom.sh`](../lab/03-oom.sh) y [`lab/leak-app.js`](../lab/leak-app.js) |
| Gravedad (ficticia) | SEV1 — el servicio termina cada pocos segundos |
| Runbook relacionado | [Memoria agotada / OOM](../runbooks/memoria-agotada-oom.md) |

## Resumen

Una aplicación simulada de Node.js acumula bloques de 4 MB en memoria sin
liberarlos (una fuga de memoria deliberada). Con un límite de 96 MB, el kernel
la mató con `SIGKILL` (código de salida 137). La política de reinicio
`on-failure:2` la relanzó dos veces, la fuga se repitió cada vez y finalmente el
contenedor quedó parado. Se resolvió desplegando una versión con la caché
acotada a 4 bloques, que se mantuvo estable con el mismo límite.

## Impacto

- **Ensayo:** el servicio no se mantuvo en pie: tres ejecuciones consecutivas
  terminaron por OOM (la inicial y dos reinicios) y después quedó parado.
- **Usuarios afectados:** ninguno; es un laboratorio.
- **Datos perdidos:** ninguno (la aplicación no guarda estado).

## Cronología

Horas del equipo anfitrión (CET, UTC+1); los logs de la aplicación van en UTC.

| Hora | Evento |
| --- | --- |
| 09:22:13 | **T0:** arranca el servicio con `--memory 96m --restart on-failure:2` |
| 09:22:16 | `docker stats`: 36,84 MiB de 96 MiB; el log muestra `rss` creciendo |
| 09:22:36 | El kernel registra una muerte por OOM en el cgroup (PID 143686) |
| 09:22:47 | El kernel registra una segunda muerte por OOM (PID 147780, la última) |
| 09:22:49 | `docker ps -a`: `Exited (137)`; `OOMKilled=true`, `RestartCount=2` |
| 09:22:49 | Se despliega la versión corregida con el mismo límite |
| 09:23:04 | Verificación: `rss` estable, `RestartCount=0`, `OOMKilled=false` |

Una primera muerte por OOM tuvo que ocurrir antes de las 09:22:26 (la
muestra de `docker stats` de las 09:22:25 ya marca 20,73 MiB, es decir, un
proceso recién reiniciado), pero mi comando solo guardó las dos últimas líneas
del log del kernel y esa no quedó capturada. Que fueron tres muertes en total
es una deducción (1 inicial + 2 reinicios permitidos por la política), no una
medición directa.

## Qué se ejecutó y qué se vio

### Crecimiento del consumo

```text
$ docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}' lab-oom
NAME      MEM USAGE / LIMIT   MEM %
lab-oom   36.84MiB / 96MiB    38.38%
$ docker logs --tail 3 lab-oom
2026-11-24T08:22:16.735Z cache_chunks=6 rss=73MB
2026-11-24T08:22:17.237Z cache_chunks=7 rss=77MB
2026-11-24T08:22:17.739Z cache_chunks=8 rss=81MB
```

El contador `cache_chunks` solo sube: nada se libera. El valor de `rss` incluye
también páginas del propio binario de Node, por eso puede superar el límite
del cgroup sin que se aplique la muerte hasta que la memoria *anónima* lo
alcanza.

### Síntoma y diagnóstico

```text
$ docker ps -a --filter name=^lab-oom$ --format 'table {{.Names}}\t{{.Status}}'
NAMES     STATUS
lab-oom   Exited (137) 1 second ago
$ docker inspect lab-oom --format 'OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}} RestartCount={{.RestartCount}} MemLimit={{.HostConfig.Memory}}'
OOMKilled=true ExitCode=137 RestartCount=2 MemLimit=100663296
```

El código 137 es 128 + 9 (`SIGKILL`). Por sí solo no prueba que fuera el OOM
killer (cualquier `kill -9` da 137); lo prueba `OOMKilled=true` y el log del
kernel:

```text
$ journalctl -k --since '10 min ago' --no-pager 2>&1 | grep -i 'memory cgroup out of memory' | tail -n 2
nov 24 09:22:36 cachyos kernel: Memory cgroup out of memory: Killed process 143686 (node) total-vm:778040kB, anon-rss:97052kB, file-rss:43568kB, shmem-rss:0kB, UID:0 pgtables:720kB oom_score_adj:0
nov 24 09:22:47 cachyos kernel: Memory cgroup out of memory: Killed process 147780 (node) total-vm:778040kB, anon-rss:97028kB, file-rss:43472kB, shmem-rss:0kB, UID:0 pgtables:744kB oom_score_adj:0
```

`anon-rss` ≈ 97 000 kB (unos 94,8 MiB), prácticamente el límite de 96 MiB del
contenedor (100663296 bytes); el resto lo ocupan páginas de fichero
(`file-rss`), que el kernel puede recuperar.

Un detalle sobre la fiabilidad de las fuentes: `docker events --filter
event=oom` mostró **un único** evento en esta ejecución (en una ejecución
anterior del mismo script mostró tres). No es un contador fiable del número de
muertes; `State.OOMKilled` y el log del kernel sí lo fueron. En la ejecución
final no pude consultar `dmesg` por falta de permisos, y usé `journalctl -k`.

### Resolución y verificación

```text
$ docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}' lab-oom-fix
NAME          MEM USAGE / LIMIT   MEM %
lab-oom-fix   37.62MiB / 96MiB    39.19%
$ docker logs --tail 2 lab-oom-fix
2026-11-24T08:23:04.622Z cache_chunks=4 rss=72MB
2026-11-24T08:23:05.125Z cache_chunks=4 rss=76MB
$ docker inspect lab-oom-fix --format 'OOMKilled={{.State.OOMKilled}} RestartCount={{.RestartCount}} Running={{.State.Running}}'
OOMKilled=false RestartCount=0 Running=true
```

Observé solo 15 segundos de la versión corregida. Con una fuga de ~8 MB/s la
versión original ya había muerto en menos de 12 s, por lo que 15 s sin
reinicios es evidencia razonable, pero no una prueba de estabilidad a largo
plazo.

## Causa raíz

La aplicación retenía en memoria todos los datos que recibía (una estructura
que solo crece) y el contenedor tenía un límite fijo de memoria. Cuando la
memoria anónima alcanzó el límite, el kernel mató el proceso.

Factores contribuyentes:

1. Estructura de datos sin cota máxima (en el ensayo, deliberadamente).
2. La política de reinicio automático ocultó el problema: el servicio volvía a
   levantarse y moría de nuevo, sin que nadie recibiera un aviso.
3. No había monitorización de la memoria del contenedor ni alerta por
   reinicios repetidos.

## Qué fue bien

- `docker inspect` (`OOMKilled`, `ExitCode`, `RestartCount`) identificó la
  causa en un comando.
- El log del kernel (`journalctl -k`) confirmó el OOM con cifras.
- Comparar la versión con fuga y la corregida con el mismo límite permitió
  verificar el arreglo en igualdad de condiciones.

## Qué fue mal

- Una política de reinicio sin alertas esconde un bucle de fallos.
- Una de las fuentes de evidencia (`docker events`) resultó inconsistente entre
  ejecuciones y no se debe usar para contar muertes.
- Subir el límite de memoria habría retrasado el fallo, no resuelto: la fuga
  seguía ahí.

## Acciones

| Acción | Tipo | Estado |
| --- | --- | --- |
| Acotar la caché (máximo 4 bloques) | Corrección | Verificada 15 s en el ensayo |
| Alerta por reinicios repetidos de un contenedor/servicio | Detección | Propuesta, sin implementar |
| Monitorizar uso de memoria frente al límite (p. ej. 80 %) | Detección | Propuesta, sin implementar |
| Pruebas de carga prolongadas antes de desplegar | Prevención | Propuesta |
| Documentar `OOMKilled` + `journalctl -k` en el runbook de OOM | Proceso | Hecho en [Memoria agotada / OOM](../runbooks/memoria-agotada-oom.md) |

## Lecciones

- El código 137 indica `SIGKILL`; confirmar el OOM con `OOMKilled` y con el log
  del kernel.
- Un reinicio automático no es una solución, es un amortiguador que puede
  esconder el problema.
- Subir el límite de memoria es un parche temporal; hay que buscar quién crece.

## Cómo reproducirlo

```bash
bash lab/03-oom.sh > salida.log 2>&1
```

Requiere Docker y la imagen `node:22-alpine`. Tarda unos 50 segundos. La parte
de `journalctl -k` necesita permiso para leer el log del kernel (en mi equipo
mi usuario lo tiene; si no, esa línea no mostrará nada).
