# Runbook: Servicio caído

| Campo | Valor |
| --- | --- |
| Gravedad típica | Alta a crítica, según el servicio |
| Se aplica a | Servicios gestionados por systemd en Debian/Ubuntu y Arch; ver también la nota de Docker |
| Verificación | Reproducido en laboratorio con nginx en Docker: [Postmortem 02](../postmortems/02-recarga-nginx-config-invalida.md). Los comandos de systemd no se reprodujeron como incidente |

## Síntomas

- Los usuarios reciben «conexión rechazada», `502`/`503` o tiempos de espera.
- El monitor marca el servicio como caído.
- `systemctl status` muestra `inactive`, `failed` o `activating (auto-restart)`.

## Impacto

El servicio afectado y todo lo que dependa de él. Define primero **qué
usuarios y qué funciones** están afectados: eso fija la prioridad (ver la
[guía N1/N2](../docs/guia-n1-n2.md)).

## Diagnóstico rápido (N1)

```bash
# 1. Estado y última salida del servicio (sustituye nginx por el tuyo)
systemctl status nginx --no-pager -l

# 2. Logs recientes del servicio
journalctl -u nginx -n 50 --no-pager
journalctl -u nginx --since "30 min ago" --no-pager

# 3. ¿Qué más ha fallado en el sistema?
systemctl --failed

# 4. ¿Escucha en el puerto esperado? ¿Lo ocupa otro proceso?
sudo ss -tlnp | grep ':80 '

# 5. Valida la configuración antes de reiniciar
sudo nginx -t              # apache: sudo apachectl configtest · ssh: sudo sshd -t

# 6. Causas externas frecuentes
df -h                      # disco lleno
free -h                    # memoria
journalctl -k --since "1 hour ago" --no-pager | grep -i -E 'oom|killed process'
```

Nota: en Debian/Ubuntu el servicio SSH se llama `ssh`; en Arch, `sshd`.

### Si el servicio corre en Docker

```bash
docker ps -a --filter name=nombre
docker logs --tail 50 nombre
docker inspect nombre --format 'ExitCode={{.State.ExitCode}} OOMKilled={{.State.OOMKilled}}'
```

## Resolución

1. **Configuración inválida** (`nginx -t` o equivalente falla): restaura la
   última configuración buena, valida de nuevo y arranca. Es lo que ocurrió en
   el postmortem 02.
2. **Límite de reinicios alcanzado** (`start request repeated too quickly`):
   corrige la causa y después limpia el contador:

   ```bash
   sudo systemctl reset-failed nginx
   ```

3. **Puerto ocupado:** identifica el proceso con `ss -tlnp`, no lo mates sin
   saber qué es; escala a N2 si es otro servicio de producción.
4. **Disco lleno o memoria agotada:** pasa a los runbooks
   [Disco lleno](disco-lleno.md) o [Memoria agotada](memoria-agotada-oom.md).
5. **Sin causa clara y con permiso para reiniciar:**

   ```bash
   sudo systemctl restart nginx
   ```

   Antes de reiniciar, guarda los logs (`journalctl -u nginx > /tmp/nginx-$(date +%F-%H%M).log`)
   por si hay que investigar después.

## Verificación

```bash
systemctl is-active nginx          # debe responder: active
sudo ss -tlnp | grep ':80 '
curl -sS -o /dev/null -w '%{http_code}\n' http://localhost/
journalctl -u nginx -n 20 --no-pager
```

Comprueba también desde fuera del servidor y confirma con quien lo reportó.
Vigila 10-15 minutos que no vuelva a caer.

## Escalado

| Nivel | Cuándo | Qué hace |
| --- | --- | --- |
| N1 | Siempre primero | Diagnostica, valida configuración, reinicia si el procedimiento lo permite, documenta |
| N2 | El reinicio no lo levanta; hay error de configuración que no entiendes; el servicio vuelve a caer; hay dependencias (BD, red) | Analiza logs en profundidad, revierte cambios, corrige dependencias |
| N3 | Defecto de la aplicación, fallo de arquitectura o incidente repetido | Corrige el código/diseño con el equipo propietario |

Escala de inmediato si es un servicio crítico y el primer reinicio no lo
recupera, o si hay sospecha de intrusión.

## Prevención

- Validar la configuración (`nginx -t`) y comprobar el código de salida antes de
  cada recarga.
- Configuración en control de versiones para poder revertir.
- Monitorización con comprobación activa (HTTP, puerto) y alerta.
- `Restart=on-failure` en la unidad de systemd con límites razonables, **y**
  alerta por reinicios repetidos para que no escondan el problema.
