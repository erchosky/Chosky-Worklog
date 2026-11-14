# Arquitectura

```text
Chosky Worklog.app
├── ChoskyWorklog (SwiftUI, único proceso visible)
│   ├── SessionManager + máquina de estados
│   ├── WorklogDatabase (SQLite)
│   ├── ScreenshotService (ScreenCaptureKit)
│   ├── ReportExporter + BackupManager
│   ├── SharingServer (Network.framework)
│   └── ActivityWatchSupervisor
└── Contents/Resources/ActivityWatch
    ├── aw-server-rust (127.0.0.1:5600)
    ├── aw-watcher-afk
    └── aw-watcher-window
```

El servidor y los watchers son hijos supervisados. `aw-qt` y `aw-tauri` no se
empaquetan porque crearían otro shell visible. El servidor solo escucha en
loopback. En modo estricto los watchers se ejecutan únicamente durante una
sesión activa.

La base de datos de Chosky y la de ActivityWatch están separadas. La
correlación se realiza con eventos `chosky.worksession` que contienen
`session_id`, `project_id`, `task_id` y estado; nunca contienen imágenes.

Las decisiones completas están en
[ARCHITECTURE_DECISIONS.md](docs/ARCHITECTURE_DECISIONS.md).
