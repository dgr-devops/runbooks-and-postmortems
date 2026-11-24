# Runbook: Disco lleno

| Campo | Valor |
| --- | --- |
| Gravedad típica | Alta (los servicios dejan de escribir y pueden caer) |
| Se aplica a | Debian/Ubuntu y Arch (los comandos distintos están marcados) |
| Verificación | Reproducido en laboratorio: [Postmortem 01](../postmortems/01-disco-lleno-log-sin-rotacion.md) |

## Síntomas

- Errores `No space left on device` en logs de aplicaciones o en la consola.
- Servicios que no arrancan, bases de datos que pasan a solo lectura o
  aplicaciones que no pueden guardar ficheros.
- `df -h` muestra una partición al 100 %. También puede fallar por **inodos**
  agotados aunque haya espacio libre.

## Impacto

Pérdida o corrupción de datos recientes, caída de servicios que escriben en
disco y, si la partición es `/`, imposibilidad de iniciar sesión o de usar
`apt`/`pacman`.

## Diagnóstico rápido (N1)

```bash
# 1. ¿Qué partición está llena? ¿De espacio o de inodos?
df -hT
df -i

# 2. ¿Qué directorios ocupan más? (-x no cruza a otros sistemas de ficheros)
sudo du -xh / --max-depth=1 2>/dev/null | sort -h | tail -n 10

# 3. Ficheros grandes en esa partición (ajusta la ruta)
sudo find /var -xdev -type f -size +200M -exec ls -lh {} + 2>/dev/null

# 4. Ficheros borrados que algún proceso mantiene abiertos
sudo lsof +L1

# 5. Candidatos habituales
sudo du -sh /var/log /var/cache /var/lib/docker 2>/dev/null
journalctl --disk-usage
```

Si `df -h` muestra poco uso pero `df -i` marca 100 %, el problema son los
inodos (muchísimos ficheros pequeños). Localiza el directorio con:

```bash
sudo find /var -xdev -printf '%h\n' | sort | uniq -c | sort -nr | head -n 10
```

## Resolución

Antes de borrar nada: **identifica qué es y quién lo escribe**. No borres datos
de aplicaciones ni bases de datos sin consultar a N2.

1. **Logs del sistema (journal).** Es seguro reducirlo:

   ```bash
   sudo journalctl --vacuum-size=200M
   ```

2. **Caché de paquetes.**

   ```bash
   # Debian/Ubuntu
   sudo apt-get clean
   sudo apt-get autoremove --purge
   # Arch (requiere pacman-contrib para paccache)
   sudo paccache -rk2
   ```

3. **Un log concreto que crece sin control.** Si el proceso lo tiene abierto,
   **no uses `rm`**: no libera espacio (ver el postmortem). Vacíalo en su sitio:

   ```bash
   sudo truncate -s 0 /var/log/app/app.log
   ```

   Si ya lo borraron y `lsof +L1` lo muestra como `(deleted)`, libera el
   espacio vaciando el descriptor, o reinicia el servicio:

   ```bash
   sudo sh -c ': > /proc/PID/fd/N'     # PID y N salen de lsof +L1
   # o bien
   sudo systemctl restart nombre-del-servicio
   ```

4. **Docker** (solo si N2 lo confirma, borra datos):

   ```bash
   docker system df
   docker image prune        # solo imágenes sin uso
   ```

5. Si no hay nada seguro que borrar: escala a N2 para ampliar el volumen.

## Verificación

```bash
df -h /ruta/afectada
df -i /ruta/afectada
sudo lsof +L1 | head              # no deben quedar ficheros borrados enormes
systemctl --failed                # servicios que fallaron por el disco
```

Reinicia o comprueba los servicios que fallaron y confirma que escriben de
nuevo.

## Escalado

| Nivel | Cuándo | Qué hace |
| --- | --- | --- |
| N1 | Siempre primero | Diagnostica, libera espacio **seguro** (caché de paquetes, journal, logs rotados) y avisa |
| N2 | No hay espacio seguro que liberar; el crecimiento continúa; hay que tocar datos de aplicaciones o ampliar volúmenes (LVM, disco) | `lvextend -r`, mueve datos, corrige la rotación de logs |
| N3 | El crecimiento revela un fallo de diseño o de aplicación (fuga de logs, retención infinita) | Rediseña retención y capacidad con el equipo propietario |

Escala **ya** si la partición afectada es la de la base de datos, `/` está al
100 % en producción o no sabes qué es lo que ocupa el espacio.

## Prevención

- Rotación de logs con `logrotate` (`rotate`, `size`, `compress`; usar
  `copytruncate` si la aplicación no reabre el fichero).
- Límites del journal (`SystemMaxUse=` en `/etc/systemd/journald.conf`).
- Alertas de uso de disco al 80 % y al 90 %, y de inodos.
- Particiones separadas para `/var/log` y datos, con margen.
- Comprobar `lsof +L1` **antes** de borrar logs en uso.
