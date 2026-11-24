# Runbook: [Nombre del escenario]

| Campo | Valor |
| --- | --- |
| Gravedad típica | [Baja / Media / Alta / Crítica y por qué] |
| Se aplica a | [Distribuciones y versiones; servicios concretos] |
| Verificación | [Qué se reprodujo o comprobó de verdad y qué no; enlace a la evidencia] |

## Síntomas

- [Qué ve el usuario o el monitor]
- [Mensajes de error literales]

## Impacto

[A quién y a qué afecta; qué empeora si no se actúa.]

## Diagnóstico rápido (N1)

```bash
# 1. [Qué pregunta responde este comando]
comando

# 2. [...]
comando
```

[Cómo interpretar los resultados: qué significa cada caso.]

## Resolución

[Pasos ordenados de lo más seguro a lo más delicado. Marca los comandos
destructivos y di quién puede autorizarlos.]

1. [Paso]
2. [Paso]

## Verificación

```bash
# [Cómo confirmar que está resuelto]
comando
```

[Qué observar durante los siguientes minutos.]

## Escalado

| Nivel | Cuándo | Qué hace |
| --- | --- | --- |
| N1 | [Siempre primero] | [Diagnostica, aplica correcciones seguras, documenta] |
| N2 | [Criterio concreto para escalar] | [Acciones de administración] |
| N3 | [Causa en diseño, código o capacidad] | [Corrección de fondo] |

[Condiciones de escalado inmediato.]

## Prevención

- [Cambio de configuración, monitorización o proceso que evita la repetición]
