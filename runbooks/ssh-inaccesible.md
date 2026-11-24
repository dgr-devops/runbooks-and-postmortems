# Runbook: SSH inaccesible

| Campo | Valor |
| --- | --- |
| Gravedad típica | Alta (sin SSH se pierde la administración remota) |
| Se aplica a | Debian/Ubuntu y Arch (el servicio es `ssh` en Debian/Ubuntu y `sshd` en Arch) |
| Verificación | `sshd -t` y comandos de cliente comprobados en contenedor (ver [verificación de comandos](../docs/verificacion-comandos.md)); no reproducido como incidente. Firewall, fail2ban y nube no se probaron |

## Síntomas

- `ssh: connect to host ... port 22: Connection timed out` (nadie responde:
  red o cortafuegos).
- `Connection refused` (el equipo responde pero nada escucha en ese puerto).
- `Permission denied (publickey)` (llega, pero no se autentica).
- `REMOTE HOST IDENTIFICATION HAS CHANGED` (la clave del servidor cambió).

## Impacto

No se puede administrar el equipo de forma remota. Los servicios que corren en
él pueden seguir funcionando; el riesgo es no poder reaccionar si fallan.

## Diagnóstico rápido (N1)

**Desde tu máquina cliente**, de fuera hacia dentro:

```bash
# 1. ¿Resuelve el nombre y hay ruta?
getent hosts servidor.ejemplo.com
ping -c 2 IP_DEL_SERVIDOR
ip route get IP_DEL_SERVIDOR

# 2. ¿Responde el puerto 22?  (timeout = filtrado; refused = nada escucha)
nc -vz -w 5 IP_DEL_SERVIDOR 22

# 3. Detalle de la conexión y de la autenticación
ssh -vvv -o ConnectTimeout=8 usuario@IP_DEL_SERVIDOR
```

**En el servidor** (por consola, KVM o consola del proveedor):

```bash
# 4. ¿Está el servicio vivo? (en Arch: sshd)
systemctl status ssh --no-pager
journalctl -u ssh -n 50 --no-pager

# 5. ¿Escucha en el puerto? ¿La configuración es válida?
sudo ss -tlnp | grep sshd
sudo sshd -t && echo "configuración OK"
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|allowusers|allowgroups) '

# 6. Cortafuegos y bloqueos automáticos
sudo ufw status verbose                    # si usa ufw
sudo nft list ruleset | head -n 60         # nftables
sudo fail2ban-client status sshd           # si usa fail2ban

# 7. Recursos: un disco lleno o memoria agotada impiden iniciar sesión
df -h /
free -h
```

## Resolución

- **Timeout:** cortafuegos, grupo de seguridad de la nube o ruta. Fuera de tu
  alcance en N1 si es red o proveedor: escala con el resultado de `nc` y
  `ping`.
- **Connection refused:** el servicio está parado o escucha en otro puerto.

  ```bash
  sudo sshd -t && sudo systemctl restart ssh      # Arch: sshd
  ```

  Si `sshd -t` falla, **no reinicies**: corrige el error que indica (o revierte
  el último cambio en `/etc/ssh/sshd_config`) y vuelve a validar.
- **IP bloqueada por fail2ban:**

  ```bash
  sudo fail2ban-client set sshd unbanip IP_DEL_CLIENTE
  ```

- **Permission denied (publickey):** comprueba que la clave pública está en
  `~/.ssh/authorized_keys` del usuario, que `~/.ssh` es 700 y
  `authorized_keys` 600 con el propietario correcto, y que `AllowUsers`/
  `AllowGroups` incluyen al usuario. El log del servidor suele indicar la
  causa exacta.
- **Cambió la clave del servidor:** puede ser una reinstalación legítima o un
  ataque de intermediario. **No** ejecutes `ssh-keygen -R` sin confirmar con
  el responsable que el servidor cambió; después elimina la entrada antigua
  con `ssh-keygen -R servidor` y verifica la nueva huella por un canal seguro.

Regla de oro al cambiar la configuración de SSH: **mantén abierta una sesión
activa** mientras pruebas desde otra, y valida con `sshd -t` antes de
recargar.

## Verificación

```bash
ssh -o ConnectTimeout=8 usuario@IP_DEL_SERVIDOR 'hostname; uptime'
sudo ss -tlnp | grep sshd
```

Prueba desde la red/equipo desde el que falló. Confirma con la persona
afectada.

## Escalado

| Nivel | Cuándo | Qué hace |
| --- | --- | --- |
| N1 | Siempre primero | Localiza en qué capa falla (red, puerto, servicio, autenticación), reinicia el servicio si es seguro |
| N2 | Cortafuegos, red o proveedor; configuración dañada; no hay consola | Corrige reglas y configuración, usa consola de recuperación |
| N3 | Cambio de clave inesperado, sospecha de intrusión, rediseño del acceso | Investiga, rota claves y accesos |

Escala de inmediato si no hay otra vía de acceso (consola) y el equipo es crítico.

## Prevención

- Acceso por clave, `PasswordAuthentication no`, sin acceso root directo.
- Consola de emergencia (KVM, consola del proveedor) probada de antemano.
- Cambios de SSH siempre validados con `sshd -t` y con una segunda sesión abierta.
- Monitorizar el puerto 22 desde fuera y alertar si deja de responder.
