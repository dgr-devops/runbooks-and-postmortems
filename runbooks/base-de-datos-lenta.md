# Runbook: Base de datos lenta

| Campo | Valor |
| --- | --- |
| Gravedad típica | Alta (las aplicaciones se vuelven lentas o dejan de responder) |
| Se aplica a | MySQL/MariaDB y PostgreSQL en Debian/Ubuntu y Arch |
| Verificación | Sintaxis de las consultas de diagnóstico de PostgreSQL comprobada en contenedor `postgres:16` (ver [verificación de comandos](../docs/verificacion-comandos.md)); MySQL/MariaDB no probado; no reproducido como incidente |

## Síntomas

- Las aplicaciones tardan mucho en responder o muestran errores de tiempo de
  espera.
- Muchas conexiones abiertas o `Too many connections`.
- Consultas que antes tardaban milisegundos tardan segundos.

## Impacto

Toda aplicación que dependa de la base de datos. Puede pasar de «lento» a
«caído» si se agotan las conexiones.

## Diagnóstico rápido (N1)

Empieza por el **servidor** (a menudo la causa es el sistema, no la base de
datos) y después mira qué hace la base de datos.

```bash
# 1. Recursos del servidor: CPU, memoria, swap, disco, E/S
uptime
free -h
df -h
vmstat 1 5
iostat -x 1 3

# 2. ¿Hay un backup o trabajo pesado en marcha?
systemctl list-timers --no-pager | head
ps -eo pid,etime,%cpu,%mem,cmd --sort=-%cpu | head -n 8
```

### PostgreSQL

```bash
# Consultas activas, de más a menos antigua
sudo -u postgres psql -c "SELECT pid, now() - query_start AS duracion, state, wait_event_type, left(query, 80) AS consulta FROM pg_stat_activity WHERE state <> 'idle' ORDER BY duracion DESC LIMIT 10;"

# Conexiones frente al máximo
sudo -u postgres psql -c "SELECT count(*) AS conexiones, current_setting('max_connections') AS maximo FROM pg_stat_activity;"

# Sesiones bloqueadas y quién las bloquea
sudo -u postgres psql -c "SELECT pid, pg_blocking_pids(pid) AS bloqueada_por, left(query, 60) AS consulta FROM pg_stat_activity WHERE cardinality(pg_blocking_pids(pid)) > 0;"
```

### MySQL / MariaDB

```bash
sudo mysql -e "SHOW FULL PROCESSLIST;"
sudo mysql -e "SHOW GLOBAL STATUS LIKE 'Threads_connected';"
sudo mysql -e "SHOW GLOBAL VARIABLES LIKE 'max_connections';"
sudo mysql -e "SHOW ENGINE INNODB STATUS\G" | sed -n '1,60p'
```

Para ver después qué consultas son lentas, activa el registro de consultas
lentas (N2):

```bash
sudo mysql -e "SET GLOBAL slow_query_log = 1; SET GLOBAL long_query_time = 1;"
```

## Resolución

N1 **no optimiza consultas ni crea índices en producción**. Lo que sí hace:

1. **Problema del servidor** (disco lleno, swap, CPU): sigue el runbook
   correspondiente ([Disco lleno](disco-lleno.md),
   [Alta carga](alta-carga-cpu.md), [Memoria](memoria-agotada-oom.md)).
2. **Una consulta descontrolada o sesión bloqueada:** documenta el `pid`/`Id` y
   la consulta y **pide autorización de N2** antes de cancelarla:

   ```bash
   # PostgreSQL: primero cancelar la consulta; terminar la sesión solo si no basta
   sudo -u postgres psql -c "SELECT pg_cancel_backend(PID);"
   sudo -u postgres psql -c "SELECT pg_terminate_backend(PID);"
   # MySQL/MariaDB
   sudo mysql -e "KILL QUERY ID;"
   ```

3. **Agotamiento de conexiones:** identifica qué aplicación abre tantas y avisa
   a su responsable; subir `max_connections` es decisión de N2.
4. **Backup u otro trabajo pesado en marcha:** valora esperar o reprogramarlo.

## Verificación

```bash
uptime
sudo -u postgres psql -c "SELECT count(*) FROM pg_stat_activity WHERE state <> 'idle';"
sudo mysql -e "SHOW GLOBAL STATUS LIKE 'Threads_running';"
```

Pide a un usuario que repita la operación lenta y compara el tiempo.

## Escalado

| Nivel | Cuándo | Qué hace |
| --- | --- | --- |
| N1 | Siempre primero | Descarta causa de servidor, identifica consultas largas o bloqueos, recopila evidencia |
| N2 | Hay que cancelar consultas, ajustar parámetros, activar el registro de consultas lentas o revisar índices | Analiza con `EXPLAIN`, ajusta configuración, coordina con desarrollo |
| N3 | Consultas o esquema mal diseñados, necesidad de réplicas o particionado | Rediseña esquema e infraestructura |

Escala de inmediato si la base de datos está caída, se acercan al máximo de
conexiones o hay riesgo para los datos.

## Prevención

- Monitorizar conexiones, latencia, bloqueos y espacio.
- Registro de consultas lentas activo y revisado.
- Índices y mantenimiento (`VACUUM`/`ANALYZE`, `OPTIMIZE` según el motor) con
  cabeza.
- Pooling de conexiones en las aplicaciones.
- Trabajos pesados fuera del horario de uso.
