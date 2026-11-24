# Runbook: Memoria agotada / OOM

| Campo | Valor |
| --- | --- |
| Gravedad típica | Alta (procesos terminados de forma abrupta, sistema lento) |
| Se aplica a | Debian/Ubuntu y Arch; contenedores Docker |
| Verificación | Reproducido en laboratorio con Docker: [Postmortem 03](../postmortems/03-oom-fuga-de-memoria.md). La creación de swap no se reprodujo |

## Síntomas

- Un servicio desaparece sin aviso y systemd muestra `code=killed, signal=KILL`.
- Código de salida 137 en un contenedor.
- El sistema se vuelve extremadamente lento (uso intensivo de swap).
- `free -h` muestra muy poca memoria disponible.

## Impacto

Servicios terminados por el kernel (OOM killer), pérdida de estado no
guardado, reinicios en bucle y degradación general del equipo.

## Diagnóstico rápido (N1)

```bash
# 1. Memoria y swap actuales (mira la columna «disponible», no «libre»)
free -h
swapon --show

# 2. Quién consume más memoria
ps -eo pid,user,%mem,rss,etime,cmd --sort=-%mem | head -n 10

# 3. ¿Mató el kernel algún proceso? (puede requerir sudo o grupo systemd-journal)
journalctl -k --since "2 hours ago" --no-pager | grep -i -E 'out of memory|oom-killer|killed process'
sudo dmesg -T | grep -i -E 'out of memory|killed process'

# 4. Presión de memoria y actividad de swap
cat /proc/pressure/memory
vmstat 1 5

# 5. ¿Se reinicia el servicio en bucle?
systemctl status nombre --no-pager
journalctl -u nombre --since "1 hour ago" --no-pager | grep -i -E 'killed|oom|start'
```

### En contenedores Docker

```bash
docker inspect nombre --format 'OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}} RestartCount={{.RestartCount}}'
docker stats --no-stream
```

El código 137 solo indica `SIGKILL`; confírmalo con `OOMKilled=true` o con el
log del kernel. La salida real de este diagnóstico está en el
[postmortem 03](../postmortems/03-oom-fuga-de-memoria.md).

## Resolución

1. **Recupera el servicio:** `sudo systemctl restart nombre` (o
   `docker start nombre`). Es un parche: si hay fuga, volverá a ocurrir.
2. **Libera memoria de forma segura:** detén procesos no críticos o trabajos
   pesados programados. **No** vacíes cachés del kernel (`drop_caches`) como
   solución: no arregla la causa y empeora el rendimiento.
3. **Si el consumo crece con el tiempo (fuga):** anota el ritmo de crecimiento
   (`ps` cada pocos minutos) y escala a N2/N3 con esa evidencia. Aumentar el
   límite solo retrasa el fallo.
4. **Si el equipo se queda corto de forma legítima (N2):** añadir swap como
   colchón (no sustituye a RAM):

   ```bash
   sudo fallocate -l 2G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
   ```

   En sistemas de ficheros como btrfs hay requisitos adicionales para ficheros
   de swap; consulta la documentación antes de aplicarlo.
5. **Limitar un servicio** para que no tumbe el resto del sistema:

   ```bash
   sudo systemctl set-property nombre.service MemoryMax=1G
   ```

   En Docker: `docker update --memory 512m --memory-swap 512m nombre`.

## Verificación

```bash
free -h
journalctl -k --since "10 min ago" --no-pager | grep -i -E 'out of memory|killed process'
systemctl is-active nombre
```

Observa el consumo del proceso durante un rato: si el RSS no deja de crecer, el
problema no está resuelto.

## Escalado

| Nivel | Cuándo | Qué hace |
| --- | --- | --- |
| N1 | Siempre primero | Confirma el OOM, reinicia el servicio, registra hora y proceso, avisa |
| N2 | Se repite; hace falta ajustar límites, swap o dimensionar | Ajusta `MemoryMax`, swap, cachés de la aplicación |
| N3 | Fuga de memoria en la aplicación; rediseño de capacidad | Corrige el código con el equipo de desarrollo |

## Prevención

- Alertas de memoria disponible (< 15 %) y de reinicios repetidos de servicios.
- Límites de memoria por servicio o contenedor, **con** alerta cuando se
  acerquen.
- Pruebas de resistencia (larga duración) antes de desplegar.
- No ocultar fallos con reinicios automáticos sin alerta.
