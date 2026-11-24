# Runbook: Usuario bloqueado / restablecer contraseña

| Campo | Valor |
| --- | --- |
| Gravedad típica | Baja a media (afecta a una persona), salvo cuentas de servicio o sospecha de ataque |
| Se aplica a | Cuentas locales en Debian/Ubuntu y Arch con PAM |
| Verificación | Comandos comprobados en contenedor con un usuario de prueba (ver [verificación de comandos](../docs/verificacion-comandos.md)); no reproducido como incidente. LDAP, SSSD y Active Directory no se cubren |

## Síntomas

- «Permission denied» o «Authentication failure» aunque la persona usa su
  contraseña.
- La cuenta aparece bloqueada tras varios intentos fallidos.
- La contraseña ha caducado y el sistema obliga a cambiarla.
- La cuenta ha caducado o tiene una shell `nologin`.

## Impacto

Una persona no puede trabajar. Si la cuenta es de servicio, puede parar un
proceso automatizado.

## Antes de tocar nada: verifica la identidad

**No restablezcas ni desbloquees una cuenta solo porque alguien lo pide por
chat o correo.** Sigue el procedimiento de identificación de tu organización
(llamada de vuelta a un número conocido, aprobación del responsable, ticket
validado). Los intentos de «suplantación para recuperar la cuenta» son una
técnica habitual de ingeniería social.

## Diagnóstico rápido (N1)

```bash
USUARIO=nombre

# 1. ¿Existe? ¿qué shell y grupos tiene?
getent passwd "$USUARIO"
id "$USUARIO"

# 2. Estado de la contraseña: L = bloqueada, P = utilizable, NP = sin contraseña
sudo passwd -S "$USUARIO"

# 3. Caducidad de contraseña y de cuenta
sudo chage -l "$USUARIO"

# 4. Bloqueo por intentos fallidos (pam_faillock)
sudo faillock --user "$USUARIO"

# 5. Intentos recientes: ¿son legítimos o parecen un ataque?
sudo lastb | head -n 10
last "$USUARIO" | head -n 5
sudo journalctl -u ssh --since "1 hour ago" --no-pager | grep -i "$USUARIO" | tail -n 15
```

En Arch el servicio SSH se llama `sshd`. Si hay muchos intentos fallidos desde
direcciones desconocidas, **no es un simple olvido de contraseña**: ve al
apartado de escalado.

## Resolución

1. **Bloqueo por intentos fallidos:**

   ```bash
   sudo faillock --user "$USUARIO" --reset
   ```

2. **Cuenta bloqueada administrativamente** (`passwd -S` muestra `L`): solo
   desbloquéala si sabes por qué se bloqueó:

   ```bash
   sudo passwd -u "$USUARIO"
   ```

   Si la cuenta **no tiene contraseña** (nunca se le asignó una), `passwd -u`
   se niega con «unlocking the password would result in a passwordless
   account». En ese caso asigna primero una contraseña (paso 3) en lugar de
   forzar el desbloqueo.

3. **Restablecer la contraseña.** Hazlo de forma interactiva (nunca pongas la
   contraseña en la línea de comandos, en el chat ni en el ticket) y obliga a
   cambiarla en el primer acceso:

   ```bash
   sudo passwd "$USUARIO"
   sudo chage -d 0 "$USUARIO"
   ```

   Entrega la contraseña temporal por un canal distinto al del ticket.
4. **Contraseña o cuenta caducada:** si procede según la política,

   ```bash
   sudo chage -E -1 "$USUARIO"       # quita la fecha de caducidad de la cuenta
   ```

5. **Acceso por clave SSH que falla:** revisa permisos (`~/.ssh` 700,
   `authorized_keys` 600, propietario correcto), no la contraseña.

## Verificación

```bash
sudo passwd -S "$USUARIO"
sudo faillock --user "$USUARIO"      # sin intentos fallidos registrados
sudo chage -l "$USUARIO"
```

Pide a la persona que inicie sesión mientras sigues el log
(`journalctl -f`) y confirma el cambio de contraseña obligatorio.

## Escalado

| Nivel | Cuándo | Qué hace |
| --- | --- | --- |
| N1 | Cuenta local, identidad verificada, causa clara | Desbloquea, restablece, verifica |
| N2 | Cuenta de servicio, administrador o privilegiada; directorio central (LDAP/AD); no se desbloquea | Corrige PAM/SSSD, revisa accesos |
| Seguridad / N3 | Muchos intentos fallidos desde IP desconocidas, accesos a horas raras, solicitudes sospechosas | Investiga posible compromiso; rotación de credenciales |

**Escala sin desbloquear** si hay indicios de ataque o si la petición no se
puede verificar.

## Prevención

- Política de contraseñas y MFA donde sea posible.
- Autoservicio de restablecimiento verificado.
- Bloqueo de IP por intentos repetidos (p. ej. `fail2ban`).
- Auditar cuentas inactivas y caducar las de personas que se van.
