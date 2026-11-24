# Postmortems

> **Todos los incidentes de esta carpeta son simulaciones de laboratorio.**
> No describen ninguna caída real, ni una empresa, ni un cliente. Los provoqué
> yo en contenedores Docker en mi equipo para practicar y documentar.

Cada postmortem sigue el formato *blameless* (sin culpables): se centra en qué
falló en el sistema y el proceso, no en quién. Incluye los comandos que
ejecuté y su salida real, capturada por un script reproducible.

## Índice

| Nº | Incidente | Qué demuestra | Script | Evidencia |
| --- | --- | --- | --- | --- |
| 01 | [Disco lleno por un log sin rotación](01-disco-lleno-log-sin-rotacion.md) | Por qué `rm` no libera espacio de un fichero abierto; rotación con `logrotate` | [`01-disco-lleno.sh`](../lab/01-disco-lleno.sh) | [log](evidencias/01-disco-lleno.log) |
| 02 | [Configuración de nginx inválida y caída tras reinicio](02-recarga-nginx-config-invalida.md) | Un fallo de configuración que solo aparece en el siguiente reinicio | [`02-recarga-nginx.sh`](../lab/02-recarga-nginx.sh) | [log](evidencias/02-recarga-nginx.log) |
| 03 | [Servicio terminado por falta de memoria (OOM)](03-oom-fuga-de-memoria.md) | Cómo confirmar un OOM kill y por qué los reinicios automáticos lo esconden | [`03-oom.sh`](../lab/03-oom.sh) | [log](evidencias/03-oom.log) |
| 04 | [Fallo de resolución DNS](04-fallo-resolucion-dns.md) | Separar red de DNS; un resolvedor inalcanzable | [`04-dns.sh`](../lab/04-dns.sh) | [log](evidencias/04-dns.log) |

## Reglas que sigo al escribirlos

- Ponen «Incidente simulado en laboratorio» al principio.
- Solo incluyen comandos y salidas que ejecuté de verdad; los tiempos son los
  del ensayo y no representan tiempos de respuesta humanos.
- Si algo no funcionó como esperaba (por ejemplo, que `nginx -s reload`
  rechazara la configuración inválida en lugar de aplicarla), lo cuento tal como
  fue.
- Señalan lo que **no** pude verificar.
- No inventan clientes, empresas, importes ni métricas de negocio.

Para escribir uno nuevo, usa la [plantilla de postmortem](../templates/postmortem.md).
