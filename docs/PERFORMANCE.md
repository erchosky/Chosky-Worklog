# Rendimiento

Mediciones que el build automatizado puede registrar sin inventar interacción:

- tiempo de `swift build`;
- tamaño del bundle;
- tiempo de arranque hasta respuesta de ActivityWatch;
- PIDs y ausencia de auxiliares después de salir.

Medición real a los 15 segundos de iniciar la app instalada:

| Proceso | RSS | CPU puntual |
|---|---:|---:|
| ChoskyWorklog | 106.864 KiB | 0,6 % |
| ChoskyProcessGuard | 6.080 KiB | 0,0 % |
| aw-server-rust | 13.264 KiB | 0,0 % |

Total aproximado: 123 MiB RSS. El servidor respondió antes de los seis
segundos. Bundle 112 MiB; DMG 49 MiB.

Pendientes de prueba física:

- CPU/RAM en reposo y durante jornada;
- coste de captura con una y dos pantallas;
- 1.000 miniaturas;
- informe con 100 capturas;
- energía y crecimiento por jornada.

La galería usa `LazyVGrid` y miniaturas, las capturas trabajan asíncronamente y
SQLite tiene índices por sesión/fecha. No se afirma cumplimiento de objetivos
sin Instruments o una muestra real.
