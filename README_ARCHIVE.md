# Restaurar el archivo de Chosky Worklog

Este documento describe cómo reanudar el proyecto desde el ZIP limpio. El
archivo conserva el código de Chosky, el upstream ActivityWatch con sus
submódulos, el historial Git superficial disponible, pruebas, scripts, recursos
originales y documentación. No conserva productos compilados ni datos privados.

## 1. Requisitos

- Mac con Apple Silicon y macOS 14 o posterior.
- Xcode Command Line Tools:

```bash
xcode-select --install
```

- Swift. La validación del archivo se realizó con Swift `6.3.3`, SDK macOS
  `26.5` y Command Line Tools en
  `/Library/Developer/CommandLineTools`.
- Git `2.50.1` o compatible.
- `curl`, `shasum`, `ditto`, `zip`, `unzip`, `hdiutil`, `sips`, `iconutil` y
  `codesign`, incluidos en macOS o Command Line Tools.
- Internet para restaurar submódulos que falten y descargar el runtime oficial
  de ActivityWatch. También puede utilizarse una copia externa del asset.

Node.js, npm, Python/Poetry y Rust pertenecen al monorepo upstream y solo son
necesarios para recompilar ActivityWatch desde sus fuentes. La aplicación
Chosky validada usa SwiftPM y runtimes oficiales verificados.

## 2. Descomprimir

```bash
unzip CHOSKY_WORKLOG_FUENTES_2026-07-31.zip
cd "APLICACION VIGIL"
```

El ZIP contiene una sola carpeta raíz llamada `APLICACION VIGIL`.

## 3. Recuperar Git y submódulos

El directorio `.git` y los objetos disponibles de los submódulos están incluidos.
Comprueba primero el estado local:

```bash
git status --short --branch
git submodule status --recursive
```

Para recuperar cualquier objeto ausente desde los repositorios públicos:

```bash
git submodule sync --recursive
git submodule update --init --recursive
```

Rama archivada: `codex/chosky-worklog`. Commit base:
`29d5da0df6476131c643c2c110ffa05b4f0e6291`.
Los cambios Chosky no estaban confirmados; por eso la copia conserva también el
working tree.

## 4. Variables de entorno

No hay secretos ni un archivo `.env` obligatorio. `.env.example` documenta la
única variable opcional:

```bash
cp .env.example .env
```

No es necesario crear `.env` para el flujo normal. Si se dispone del ZIP oficial
de ActivityWatch fuera del proyecto:

```bash
export CHOSKY_ACTIVITYWATCH_ARCHIVE="/ruta/privada/activitywatch-v0.14.0b2-macos-arm64.zip"
```

## 5. Restaurar dependencias binarias regenerables

```bash
make chosky-fetch-resources
```

La descarga se rechaza si no coincide con el SHA-256 fijado. Los lockfiles
Swift, Python, Rust y npm del upstream se conservan. Chosky no usa paquetes
Swift externos, por lo que no genera `Package.resolved`.

## 6. Migraciones y datos

No se incluye ninguna base de datos de usuario. El esquema y las migraciones
están en `ChoskyWorklog/Sources/ChoskyWorklog/Database.swift` y se aplican
automáticamente al primer arranque. No existe un comando de migración manual
separado.

Los datos de ejecución viven en:

```text
~/Library/Application Support/com.chosky.worklog/
```

Solo deben recuperarse desde un backup privado creado expresamente por la
persona usuaria.

## 7. Probar y desarrollar

```bash
make chosky-test
swift run --package-path ChoskyWorklog ChoskyWorklog
```

Las pruebas cubren la máquina de estados, SQLite y migraciones, relaciones,
AFK, capturas, informes, backup/restauración, ActivityWatch, pausa estricta,
arranque/cierre de procesos y permisos de compartición local.

## 8. Build y paquete

```bash
make chosky-build
make chosky-package
```

Resultados regenerables:

```text
dist/Chosky Worklog.app
dist/Chosky-Worklog-arm64.dmg
```

La firma actual es ad hoc. Para distribución pública debe configurarse un
Developer ID y notarización fuera del repositorio.

## 9. Despliegue e instalación local

No hay despliegue cloud. Para instalar el bundle regenerado:

```bash
ditto --noextattr --norsrc "dist/Chosky Worklog.app" "/Applications/Chosky Worklog.app"
xattr -cr "/Applications/Chosky Worklog.app"
codesign --verify --deep --strict "/Applications/Chosky Worklog.app"
```

Concede Grabación de pantalla y, para el watcher de ventanas, Accesibilidad.
Red local solo es necesaria al activar explícitamente la compartición LAN.

## 10. Comprobación mínima

```bash
make chosky-test
codesign --verify --deep --strict "dist/Chosky Worklog.app"
shasum -a 256 -c dist/checksums.txt
```

## 11. Componentes no incluidos

- `.build`, `dist`, DMG, aplicaciones firmadas ad hoc y resultados de pruebas.
- Runtimes binarios copiados de ActivityWatch; se restauran con el script
  verificado.
- Entorno virtual `.audit-venv` y descargas de auditoría `.audit-upstream`.
- Bases de datos, capturas, informes y backups personales.
- Caches, logs, temporales, ZIP anteriores y basura de macOS/editor.
- Secretos y credenciales; no se detectó ninguno necesario para el proyecto.

Consulta `ARCHIVE_EXCLUSIONS.txt`, `ARCHIVE_MANIFEST.md`,
`PROJECT_SERVICES.md` y `docs/ARCHIVE_AUDIT.md` para el detalle.
