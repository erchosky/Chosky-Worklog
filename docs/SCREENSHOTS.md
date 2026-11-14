# Capturas

Motor: ScreenCaptureKit. Predeterminado: HEIC calidad 0,78, miniatura JPEG y
pantalla principal. Después de cada captura se elige con
`SystemRandomNumberGenerator` un nuevo intervalo entero entre 8 y 18 minutos.
No hay cuenta atrás ni notificación previa; sí hay indicador permanente.

Condiciones obligatorias antes de capturar:

- sesión con estado `running`;
- capturas habilitadas;
- privacidad desactivada;
- pantalla no bloqueada;
- permiso TCC concedido.

La escritura usa un archivo oculto temporal, permisos 0600, finalización
ImageIO y movimiento atómico. Se registra SHA-256, pantalla, resolución,
escala, aplicación y sesión. La eliminación mueve a `Trash` antes de marcar la
fila.

Limitación v0.1: captura la pantalla principal; las cuatro políticas
multimonitor configurables aún no están expuestas.
