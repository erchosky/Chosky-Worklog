# Auditoría inicial

Fecha: 27 de julio de 2026. Equipo: macOS 26.5.1, arm64, Swift 6.3.2.

## Repositorio inspeccionado

- ActivityWatch `29d5da0df6476131c643c2c110ffa05b4f0e6291`.
- Versión declarada: 0.14.0.
- Todos los submódulos y submódulos anidados se inicializaron con los commits
  registrados en [UPSTREAM_MAP.md](UPSTREAM_MAP.md).
- Remoto `upstream`: `https://github.com/ActivityWatch/activitywatch.git`.
- Rama de trabajo: `codex/chosky-worklog`.

Componentes: `aw-client`, `aw-core`, `aw-notify`, `aw-qt`, `aw-server`,
`aw-server-rust`, `aw-tauri`, `aw-watcher-afk`, `aw-watcher-input`,
`aw-watcher-window`, `awatcher` y tres copias fijadas de `aw-webui`.

## Build original

Comando ejecutado antes de modificar fuentes:

```bash
python3 -m venv .audit-venv
source .audit-venv/bin/activate
make build
```

Resultado real: fallo en `aw-core` porque `poetry` no está instalado. El
entorno tampoco tiene Rust/Cargo ni Xcode completo, por lo que el build
original completo no es posible sin ampliar las herramientas. No se presenta
como aprobado.

## Ejecución original arm64

Se descargó el artefacto oficial `v0.14.0b2`:

```text
activitywatch-tauri-v0.14.0b2-macos-arm64.zip
SHA-256 40e38b36cc5b2267112126e66ba1a5164c30218b2fe944ef11e7beb82dd6c628
```

El hash coincide con el digest publicado por GitHub. Al ejecutarlo:

- inició `aw-tauri` arm64;
- creó configuración con `autostart.enabled = true`;
- lanzó `osascript` para crear un login item;
- el servidor 5600 no llegó a responder en seis segundos;
- `osascript` quedó esperando y fue terminado explícitamente;
- no quedaron procesos ActivityWatch;
- el estado creado se conservó en `.audit-upstream/runtime-state`.

Este comportamiento justifica no reutilizar `aw-tauri` como shell.

## Empaquetado upstream

- Legado: PyInstaller + `aw-qt`, `ActivityWatch.app` y DMG.
- Experimental actual: Tauri 2, servidor Rust embebido, WebView, tray,
  reinicio de módulos y soporte arm64.
- El release arm64 legado v0.14.0b2 incluye `aw-server-rust`,
  `aw-watcher-afk` y `aw-watcher-window` como Mach-O arm64 ad hoc.
- El artefacto completo usado tiene SHA-256
  `33380f395ac873bc28da4453c63365bbae1c7d06dc44cfceafe2adbbe707ed54`.

## Comunicación y datos

ActivityWatch utiliza HTTP JSON local en el puerto 5600, buckets y
heartbeats. `aw-server-rust` admite `--host`, `--port` y `--dbpath`. Chosky
fuerza `127.0.0.1` y una base de datos bajo su propio Application Support.

## Licencias y seguridad

El repositorio y los componentes oficiales declaran MPL-2.0. Los binarios
incluyen dependencias transitorias con sus propios avisos. No se encontró un
archivo de advisories específico en el checkout; esto no equivale a afirmar
ausencia de vulnerabilidades. El inventario y los riesgos están en
[DEPENDENCIES.md](DEPENDENCIES.md) y [THREAT_MODEL.md](../THREAT_MODEL.md).

## Riesgos iniciales

1. ActivityWatch beta arm64, no release estable arm64.
2. Watchers PyInstaller incluyen Python 3.9 y dependencia `pkg_resources`
   obsoleta.
3. El watcher web requiere extensión separada y puede registrar fuera del
   control del shell; no se instala automáticamente.
4. Firma ad hoc no equivale a Developer ID/notarización.
5. ScreenCaptureKit y Accesibilidad requieren autorización manual TCC.
6. Un panel LAN HTTP no cifra tráfico; debe preferirse localhost o Tailscale.
