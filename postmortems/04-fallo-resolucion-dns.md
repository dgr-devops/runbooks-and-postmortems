# Postmortem 04 — Fallo de resolución DNS por un resolvedor inalcanzable

> **Incidente simulado en laboratorio.** Este incidente no ocurrió en
> producción ni afectó a ningún usuario, empresa o cliente. Lo provoqué a
> propósito en un contenedor Docker de mi equipo para practicar el diagnóstico
> y documentarlo. Los comandos y las salidas son reales (ver
> [evidencia completa](evidencias/04-dns.log)); los tiempos son los del ensayo
> y no representan un servicio real.

| Campo | Valor |
| --- | --- |
| Fecha del ensayo | 2026-11-24 |
| Entorno | Contenedor `ubuntu:24.04` con `dnsutils` instalado |
| Script | [`lab/04-dns.sh`](../lab/04-dns.sh) |
| Gravedad (ficticia) | SEV2 — la máquina no resuelve nombres |
| Runbook relacionado | [Fallo de resolución DNS](../runbooks/fallo-dns.md) |

## Resumen

Se cambió el resolvedor de la máquina (`/etc/resolv.conf`) a `192.0.2.53`, una
dirección del rango reservado para documentación (TEST-NET-1) que no responde a
nadie. A partir de ese momento todas las resoluciones de nombre tardaron 20
segundos y fallaron, aunque la conectividad IP funcionaba. Se diagnosticó
separando «red» de «DNS» y se resolvió apuntando a un resolvedor que sí
responde.

## Impacto

- **Ensayo:** cada resolución de nombre falló tras 20 s de espera; cualquier
  servicio que dependa de nombres (web, base de datos remota, APIs) habría
  parecido «colgado» antes de dar error.
- **Usuarios afectados:** ninguno; es un laboratorio.
- **Conectividad IP:** intacta durante todo el ensayo.

## Cronología

Horas del equipo anfitrión (CET, UTC+1).

| Hora | Evento |
| --- | --- |
| 09:21:25 | Se crea el contenedor y se instala `dig` (DNS normal) |
| 09:21:41 | Línea base: `getent hosts example.com` responde en 0,043 s |
| 09:21:41 | **T0:** `resolv.conf` pasa a `nameserver 192.0.2.53` |
| 09:21:41 | **T1:** síntoma: `getent hosts example.com` tarda 20 s y falla (código 2) |
| 09:22:02 | Diagnóstico 1: la conexión TCP directa a una IP (1.1.1.1:443) funciona |
| 09:22:02 | Diagnóstico 2: `dig @192.0.2.53` → «no servers could be reached» |
| 09:22:04 | Diagnóstico 3: `dig @1.1.1.1` devuelve direcciones |
| 09:22:04 | Resolución: `nameserver 1.1.1.1`; `getent` responde en 0,024 s |

## Qué se ejecutó y qué se vio

### Síntoma

```text
(lab-dns)$ grep ^nameserver /etc/resolv.conf
nameserver 192.0.2.53
(lab-dns)$ time getent hosts example.com

real	0m20.021s
user	0m0.000s
sys	0m0.002s
(código de salida: 2)
```

Los 20 s son coherentes con los valores por defecto del resolvedor de glibc
(5 s de espera y 2 intentos por consulta), pero no desglosé de dónde sale
exactamente cada segundo; no lo he configurado yo.

### Diagnóstico: separar red de DNS

```text
(lab-dns)$ timeout 5 bash -c "echo > /dev/tcp/1.1.1.1/443" && echo "TCP a 1.1.1.1:443 OK"
TCP a 1.1.1.1:443 OK
(lab-dns)$ dig @192.0.2.53 example.com +time=2 +tries=1 | tail -n 4
; <<>> DiG 9.18.39-0ubuntu0.24.04.9-Ubuntu <<>> @192.0.2.53 example.com +time=2 +tries=1
; (1 server found)
;; global options: +cmd
;; no servers could be reached
(lab-dns)$ dig @1.1.1.1 example.com A +short +time=3 +tries=3
172.66.147.243
104.20.23.154
```

Conclusión: la red funciona (hay conexión por IP), el servidor DNS configurado
no responde, y otro servidor DNS sí. El problema es el resolvedor configurado,
no la red ni el dominio.

### Resolución y verificación

```text
(lab-dns)$ echo "nameserver 1.1.1.1" > /etc/resolv.conf; grep ^nameserver /etc/resolv.conf
nameserver 1.1.1.1
(lab-dns)$ time getent hosts example.com
2606:4700:10::ac42:93f3 example.com
2606:4700:10::6814:179a example.com

real	0m0.024s
```

## Causa raíz

El resolvedor configurado en la máquina era una dirección sin servidor DNS
detrás. En el ensayo lo causé editando `resolv.conf`; en la vida real las
causas típicas son un DHCP que reparte un DNS equivocado, un servidor DNS
interno caído o una regla de cortafuegos que bloquea el puerto 53.

## Observación sobre el propio diagnóstico

En una ejecución anterior del mismo script, la consulta `dig @1.1.1.1 ...
+tries=1` agotó el tiempo aunque 1.1.1.1 respondía con normalidad (lo
comprobé justo después con otras consultas). Una única consulta UDP perdida no
es concluyente: antes de afirmar que un servidor DNS está caído conviene
repetir la prueba y comparar con otro resolvedor. Por eso el script usa
`+tries=3` en esa comprobación y esta es la ejecución que documento. No investigué
por qué se perdió esa consulta concreta.

## Qué fue bien

- Probar la conexión por IP primero permitió descartar la red en un paso.
- Consultar los dos servidores DNS con `dig @servidor` aisló el problema.
- La verificación comparó el tiempo antes y después (20 s frente a 0,02 s).

## Qué fue mal

- El síntoma de partida («no abre ninguna web») es ambiguo; sin el método de
  separar IP de nombres se puede perder mucho tiempo mirando el cortafuegos o
  la aplicación.
- La falta de un DNS secundario hizo que un solo fallo bloqueara toda la
  resolución.

## Acciones

| Acción | Tipo | Estado |
| --- | --- | --- |
| Configurar un segundo resolvedor de respaldo | Prevención | Propuesta |
| Prueba de resolución periódica (cron) con alerta | Detección | Propuesta, sin implementar |
| Documentar el método «IP → servidor DNS → otro servidor DNS» | Proceso | Hecho en [Fallo de resolución DNS](../runbooks/fallo-dns.md) |

## Límites de este ensayo

El laboratorio edita `/etc/resolv.conf` dentro de un contenedor. En un
servidor real con `systemd-resolved` o `NetworkManager`, ese fichero lo
gestionan ellos y editarlo a mano se pierde; el runbook explica cómo
comprobarlo con `resolvectl status`, pero **esa parte no la he reproducido** en
este ensayo.

## Cómo reproducirlo

```bash
bash lab/04-dns.sh > salida.log 2>&1
```

Requiere Docker, la imagen `ubuntu:24.04` y acceso a Internet (instala
`dnsutils` con `apt` y consulta a `1.1.1.1`).
