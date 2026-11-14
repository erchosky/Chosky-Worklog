# Pruebas

Comando comprobado sin Xcode completo:

```bash
./scripts/chosky/run-tests.sh
```

Compila un ejecutable temporal con los mismos fuentes y un cache de módulos
aislado, y verifica:

- transiciones válidas e imposibles;
- migración, seed e `integrity_check`;
- exclusión de dos sesiones activas;
- 200 intervalos aleatorios dentro de 8–18 minutos;
- PDF real, HTML, CSV, JSON, ZIP y manifiesto;
- backup, checksum y restauración en base limpia.
- relaciones cliente/proyecto/tarea y recargas durante una sesión activa;
- detección AFK local y conservación del último intervalo al pausar;
- solapamiento de rangos, redacción de tarifas y neutralización de fórmulas CSV.

Integración ActivityWatch:

```bash
./scripts/chosky/run-integration-tests.sh
```

Verifica servidor, watchers AFK/ventana, buckets correlacionados, pausa estricta,
reinicio durante pausa, conmutación inmediata del modo continuo, pausa durante
el arranque y cierre del puerto.

Compartición:

```bash
./scripts/chosky/run-sharing-tests.sh
```

Verifica listener localhost, token, aplicación efectiva de permisos de sesión,
revocación y enlace antiguo inválido.

Build:

```bash
scratch="$(mktemp -d "${TMPDIR:-/tmp}/chosky-build.XXXXXX")"
swift build --package-path ChoskyWorklog --scratch-path "$scratch" -c release
```

La prueba manual de permisos, bloqueo, dos monitores y LAN requiere interacción
física y se registra como pendiente, no como aprobada.
