# Nota de escalado de ticket

Rellénala **antes** de pasar un ticket a otro nivel, para que N2/N3 no tengan
que repetir tu diagnóstico. Si no puedes completar un campo, escribe «no
comprobado» en lugar de dejarlo en blanco.

## Cabecera

| Campo | Valor |
| --- | --- |
| Ticket | [Identificador] |
| Escala de | [N1 / N2] a [N2 / N3 / Seguridad] |
| Fecha y hora (con zona horaria) | [AAAA-MM-DD hh:mm TZ] |
| Prioridad | [P1 / P2 / P3 / P4 y criterio] |
| Quién escala | [Nombre] |

## 1. Resumen en una frase

[Qué está fallando y a quién afecta. Ejemplo: «El servicio X no responde desde
las 10:15; afecta a todos los usuarios de Y».]

## 2. Impacto

- **Afectados:** [número y tipo de usuarios o sistemas]
- **Desde cuándo:** [primera aparición conocida]
- **Estado actual:** [caído / degradado / intermitente]
- **Alternativa temporal:** [si existe]

## 3. Qué se ha comprobado

| Comprobación | Comando o acción | Resultado |
| --- | --- | --- |
| [Qué se miró] | [Comando exacto] | [Salida relevante, copiada literal] |

## 4. Qué se ha intentado

- [Acción y resultado, con hora]

## 5. Qué se sospecha

[Hipótesis y por qué; deja claro qué es un hecho y qué una suposición.]

## 6. Motivo del escalado

[Criterio del runbook que se cumple: falta de permisos, riesgo para los datos,
no hay solución segura en N1, incumplimiento de plazo, sospecha de seguridad…]

## 7. Qué se pide

[Acción concreta: «Ampliar el volumen de /var», «Revisar la configuración de
nginx», «Investigar posibles accesos no autorizados».]

## 8. Datos adjuntos

- [Logs, capturas y enlaces. **Sin contraseñas, claves ni datos personales.**]

## 9. Comunicación con el usuario

- Último aviso al usuario: [hora y contenido]
- Próxima actualización prometida: [hora]
