# Auditoría para archivo reanudable

Fecha: 2026-07-28  
Proyecto: Chosky Worklog sobre el monorepo ActivityWatch  
Rama: `codex/chosky-worklog`  
Commit base: `29d5da0df6476131c643c2c110ffa05b4f0e6291`

## Alcance detectado

- Aplicación macOS nativa: Swift 6, SwiftUI, AppKit, ScreenCaptureKit,
  Network.framework, WebKit y SQLite.
- Gestor principal de Chosky: Swift Package Manager.
- Upstream monorepo ActivityWatch: Python/Poetry, Rust/Cargo,
  JavaScript/npm, TypeScript/Vue y scripts Bash.
- Submódulos Git: `aw-client`, `aw-core`, `aw-notify`, `aw-qt`, `aw-server`,
  `aw-server-rust`, `aw-tauri`, `aw-watcher-afk`, `aw-watcher-input`,
  `aw-watcher-window`, `awatcher` y submódulos web/media anidados.
- Backend local: `aw-server-rust` en `127.0.0.1:5600`.
- Base de datos: SQLite local; esquema y migración v1 definidos en Swift.
- Frontend: interfaz SwiftUI de Chosky y web UI upstream en submódulos.
- No se detectaron funciones serverless ni despliegues cloud de Chosky.

## Git

- `.git` ocupa aproximadamente 7.4 MB y se considera historial razonable.
- La rama no tiene upstream propio, pero su commit coincide con
  `upstream/master` en la copia inspeccionada.
- Había cuatro archivos raíz modificados antes de esta auditoría:
  `.gitignore`, `Makefile`, `README.md` y `SECURITY.md`.
- La implementación Chosky, documentación y runtimes eran contenido local sin
  commit. El archivo conserva ese working tree.
- Remoto público: `https://github.com/ActivityWatch/activitywatch.git`.
- No se reescribió historial, no se hizo commit, push, PR ni despliegue.

## Seguridad y datos

- No se detectaron archivos `.env` reales, claves privadas, tokens de formatos
  conocidos, URLs con usuario/contraseña ni rutas absolutas de la máquina en el
  código Chosky.
- Dos coincidencias genéricas de `api_key` pertenecen a tests/configuración
  upstream y usan valores de prueba, no credenciales operativas.
- Los PEM encontrados son certificados CA públicos dentro de runtimes
  compilados excluidos.
- No se detectaron bases de datos, sesiones, capturas personales ni
  exportaciones reales dentro de la fuente que se archivará.
- Los datos bajo `~/Library/Application Support/Chosky Worklog/` viven fuera
  del proyecto y no se copiaron.

## Archivos grandes

Los elementos grandes detectados eran regenerables:

- Runtime oficial ActivityWatch copiado dentro de
  `ChoskyWorklog/Resources/ActivityWatch/`.
- `dist/Chosky Worklog.app` y el DMG generado.
- `.audit-upstream/` con ZIP y aplicaciones usados para estudiar el upstream.
- `ChoskyWorklog/.build/` con módulos, ejecutables y símbolos Swift.

El recurso original `ChoskyWorklog/Resources/AppIcon-1024.png` sí se conserva.
Los runtimes excluidos se recuperan con un script que fija versión y SHA-256.

## Problemas confirmados y correcciones

1. El target `chosky-package` ejecutaba después del empaquetado un borrado
   recursivo de cualquier `node_modules` del monorepo. Se retiró esa orden.
2. El build dependía de binarios locales no declarados. Se añadió
   `scripts/chosky/fetch-activitywatch-resources.sh`, con descarga oficial y
   verificación SHA-256, más el target `make chosky-fetch-resources`.
3. El script de build ahora falla con una instrucción clara si faltan los tres
   componentes ActivityWatch.
4. `.gitignore` se reforzó para excluir runtimes descargados, builds, datos
   locales, medios de evidencia, ZIP/DMG y archivos `.env`, preservando
   `.env.example`.
5. Se añadieron la documentación y los manifiestos requeridos para restaurar.

No se cambió arquitectura, interfaz, lógica de negocio, API pública ni esquema
de base de datos.

## Comprobaciones

Antes de crear el archivo definitivo se ejecutan:

- `bash -n` sobre todos los scripts Chosky.
- Validación del manifiesto Swift.
- Pruebas nativas, de integración ActivityWatch y de compartición.
- Build release y firma ad hoc.
- Copia limpia a staging.
- Escaneo de secretos, dependencias, caches, builds, datos y enlaces.
- Restauración en una segunda carpeta temporal.
- Descarga/verificación de ActivityWatch desde la copia restaurada.
- Pruebas y build desde cero.
- Limpieza posterior y comparación de contenido.
- Integridad y extracción del ZIP final.

## Resultado de la restauración

- Segunda copia creada en `/tmp`, sin depender del árbol original.
- Runtime ActivityWatch restaurado desde el asset oficial y validado por
  SHA-256.
- 6 pruebas nativas, 5 de integración y 3 de compartición aprobadas.
- Build release aprobado; bundle arm64 y firma ad hoc válidos.
- Arranque aislado aprobado; ActivityWatch respondió y el cierre no dejó
  procesos ni puertos huérfanos.
- Los productos generados se retiraron de la restauración y el contenido fuente
  volvió a coincidir con el staging.

Las métricas y advertencias finales se registran en `ARCHIVE_MANIFEST.md`.

## Archivo definitivo

- ZIP:
  `/Users/sheylla/Documents/CHOSKY_WORKLOG_ARCHIVO_LIMPIO_2026-07-28.zip`.
- Tamaño: 15.296.447 bytes.
- SHA-256:
  `9f2017616f13ea451d218adee17598944e79d909645e1a498fb6e45340eddec5`.
- Entradas: 2.595, bajo una única carpeta raíz.
- `unzip -t`, extracción completa, comparación con staging, exclusiones,
  escaneo de secretos y `git fsck --full`: aprobados.
- Estado: **ZIP limpio, validado y restaurable**.
