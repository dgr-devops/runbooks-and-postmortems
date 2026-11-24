# Guía N1/N2: triaje, prioridad, comunicación y escalado

Guía práctica para atender incidencias en un equipo de soporte por niveles.
Es una síntesis de buenas prácticas habituales (ITIL, gestión de incidentes y
guías SRE públicas) adaptada a mi forma de trabajar; **no** describe el proceso
de ninguna empresa concreta. Los plazos y umbrales son ejemplos orientativos:
cada organización define los suyos.

## 1. Los niveles

| Nivel | Rol | Hace | No hace |
| --- | --- | --- | --- |
| N1 | Primera línea | Recibe, clasifica, diagnostica con runbooks, resuelve lo conocido, comunica y escala bien | Cambios de configuración no documentados, tocar datos de aplicaciones |
| N2 | Administración | Analiza causas, cambia configuraciones, corrige servicios, amplía recursos | Rediseñar arquitectura o corregir código de aplicación |
| N3 | Especialista / ingeniería | Corrige el defecto de fondo, diseña, coordina con desarrollo y proveedores | Atender peticiones rutinarias |

Escalar bien **es** una habilidad de N1: un ticket escalado con diagnóstico
claro ahorra tiempo a todos.

## 2. Triaje: los primeros minutos

Cuando entra una incidencia, responde estas preguntas antes de tocar nada:

1. **¿Qué ocurre exactamente?** Mensaje de error literal, captura, hora.
2. **¿A quién afecta?** Una persona, un equipo, todos los usuarios.
3. **¿Desde cuándo?** ¿Cambió algo antes (despliegue, actualización, cambio de red)?
4. **¿Es reproducible?** ¿Siempre, a veces, solo desde un sitio?
5. **¿Hay un workaround?** ¿Puede seguir trabajando de otra forma?
6. **¿Hay riesgo de seguridad o de pérdida de datos?** Si sí, para y escala.

Después:

1. Busca el runbook que encaje en el [índice](../runbooks/README.md).
2. Registra en el ticket lo que compruebes **mientras** lo compruebas, con la
   hora. Si no está anotado, para el siguiente nivel no ocurrió.
3. Aplica el diagnóstico rápido antes que cualquier solución.
4. Cambia **una cosa cada vez** y comprueba el efecto.

## 3. Prioridad: impacto × urgencia

La prioridad no es «lo que más grita el usuario»: combina **impacto** (a
cuántos y qué afecta) y **urgencia** (cuánto tiempo hay antes de que sea
peor).

| | Urgencia alta (se agrava ya) | Urgencia media | Urgencia baja |
| --- | --- | --- | --- |
| **Impacto alto** (muchos usuarios o servicio crítico) | P1 | P1 / P2 | P2 |
| **Impacto medio** (un equipo, función no crítica) | P2 | P3 | P3 |
| **Impacto bajo** (una persona, hay workaround) | P3 | P4 | P4 |

Ejemplos orientativos de tiempos de primera respuesta (ajústalos al acuerdo de
servicio real): P1 minutos, P2 en menos de una hora, P3 el mismo día
laborable, P4 en pocos días.

Reglas prácticas:

- Un fallo que ocurre en **producción** y afecta a **todos** es P1 aunque sea
  «solo» una pantalla.
- Revisa la prioridad cuando cambien los datos (un P3 que se extiende pasa a P2).
- Si hay riesgo de seguridad o de pérdida de datos, sube la prioridad y avisa.

## 4. Comunicación con el usuario

Una buena comunicación reduce la ansiedad y las llamadas repetidas.

- **Acusa recibo pronto**, aunque aún no tengas diagnóstico: «Hemos recibido su
  incidencia y la estamos revisando».
- **Habla en su lenguaje:** impacto y próximos pasos, no jerga.
- **Di qué sabes, qué no sabes y cuándo volverás a informar.** No prometas una
  hora de resolución que no controlas.
- **Actualiza con la frecuencia prometida**, aunque sea para decir «sin cambios».
- **No culpes** (ni al usuario, ni a otro equipo, ni al proveedor).
- **Cierra confirmando** con la persona que ya funciona.

### Mensajes tipo

Acuse de recibo:

> Hola. Hemos recibido su incidencia sobre [descripción breve]. La estamos
> analizando y le daremos novedades antes de las [hora]. Si necesita trabajar
> mientras tanto, [alternativa si existe].

Actualización de una incidencia mayor:

> Actualización de las [hora]: [servicio] sigue [caído/degradado]. Ya hemos
> identificado [causa o «aún estamos investigando»]. Estamos [acción en curso].
> Próxima actualización a las [hora].

Resolución:

> La incidencia sobre [descripción] está resuelta desde las [hora]. La causa
> fue [explicación sencilla]. Por favor, confirme que todo funciona y avísenos
> si ve algo raro.

### Seguridad en la comunicación

- **Nunca pidas ni aceptes contraseñas** por chat, correo o ticket.
- **Verifica la identidad** antes de restablecer accesos o cambiar datos de una
  cuenta (ver el runbook de [usuario bloqueado](../runbooks/usuario-bloqueado.md)).
- Desconfía de la urgencia inventada («es del director, hazlo ya»): es una técnica
  habitual de ingeniería social.
- Adjunta a los tickets solo la información necesaria, sin datos personales ni
  secretos.

## 5. Cuándo escalar

Escala cuando se cumpla **cualquiera** de estas condiciones:

- **Permisos o alcance:** la solución requiere acceso o decisiones fuera de tu nivel.
- **Riesgo:** puede perderse información, o el cambio puede empeorar el servicio.
- **Seguridad:** hay indicios de intrusión, actividad inusual o petición sospechosa.
- **Tiempo:** estás por encima del plazo de tu nivel o llevas más de ~15-30
  minutos de diagnóstico sin avances en un P1/P2.
- **Falta de conocimiento:** no hay runbook y no entiendes lo que ves.
- **Repetición:** el problema ya ocurrió antes (hay que ir a la causa raíz).
- **Impacto creciente:** afecta a más usuarios de los previstos.

No escales «por si acaso» sin diagnosticar: escala **con** la información
hecha. Y no tardes en escalar por orgullo: en un P1, esperar cuesta más que
pedir ayuda.

### Qué incluir al escalar

Usa la [nota de escalado](../templates/nota-escalado-ticket.md). Como mínimo:

1. Resumen en una frase y prioridad.
2. Impacto y desde cuándo.
3. Qué has comprobado (comandos y resultados) y qué has intentado.
4. Qué sospechas y por qué.
5. Qué pides concretamente.

Ejemplo de resumen bien escrito:

> Servidor de ficheros sin espacio (`/srv` al 100 %) desde las 10:20; afecta a
> todo el departamento. Hemos liberado la caché de paquetes y el journal sin
> efecto. `du` apunta a `/srv/backups` (80 %). Necesitamos autorización para
> mover o purgar copias antiguas, o ampliar el volumen.

## 6. Después de la incidencia

- Cierra el ticket con la **causa**, la **solución** y cómo se comprobó.
- Si faltaba un runbook o estaba incompleto, **actualízalo** (esto es trabajo
  de verdad, no un extra).
- Si la incidencia fue grave o se repite, escribe un
  [postmortem](../postmortems/README.md) sin culpables: qué falló en el sistema
  y el proceso, y qué acciones concretas evitarán la repetición.
- Traspasa los turnos con una nota breve: qué está abierto, qué se probó,
  qué se espera.

## 7. Hábitos que marcan la diferencia

- Anota la hora y el comando de lo que haces; mañana no lo recordarás.
- Antes de un cambio, comprueba cómo volver atrás.
- Una variable cada vez, y confirma el efecto.
- Pregunta pronto; documenta siempre.
- Si no estás seguro de que un comando es seguro, **no lo ejecutes en
  producción**: pruébalo en un entorno de laboratorio.
