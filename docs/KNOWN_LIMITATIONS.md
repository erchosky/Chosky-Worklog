# Limitaciones conocidas

Versión 0.1.0:

- ActivityWatch arm64 procede de una beta oficial 0.14.0b2.
- El build upstream desde fuente no se completó: faltan Poetry, Rust y Xcode
  completo en el equipo.
- Actividad web depende de una extensión de navegador instalada por separado;
  Chosky no puede garantizar su compuerta fuera de sesión.
- Captura principal implementada; políticas todas-las-pantallas y exclusiones
  por app/dominio/pantalla no están expuestas.
- Corrección, división y combinación de sesiones tienen esquema/auditoría pero
  no editor UI completo.
- Panel LAN usa HTTP, no TLS; remoto Tailscale no se detecta automáticamente.
- Permisos granulares existen en UI, pero v0.1 del panel solo publica el resumen
  de sesiones; capturas y descargas permanecen deshabilitadas.
- No hay cifrado de backups, restauración destructiva desde UI, retención
  automática o firma Keychain del manifiesto.
- PDF no inserta capturas ni tarifas todavía.
- Sin login item propio ni actualizador automático.
- Firma ad hoc no está notarizada y TCC puede pedir permisos tras actualizar.
- Pruebas físicas de bloqueo, reposo, tapa, disco lleno, dos monitores,
  VoiceOver y otro dispositivo LAN siguen pendientes.
