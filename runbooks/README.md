# Runbooks

Un runbook es una guía paso a paso para atender un tipo de incidencia. Estos
están escritos para quien trabaja en soporte N1/N2 sobre Linux
(Debian/Ubuntu y Arch). Todos siguen la misma estructura para que sean fáciles
de seguir bajo presión.

## Índice

| Runbook | Cuándo usarlo | Evidencia |
| --- | --- | --- |
| [Disco lleno](disco-lleno.md) | `No space left on device`, partición al 100 % | [Postmortem 01](../postmortems/01-disco-lleno-log-sin-rotacion.md) |
| [Servicio caído](servicio-caido.md) | Un servicio no responde o está parado | [Postmortem 02](../postmortems/02-recarga-nginx-config-invalida.md) |
| [Alta carga / CPU](alta-carga-cpu.md) | Lentitud, *load average* alto | Comandos comprobados |
| [Memoria agotada / OOM](memoria-agotada-oom.md) | Procesos matados, código 137, swap saturado | [Postmortem 03](../postmortems/03-oom-fuga-de-memoria.md) |
| [Fallo de resolución DNS](fallo-dns.md) | «No abre ninguna web», `Could not resolve host` | [Postmortem 04](../postmortems/04-fallo-resolucion-dns.md) |
| [Certificado TLS caducado](certificado-tls-caducado.md) | Advertencias de certificado, APIs que rechazan TLS | Comandos comprobados |
| [Backup fallido](backup-fallido.md) | Falta el backup, error o fichero inválido | Comandos comprobados |
| [Usuario bloqueado / contraseña](usuario-bloqueado.md) | Cuenta bloqueada, contraseña caducada | Comandos comprobados |
| [SSH inaccesible](ssh-inaccesible.md) | No se puede entrar por SSH | Comandos comprobados |
| [Base de datos lenta](base-de-datos-lenta.md) | Consultas lentas, conexiones agotadas | Consultas PostgreSQL comprobadas |

«Comandos comprobados» significa que se ejecutaron en un contenedor o entorno
de prueba, **no** que se haya reproducido un incidente. El detalle y las
limitaciones están en la [verificación de comandos](../docs/verificacion-comandos.md).

## Estructura común

Cada runbook contiene:

1. **Síntomas:** cómo se manifiesta el problema.
2. **Impacto:** a quién y a qué afecta.
3. **Diagnóstico rápido (N1):** comandos para localizar la causa.
4. **Resolución:** pasos, de los más seguros a los más delicados.
5. **Verificación:** cómo confirmar que está resuelto.
6. **Escalado:** qué hace cada nivel (N1, N2, N3) y cuándo escalar.
7. **Prevención:** qué cambiar para que no se repita.

Para crear uno nuevo, parte de la [plantilla de runbook](../templates/runbook.md).
Si no sabes por dónde empezar, lee antes la [guía N1/N2](../docs/guia-n1-n2.md).

## Convenciones

- Los comandos con `sudo` requieren privilegios; los que no, no.
- Donde Debian/Ubuntu y Arch difieren (nombres de servicio, gestor de
  paquetes) se indica; el servicio SSH, por ejemplo, es `ssh` en Debian/Ubuntu y
  `sshd` en Arch.
- Los nombres de servicios, rutas y usuarios son ejemplos: sustitúyelos.
- Ningún comando destructivo se presenta como seguro: se avisa y se pide
  autorización de N2.
