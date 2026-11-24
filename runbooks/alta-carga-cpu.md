# Runbook: Carga alta o CPU al máximo

| Campo | Valor |
| --- | --- |
| Gravedad típica | Media a alta (lentitud generalizada; puede acabar en caída) |
| Se aplica a | Debian/Ubuntu y Arch |
| Verificación | Comandos comprobados en contenedor (ver [verificación de comandos](../docs/verificacion-comandos.md)); no reproducido como incidente |

## Síntomas

- El servidor responde lento, las sesiones SSH van a tirones.
- `uptime` muestra un *load average* muy por encima del número de CPU.
- Un proceso consume casi el 100 % de uno o más núcleos.

## Impacto

Degradación de todos los servicios del equipo; si la carga no baja, tiempos de
espera, caídas en cascada y, en el peor caso, un sistema que no responde.

## Diagnóstico rápido (N1)

La clave es separar **carga** (procesos esperando) de **uso de CPU**. Una carga
alta con CPU baja suele ser espera de disco o de red, no de CPU.

```bash
# 1. Carga frente al número de CPU (carga ≈ nproc ya es «llena»)
uptime
nproc

# 2. Quién consume CPU y memoria ahora
top -b -n1 | head -n 15
ps -eo pid,ppid,user,%cpu,%mem,etime,stat,cmd --sort=-%cpu | head -n 10

# 3. ¿CPU, espera de E/S o memoria? Mira us, sy, wa y las columnas r y b
vmstat 1 5

# 4. Procesos bloqueados en E/S (estado D)
ps -eo pid,stat,wchan:20,cmd | awk '$2 ~ /^D/' | head

# 5. Por núcleo y por proceso (paquete sysstat)
mpstat -P ALL 1 3
pidstat 1 5
iostat -x 1 3

# 6. ¿Se lanzó algo hace poco? (cron, backups, despliegues)
systemctl list-timers --no-pager | head
journalctl --since "30 min ago" --no-pager | tail -n 30
```

Interpretación rápida de `vmstat`:

- `us` alto: una aplicación calcula demasiado.
- `sy` alto: mucho trabajo del kernel (red, muchos procesos, cambios de contexto).
- `wa` alto: se espera al disco; mira `iostat -x` y el runbook de
  [Disco lleno](disco-lleno.md) o de [Base de datos lenta](base-de-datos-lenta.md).
- `r` muy por encima de `nproc`: procesos en cola de CPU.
- `si`/`so` distintos de 0 de forma sostenida: intercambio a swap; ver
  [Memoria agotada](memoria-agotada-oom.md).

## Resolución

1. **Identifica el proceso y su propietario.** Si es un trabajo programado
   (backup, informe), quizá basta con esperar o reprogramarlo.
2. **Baja su prioridad sin matarlo:**

   ```bash
   sudo renice +10 -p PID
   ```

3. **Limita un servicio de systemd** (efecto inmediato, no persiste tras el
   reinicio):

   ```bash
   sudo systemctl set-property --runtime nombre.service CPUQuota=50%
   ```

4. **Reinicia el servicio** si el procedimiento lo permite y el proceso está
   descontrolado: `sudo systemctl restart nombre`.
5. **Último recurso, terminar un proceso:** primero `kill PID` (SIGTERM), espera
   unos segundos, y solo después `kill -9 PID`. No mates procesos de
   base de datos sin consultar a N2.
6. Si el proceso no es reconocible (nombre extraño, ejecutándose desde
   `/tmp`), **no lo borres**: conserva la evidencia y escala a seguridad.

## Verificación

```bash
uptime            # la carga de 1 y 5 minutos debe bajar
top -b -n1 | head -n 12
vmstat 1 5
```

Comprueba que el servicio responde con normalidad (`curl`, prueba funcional) y
observa 15 minutos.

## Escalado

| Nivel | Cuándo | Qué hace |
| --- | --- | --- |
| N1 | Siempre primero | Identifica el proceso, baja prioridad, reinicia si está autorizado |
| N2 | La carga vuelve a subir; la causa es una aplicación, base de datos o E/S; hay que limitar recursos o ajustar configuración | Perfila el proceso, ajusta límites, revisa consultas y trabajos |
| N3 | Defecto de código o de capacidad; bucle infinito; dimensionamiento | Corrige la aplicación o redimensiona |

Escala a seguridad si hay procesos desconocidos con alto consumo (posible
minería de criptomonedas o malware).

## Prevención

- Monitorizar carga, CPU y espera de E/S con alertas sostenidas (no por picos).
- Escalonar trabajos programados y usar `nice`/`ionice`.
- Límites de recursos en unidades de systemd (`CPUQuota=`, `MemoryMax=`).
- Pruebas de carga antes de los despliegues.
