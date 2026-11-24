// Aplicación simulada del laboratorio 03.
// Con LEAK distinto de "off" acumula buffers sin límite (fuga de memoria).
// Con LEAK=off conserva como máximo 4 bloques (caché acotada).
const MB = 1024 * 1024;
const chunks = [];
const leak = process.env.LEAK !== 'off';

setInterval(() => {
  chunks.push(Buffer.alloc(4 * MB, 1));
  if (!leak && chunks.length > 4) chunks.shift();
  const rss = Math.round(process.memoryUsage().rss / MB);
  console.log(`${new Date().toISOString()} cache_chunks=${chunks.length} rss=${rss}MB`);
}, 500);
