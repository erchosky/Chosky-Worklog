# Auditoría final

Fecha original: 27 de julio de 2026. Actualizada: 31 de julio de 2026.

La revisión correctiva vigente, con defectos y evidencia ampliada, está en
[AUDIT_2026-07-31.md](AUDIT_2026-07-31.md).

Estado: **parcialmente funcional**.

No se usa “funcional y verificado” porque faltan pruebas físicas de capturas
reales con TCC, bloqueo/reposo, dos monitores, VoiceOver y acceso desde un
segundo dispositivo.

## Arquitectura verificada

- shell SwiftUI arm64, ventana y `MenuBarExtra`;
- SQLite separado, migración v1 e índice único de sesión activa;
- ScreenCaptureKit/HEIC con escritura atómica y SHA-256;
- ActivityWatch v0.14.0b2 arm64: servidor Rust y watchers AFK/ventana;
- `ChoskyProcessGuard` nativo para terminar hijos incluso al perder al padre;
- informes y backup locales;
- panel HTTP temporal de solo lectura, desactivado por defecto.

## Funciones completadas y probadas

- seed Nina, siete proyectos y 18 tareas;
- máquina de estados y exclusión de dos sesiones activas;
- persistencia, auditoría y `integrity_check`;
- aleatoriedad de capturas dentro de 8–18 minutos;
- PDF, HTML, CSV, JSON, ZIP y manifiesto SHA-256;
- backup y restauración en base limpia;
- ActivityWatch en `127.0.0.1:5600`;
- arranque/parada de watchers en modo estricto;
- buckets de sesión, AFK y ventana;
- panel local con token y contenido solo lectura;
- revocación: cierra listener e invalida enlace;
- firma ad hoc verificada dentro del DMG;
- instalación real en `/Applications`;
- cierre sin procesos auxiliares ni puerto abierto;
- verificación de 202 hashes de archivos/distribución.

## Comandos y resultados

```bash
./scripts/chosky/run-tests.sh
```

8 aprobadas, 0 fallidas.

```bash
./scripts/chosky/run-integration-tests.sh
```

8 comprobaciones aprobadas: servidor, dos watchers, tres buckets, pausa
estricta, reinicio pausado, modo continuo, pausa durante arranque y cierre.

```bash
./scripts/chosky/run-sharing-tests.sh
```

3 aprobadas: listener/token, permisos efectivos del panel y revocación.

```bash
./scripts/chosky/package.sh
```

Generó `.app`, DMG, ejemplos, guía PDF, auditoría, build-info y checksums.

## Ejecución instalada

Ruta: `/Applications/Chosky Worklog.app`.

- ejecutables principal, guardián y ActivityWatch: Mach-O arm64;
- ActivityWatch respondió:
  `{"version":"v0.14.0-beta.2 (rust)","testing":false}`;
- base local: `integrity_check=ok`, 1 cliente, 7 proyectos, 18 tareas;
- después de SIGTERM: ningún `ChoskyProcessGuard`, `aw-server-rust` o watcher;
- `127.0.0.1:5600` quedó cerrado.

## Consumo observado

Muestra a los 15 segundos de arranque:

- shell: 106.864 KiB RSS, 0,6 % CPU;
- guardián: 6.080 KiB RSS, 0,0 % CPU;
- servidor: 13.264 KiB RSS, 0,0 % CPU;
- total aproximado: 123 MiB RSS;
- bundle: 112 MiB;
- DMG: 49 MiB;
- servidor disponible en menos de seis segundos en la prueba.

No son medidas de una jornada ni sustituyen Instruments.

## Firma y Gatekeeper

`codesign --verify --deep --strict` pasa en el bundle temporal, en
`/Applications` y dentro del DMG montado. `spctl` rechaza la copia ad hoc como
no notarizada, resultado esperado. Documentos/iCloud puede volver a añadir
`com.apple.FinderInfo` a la copia guardada en el workspace; la copia del DMG se
empaqueta sin esos xattrs.

## Funciones no completadas

- políticas multimonitor y exclusiones por app/dominio/pantalla;
- editor UI para dividir/combinar/corregir intervalos;
- Tailscale automático y TLS LAN;
- capturas/tarifas/descargas en el panel compartido;
- cifrado de backup y restauración destructiva desde UI;
- retención automática;
- PDF con capturas;
- prueba de extensión web bajo compuerta estricta;
- login item y actualización privada automática.

## Pruebas pendientes

Captura TCC real, bloqueo/loginwindow, reposo/tapa, cambio de monitor y
resolución, disco lleno, 1.000 miniaturas, 100 capturas por informe, LAN desde
otro dispositivo, Tailscale, VoiceOver y reinicio del Mac.

## Entregables

- app: `dist/Chosky Worklog.app`
- DMG: `dist/Chosky-Worklog-arm64.dmg`
- datos: `~/Library/Application Support/com.chosky.worklog/`
- logs: `~/Library/Logs/com.chosky.worklog/`
