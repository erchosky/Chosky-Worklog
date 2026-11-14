# Modelo de datos

El esquema v1 está en `WorklogDatabase.schemaV1`. Incluye:

- clientes, proyectos, tareas, etiquetas y tarifas;
- sesiones, segmentos, pausas, AFK y ajustes manuales;
- capturas, archivos, enlaces a ActivityWatch y entregables;
- informes e ítems protegidos;
- perfiles, tokens y accesos compartidos;
- ajustes, auditoría y migraciones.

Todas las relaciones materiales usan claves foráneas. Una restricción parcial
impide dos sesiones activas. Timestamps SQLite son segundos UTC desde epoch; la
zona horaria original se guarda en la sesión. Rutas de capturas e informes son
relativas a Application Support.

Las modificaciones escriben `audit_log` con valor previo/nuevo, motivo,
dispositivo, fecha e indicador manual. Las imágenes eliminadas se mueven
primero a `Trash`, permitiendo recuperación manual.
