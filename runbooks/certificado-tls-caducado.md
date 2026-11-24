# Runbook: Certificado TLS caducado o a punto de caducar

| Campo | Valor |
| --- | --- |
| Gravedad típica | Alta (los navegadores bloquean el sitio; fallan las APIs) |
| Se aplica a | Debian/Ubuntu y Arch; ejemplos con nginx y certbot |
| Verificación | Comandos comprobados en contenedor con un certificado autofirmado de prueba (ver [verificación de comandos](../docs/verificacion-comandos.md)); no reproducido como incidente; la renovación con certbot no se probó |

## Síntomas

- El navegador muestra «Su conexión no es privada» / `NET::ERR_CERT_DATE_INVALID`.
- `curl` falla con `SSL certificate problem: certificate has expired`.
- Las integraciones y APIs que consumen el servicio dejan de funcionar.

## Impacto

Los usuarios no pueden acceder de forma segura (o en absoluto), los clientes
automatizados rechazan la conexión y se pierde confianza en el servicio.

## Diagnóstico rápido (N1)

```bash
# 1. Fechas del certificado que sirve realmente el servidor
echo | openssl s_client -connect ejemplo.com:443 -servername ejemplo.com 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

# 2. ¿Caduca en los próximos 30 días? (código 0 = no caduca; 1 = caduca)
echo | openssl s_client -connect ejemplo.com:443 -servername ejemplo.com 2>/dev/null \
  | openssl x509 -noout -checkend 2592000

# 3. Un fichero de certificado concreto
sudo openssl x509 -in /etc/letsencrypt/live/ejemplo.com/fullchain.pem -noout -enddate

# 4. Con certbot: estado de los certificados y del temporizador de renovación
sudo certbot certificates
systemctl list-timers --no-pager | grep -i certbot
journalctl -u certbot --since "7 days ago" --no-pager | tail -n 30

# 5. Descarta un reloj desviado (un reloj mal puesto «caduca» certificados válidos)
timedatectl
```

Distingue:

- **Caducado:** `notAfter` ya pasó.
- **Renovado en disco pero el servicio sirve el viejo:** el fichero está al día
  y el servicio no lo recargó (paso 3 correcto, paso 1 incorrecto).
- **Cadena incompleta o nombre que no coincide:** el certificado no está
  caducado pero no es válido para ese dominio (SAN/CN) o falta el intermedio.

## Resolución

1. **Si el certificado en disco es válido pero el servicio sirve el viejo:**
   valida y recarga.

   ```bash
   sudo nginx -t && sudo systemctl reload nginx
   ```

2. **Certificados de Let's Encrypt con certbot:**

   ```bash
   sudo certbot renew --dry-run     # prueba sin cambiar nada
   sudo certbot renew               # renueva los que toque
   sudo systemctl reload nginx
   ```

   Si falla, lee el error: validación HTTP-01 bloqueada por el cortafuegos o por
   una redirección, DNS que ya no apunta al servidor, o límite de peticiones.
3. **Certificado comercial o interno:** N1 no lo emite. Abre un ticket a N2
   indicando dominio, fecha de caducidad y dónde se instala (consulta la
   plantilla de [escalado](../templates/nota-escalado-ticket.md)).
4. **Mientras tanto,** informa a los usuarios del impacto; **no** les pidas que
   «ignoren la advertencia» ni desactives la verificación TLS en clientes.

## Verificación

```bash
echo | openssl s_client -connect ejemplo.com:443 -servername ejemplo.com 2>/dev/null \
  | openssl x509 -noout -enddate
curl -sSI https://ejemplo.com | head -n 1
```

La nueva fecha `notAfter` debe ser futura. Verifica desde un equipo externo y
con las integraciones que consumen el servicio.

## Escalado

| Nivel | Cuándo | Qué hace |
| --- | --- | --- |
| N1 | Siempre primero | Diagnostica la fecha, recarga el servicio si el certificado ya está renovado, avisa |
| N2 | Hay que emitir o renovar un certificado, falla certbot, cambia la cadena o el dominio | Renueva, corrige validación ACME, instala el certificado |
| N3 | Rediseñar la gestión de certificados (automatización, PKI interna) | Automatiza y centraliza |

Escala **ya** si el certificado afecta a un servicio de producción y no puedes
renovarlo tú en el acto.

## Prevención

- Renovación automática (temporizador de certbot) **y** alerta de caducidad a 30,
  14 y 7 días.
- Un inventario de certificados con responsable y fecha de caducidad.
- Hook de renovación que recargue el servicio
  (`--deploy-hook "systemctl reload nginx"`).
- Prueba periódica de `certbot renew --dry-run`.
