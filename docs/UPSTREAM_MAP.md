# Mapa upstream

| Componente | Commit | Uso en Chosky | Cambio directo | Actualización |
|---|---|---|---|---|
| activitywatch | `29d5da0` | Repositorio base y build | Makefile añade targets | Baja |
| aw-client | `2c88b87` | Referencia API | No | Baja |
| aw-core | `34198c6` | Referencia de consulta | No | Baja |
| aw-server-rust | `59eaae3` | Binario arm64 oficial 0.14.0b2 | No | Media |
| aw-watcher-afk | `2ee285f` | Binario arm64 oficial | No | Media |
| aw-watcher-window | `c9732d5` | Binario arm64 oficial | No | Media |
| aw-tauri | `dd8098b` | Auditado, no empaquetado | No | Baja |
| aw-qt | `6fbb5f7` | Auditado, no empaquetado | No | Baja |
| aw-notify | `e8bdb81` | No empaquetado | No | Baja |
| aw-watcher-input | `9bb5045` | No empaquetado; evita keylogging fino | No | Baja |
| awatcher | `d5669d3` | Linux, no empaquetado | No | Baja |
| aw-webui | `464405d` / `e83db8e` | Embebido dentro de server/Tauri upstream | No | Media |

Nuevos: todo `ChoskyWorklog/`, `scripts/chosky/`, documentación y
empaquetado. No se aplicaron parches dentro de submódulos.

Los tres binarios empaquetados proceden del ZIP oficial v0.14.0b2 arm64 cuyo
digest está fijado en `build-info.json`.
