# Manifiesto del ZIP de fuentes

## Identidad

- Proyecto: Chosky Worklog / APLICACION VIGIL.
- Fecha: 2026-07-31 (Europe/Madrid).
- Archivo: `CHOSKY_WORKLOG_FUENTES_2026-07-31.zip`.
- Rama: `codex/chosky-worklog`.
- Commit base: `29d5da0df6476131c643c2c110ffa05b4f0e6291`.
- Remoto: `https://github.com/ActivityWatch/activitywatch.git`.
- Historial: se conservan `.git`, los metadatos de submódulos y el working
  tree con los cambios Chosky todavía no confirmados.

## Qué incluye

- código Swift completo de Chosky Worklog;
- pruebas nativas, de integración y de compartición;
- scripts de descarga verificada, build y empaquetado;
- icono fuente, esquema y migraciones SQLite;
- código fuente upstream disponible de ActivityWatch y sus submódulos;
- lockfiles, licencias, avisos, configuración Git y documentación;
- auditoría correctiva del 31 de julio de 2026.

## Qué no incluye

- runtimes ActivityWatch descargados;
- `.build`, `target`, `node_modules`, entornos virtuales o caches;
- aplicaciones, DMG, ZIP, informes de build o artefactos de distribución;
- bases SQLite, capturas, backups, informes, logs o datos de usuario;
- archivos `.env`, certificados privados o credenciales.

La lista de patrones está en `ARCHIVE_EXCLUSIONS.txt`. Las dependencias se
restauran de forma declarativa mediante lockfiles y:

```bash
make chosky-fetch-resources
```

El asset oficial fijado se rechaza si no coincide con el SHA-256 documentado.

## Entorno de validación

- macOS 26.5, arm64;
- Swift 6.3.3;
- SDK macOS 26.5;
- Git y Xcode Command Line Tools;
- sin paquetes Swift externos para Chosky.

## Validación previa al archivo

- pruebas nativas: 8 aprobadas;
- integración ActivityWatch: 8 comprobaciones aprobadas;
- compartición: 3 comprobaciones aprobadas;
- build release y DMG verificados;
- sintaxis Bash y manifiesto SwiftPM válidos;
- proceso guardián probado contra un hijo que ignora `SIGTERM`;
- auditoría de secretos sin credenciales detectadas.

## Validación del ZIP

El archivo solo se considera entregable después de comprobar:

1. una única carpeta raíz;
2. ausencia de todos los patrones excluidos;
3. `unzip -t` sin errores;
4. extracción completa y comparación contra staging;
5. `git fsck --full` y manifiesto Swift válidos;
6. restauración del runtime desde un asset externo verificado;
7. pruebas y build desde la copia extraída;
8. ausencia de procesos o puertos residuales.

El SHA-256 final se entrega en el archivo hermano
`CHOSKY_WORKLOG_FUENTES_2026-07-31.zip.sha256`. No se inserta dentro del propio
ZIP porque modificaría el hash que pretende registrar.

## Restauración

Sigue `README_ARCHIVE.md`. Los datos personales no forman parte del código y
solo deben restaurarse desde un backup privado independiente.
