# Runbooks y postmortems de laboratorio

[![Lint y enlaces](https://github.com/dgr-devops/runbooks-and-postmortems/actions/workflows/ci.yml/badge.svg)](https://github.com/dgr-devops/runbooks-and-postmortems/actions/workflows/ci.yml)

Material de soporte N1/N2 sobre Linux: **runbooks** para los escenarios más
comunes, **postmortems** de incidentes que reproduje en un laboratorio local,
plantillas y una guía de triaje y escalado.

## Aviso importante: todos los incidentes son simulaciones

> **Ningún incidente de este repositorio es real.** No hay clientes, empresas,
> producciones ni métricas de negocio. Los cuatro postmortems documentan fallos
> que **provoqué yo a propósito** en contenedores Docker de mi equipo para
> practicar el diagnóstico. Los comandos que muestran y sus salidas son reales
> (capturados por scripts que puedes ejecutar), pero los tiempos y el «impacto»
> son los de un ensayo, no los de un servicio en producción.
>
> Este repositorio demuestra cómo diagnostico y documento, no experiencia
> laboral en incidentes reales.

## Contenido

| Carpeta | Qué hay |
| --- | --- |
| [`runbooks/`](runbooks/README.md) | 10 runbooks: disco lleno, servicio caído, alta carga/CPU, memoria/OOM, DNS, certificado TLS, backup fallido, usuario bloqueado, SSH inaccesible y base de datos lenta |
| [`postmortems/`](postmortems/README.md) | 4 postmortems *blameless* de incidentes simulados, con cronología, salida real, causa raíz y acciones |
| [`templates/`](templates/runbook.md) | Plantillas de [runbook](templates/runbook.md), [postmortem](templates/postmortem.md) y [nota de escalado de ticket](templates/nota-escalado-ticket.md) |
| [`docs/`](docs/guia-n1-n2.md) | [Guía N1/N2](docs/guia-n1-n2.md) (triaje, prioridad, comunicación, escalado) y [verificación de comandos](docs/verificacion-comandos.md) |
| [`lab/`](lab/lib.sh) | Scripts que reproducen los incidentes y verifican los comandos |

### Los postmortems

1. [Disco lleno por un log sin rotación](postmortems/01-disco-lleno-log-sin-rotacion.md)
   — por qué borrar un fichero abierto no libera espacio.
2. [Configuración de nginx inválida y caída tras reinicio](postmortems/02-recarga-nginx-config-invalida.md)
   — un fallo latente que solo aparece al reiniciar.
3. [Servicio terminado por falta de memoria](postmortems/03-oom-fuga-de-memoria.md)
   — confirmar un OOM kill y por qué el reinicio automático lo esconde.
4. [Fallo de resolución DNS](postmortems/04-fallo-resolucion-dns.md)
   — separar red de DNS con un método simple.

Cada uno empieza con «Incidente simulado en laboratorio» y enlaza el script que
lo provoca y el log con la salida íntegra (carpeta `postmortems/evidencias/`).

## Qué está verificado y qué no

- **Reproducido de verdad:** los cuatro incidentes de los postmortems (disco
  lleno, recarga de nginx, OOM y DNS), en Docker, en mi equipo.
- **Comandos comprobados:** 79 comprobaciones de los comandos de los runbooks en
  contenedores Ubuntu 24.04, Arch y PostgreSQL 16, más comandos de solo lectura
  en mi equipo. Esto prueba que los comandos funcionan, **no** que los runbooks
  hayan resuelto incidentes reales.
- **CI en GitHub:** el flujo [`ci.yml`](.github/workflows/ci.yml) se ejecutó en
  GitHub Actions y pasó en verde (markdownlint y lychee), además de pasar en
  local antes de subir.
- **No verificado:** firewall (`ufw`, `nftables`), `fail2ban`, `certbot`,
  MySQL/MariaDB, LVM, cambios reales de `systemd-resolved`/NetworkManager,
  `systemctl restart` sobre servicios reales, entre otros.

La lista completa y exacta está en
[`docs/verificacion-comandos.md`](docs/verificacion-comandos.md).

## Cómo reproducir los laboratorios

Requisitos: Docker y, para algunos, acceso a Internet (los scripts instalan
paquetes dentro de contenedores desechables). Ninguno modifica tu sistema ni
necesita privilegios de administrador.

```bash
git clone https://github.com/dgr-devops/runbooks-and-postmortems.git
cd runbooks-and-postmortems

bash lab/01-disco-lleno.sh   > salida-01.log 2>&1   # ~35 s
bash lab/02-recarga-nginx.sh > salida-02.log 2>&1   # ~10 s
bash lab/03-oom.sh           > salida-03.log 2>&1   # ~50 s
bash lab/04-dns.sh           > salida-04.log 2>&1   # ~40 s
bash lab/verificar-comandos.sh > verificacion.log 2>&1   # ~1 min
```

Las marcas de tiempo, los PID y los identificadores serán distintos en tu
ejecución, pero el comportamiento debe ser el mismo. Los scripts eliminan sus
contenedores al terminar. La última sección de `verificar-comandos.sh` ejecuta
comandos de solo lectura de `systemctl`, `journalctl` y `resolvectl` en tu
equipo, y no muestra su salida.

## Integración continua

El flujo [`ci.yml`](.github/workflows/ci.yml) comprueba en cada *push* y *pull
request*:

- Estilo de todos los documentos Markdown con
  [markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2)
  (configuración en [`.markdownlint-cli2.jsonc`](.markdownlint-cli2.jsonc)).
- Que los enlaces (internos y externos) no estén rotos, con
  [lychee](https://github.com/lycheeverse/lychee)
  (configuración en [`lychee.toml`](lychee.toml)).

## Estructura

```text
.
├── README.md
├── LICENSE
├── .github/workflows/ci.yml
├── runbooks/            # 10 runbooks + índice
├── postmortems/         # 4 postmortems + evidencias/ con los logs reales
├── templates/           # runbook, postmortem, nota de escalado
├── docs/                # guía N1/N2 y verificación de comandos
└── lab/                 # scripts de laboratorio (Docker)
```

## Licencia

[MIT](LICENSE) © 2026 Daniel García Rodríguez.
