# Runbook: Fallo de resolución DNS

| Campo | Valor |
| --- | --- |
| Gravedad típica | Alta (todo lo que usa nombres parece caído) |
| Se aplica a | Debian/Ubuntu y Arch |
| Verificación | Reproducido en laboratorio con Docker: [Postmortem 04](../postmortems/04-fallo-resolucion-dns.md). La gestión con `systemd-resolved`/NetworkManager no se reprodujo |

## Síntomas

- «No abre ninguna web» pero se puede acceder por IP.
- Errores `Temporary failure in name resolution`, `Name or service not known`
  o `Could not resolve host`.
- Las resoluciones tardan muchos segundos antes de fallar.

## Impacto

Cualquier servicio que dependa de nombres: aplicaciones web, APIs, bases de
datos remotas, correo, actualizaciones de paquetes.

## Diagnóstico rápido (N1)

El método: **IP → servidor DNS configurado → otro servidor DNS.**

```bash
# 1. ¿Hay red? Prueba por IP, sin nombres
ping -c 2 1.1.1.1
ip route                       # ¿hay ruta por defecto?

# 2. ¿Qué resolvedor usa esta máquina?
cat /etc/resolv.conf
ls -l /etc/resolv.conf         # ¿es un enlace a systemd-resolved?
resolvectl status              # si usa systemd-resolved

# 3. Resolución como la hacen las aplicaciones (respeta /etc/hosts y nsswitch)
time getent hosts example.com

# 4. Pregunta directamente a cada servidor DNS (paquete dnsutils / bind en Arch)
dig @IP_DEL_RESOLVEDOR example.com +time=2 +tries=3
dig @1.1.1.1 example.com +short +time=3 +tries=3

# 5. Comprueba que no hay una entrada local que lo falsee
grep -n example.com /etc/hosts
grep '^hosts:' /etc/nsswitch.conf
```

Si el nombre falla con tu resolvedor pero funciona con otro, el problema es el
resolvedor. **Repite las pruebas**: una sola consulta UDP perdida no es
concluyente (ver el postmortem 04).

Si solo falla **un** dominio y los demás resuelven, el fallo está en ese
dominio (registros, caducidad, delegación): comprueba con
`dig +trace nombre` y escala a N2.

## Resolución

1. **El resolvedor configurado no responde:** corrige el origen de la
   configuración. En equipos con `systemd-resolved` o NetworkManager no edites
   `/etc/resolv.conf` a mano (se sobrescribe); cambia el DNS en la configuración
   de red:

   ```bash
   resolvectl status
   nmcli device show | grep -i dns     # con NetworkManager
   ```

2. **Servicio de resolución parado:**

   ```bash
   sudo systemctl restart systemd-resolved
   ```

3. **Caché con datos viejos:**

   ```bash
   sudo resolvectl flush-caches
   ```

4. **Solución temporal para un único servicio crítico (N2):** añadir la
   entrada en `/etc/hosts` documentando quién y cuándo, y eliminarla después.
5. **Fallo del servidor DNS corporativo:** escala a N2 de red; mientras tanto,
   un resolvedor público alternativo solo si la política lo permite.

## Verificación

```bash
time getent hosts example.com        # debe responder en milisegundos
dig example.com +short
curl -sS -o /dev/null -w '%{http_code}\n' https://example.com
```

Prueba también un nombre interno si lo hay, y confirma con el usuario afectado.

## Escalado

| Nivel | Cuándo | Qué hace |
| --- | --- | --- |
| N1 | Siempre primero | Separa red de DNS, identifica el resolvedor que falla, aplica el arreglo local autorizado |
| N2 | Falla el DNS corporativo o un dominio concreto; hay que cambiar configuración de red/DHCP/DNS | Corrige servidores DNS, DHCP, zonas, reglas de cortafuegos al puerto 53 |
| N3 | Fallo de diseño de la resolución, DNSSEC o delegaciones complejas | Rediseña y coordina con proveedores |

## Prevención

- Al menos dos servidores DNS configurados.
- Prueba de resolución periódica con alerta.
- Revisar qué reparte el DHCP y vigilar cambios en `/etc/resolv.conf`.
- Registrar los dominios con aviso de caducidad.
