# Decisiones de arquitectura

## ADR-001 — Shell SwiftUI y auxiliares upstream

Se conserva ActivityWatch como motor, pero no su shell Qt/Tauri. SwiftUI es el
único proceso visible. `aw-server-rust`, `aw-watcher-afk` y
`aw-watcher-window` se empaquetan como recursos y se supervisan como hijos.

Motivo: `aw-tauri` genera otro icono/shell y activa autostart por defecto.

## ADR-002 — SQLite separado

Chosky usa `worklog.sqlite3` con migraciones, claves foráneas, WAL,
`synchronous=FULL` e índice único de sesión activa. ActivityWatch conserva su
propia base. No se mezclan esquemas.

## ADR-003 — Capturas nativas

ScreenCaptureKit y `SCScreenshotManager` producen HEIC con escritura temporal,
movimiento atómico, miniatura JPEG y SHA-256. Las imágenes no son BLOB ni
eventos ActivityWatch.

## ADR-004 — Modo estricto

Predeterminado. Los watchers arrancan con una sesión en curso y paran al
pausar/finalizar. ActivityWatch continuo es opt-in. El servidor permanece
local para consultas y arranque rápido.

## ADR-005 — Compartición revocable

Network.framework sirve un panel HTTP de solo lectura. Desactivado por defecto;
token de 256 bits almacenado solo como hash, caducidad, comparación constante,
rate limiting y revocación que cierra conexiones y listener.

LAN sin TLS se considera una limitación. Para remoto se requiere una red
privada ya configurada; no existe exposición pública automática.

## ADR-006 — Distribución privada ad hoc

Se usa `codesign --sign - --deep`. No hay sandbox, Developer ID ni
notarización. El usuario debe copiar a `/Applications`, abrir manualmente y
conceder TCC. Esta ruta es reproducible sin cuenta de pago.
