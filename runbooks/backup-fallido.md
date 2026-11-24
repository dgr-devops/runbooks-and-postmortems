# Runbook: Backup fallido

| Campo | Valor |
| --- | --- |
| Gravedad típica | Media; **alta** si es la única copia o lleva días fallando |
| Se aplica a | Debian/Ubuntu y Arch; ejemplos con cron/timers, `tar` y `rsync` |
| Verificación | Comprobaciones de integridad (`tar -t`, `gzip -t`, `sha256sum -c`) comprobadas en contenedor (ver [verificación de comandos](../docs/verificacion-comandos.md)); no reproducido como incidente |

## Síntomas

- Alerta o correo del trabajo de backup con error, o ausencia del aviso diario.
- Falta el fichero de backup de hoy, o tiene tamaño cero o muy inferior al
  habitual.
- El trabajo termina «bien» pero la restauración de prueba falla.

## Impacto

No hay riesgo inmediato para el servicio, pero se pierde la capacidad de
recuperarse: cada día sin backup válido aumenta la pérdida de datos posible
(RPO). Es una incidencia **silenciosa y acumulativa**.

## Diagnóstico rápido (N1)

```bash
# 1. ¿Se ejecutó el trabajo y cómo terminó? (systemd o cron)
systemctl list-timers --no-pager | grep -i backup
systemctl status backup.service --no-pager
journalctl -u backup.service --since "2 days ago" --no-pager | tail -n 40
journalctl -u cron --since "2 days ago" --no-pager | tail -n 20   # Debian/Ubuntu
journalctl -u cronie --since "2 days ago" --no-pager | tail -n 20 # Arch

# 2. ¿Qué backups existen y qué tamaño tienen?
ls -lht /ruta/backups | head -n 10

# 3. Causas frecuentes: espacio, inodos, montaje, permisos
df -h /ruta/backups
df -i /ruta/backups
findmnt /ruta/backups          # ¿está montado el destino (NFS, disco externo)?
sudo -u usuario_backup test -w /ruta/backups && echo "escritura OK"

# 4. ¿El último backup es válido? (no basta con que exista)
tar -tzf /ruta/backups/ultimo.tar.gz > /dev/null && echo "tar OK"
gzip -t /ruta/backups/ultimo.sql.gz && echo "gzip OK"
sha256sum -c /ruta/backups/ultimo.sha256

# 5. Red/credenciales si el destino es remoto
ssh -o ConnectTimeout=5 usuario@destino true && echo "SSH OK"
```

Sustituye `backup.service` y las rutas por las de tu entorno. Cada organización
nombra distinto sus unidades.

## Resolución

1. **Destino sin espacio:** libera siguiendo el runbook
   [Disco lleno](disco-lleno.md), o aplica la política de retención (borra los
   backups más antiguos **solo** según la política acordada).
2. **Destino no montado:** monta (`sudo mount /ruta/backups`), revisa
   `/etc/fstab` y la red, y **comprueba que no se escribió en el directorio
   local por error** (un backup que cae en el disco local lo llena).
3. **Permisos o credenciales cambiadas:** restablece el acceso con el
   propietario del recurso; no pongas contraseñas en scripts ni en el ticket.
4. **Relanza el trabajo manualmente** una vez corregida la causa:

   ```bash
   sudo systemctl start backup.service
   journalctl -u backup.service -f
   ```

5. **Si la causa está en el propio script o en la base de datos** (fallo de
   `mysqldump`/`pg_dump`, bloqueos): escala a N2 con el mensaje de error exacto.

## Verificación

Un backup solo cuenta si **se puede restaurar**.

```bash
ls -lh /ruta/backups | head -n 5                    # fichero nuevo, tamaño razonable
tar -tzf /ruta/backups/nuevo.tar.gz | head          # lista el contenido
mkdir -p /tmp/restauracion-prueba
tar -xzf /ruta/backups/nuevo.tar.gz -C /tmp/restauracion-prueba
ls /tmp/restauracion-prueba | head
rm -rf /tmp/restauracion-prueba
```

En bases de datos, restaura en una instancia de prueba, nunca sobre producción.

## Escalado

| Nivel | Cuándo | Qué hace |
| --- | --- | --- |
| N1 | Siempre primero | Diagnostica espacio, montaje y permisos, relanza el trabajo, valida el resultado |
| N2 | La causa está en el script, la base de datos, la red o credenciales; el backup falla de forma repetida | Corrige scripts y destinos, valida restauraciones |
| N3 | Rediseñar la estrategia (retención, RPO/RTO, copias fuera del sitio) | Define y automatiza la estrategia |

Escala de inmediato si **no existe ningún backup válido reciente** de datos
críticos.

## Prevención

- Estrategia 3-2-1 (3 copias, 2 soportes, 1 fuera del sitio).
- Alerta por **ausencia** de backup (no solo por error): lo que no se ejecuta
  tampoco avisa.
- Restauraciones de prueba periódicas y documentadas.
- Verificación de integridad (suma de comprobación) tras cada backup.
- Monitorizar espacio del destino y aplicar retención automática.
