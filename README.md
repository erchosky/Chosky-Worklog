# Chosky Worklog

Aplicación nativa y privada de registro de trabajo para macOS, construida sobre
ActivityWatch. El punto de entrada es una única aplicación:
`Chosky Worklog.app`.

## Estado

Versión 0.1.0. El núcleo nativo, las sesiones, la persistencia, las capturas,
ActivityWatch, los informes, los backups y el panel temporal están
implementados. Consulta [KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md) antes
de usarla como evidencia contractual. La auditoría correctiva más reciente está
en [AUDIT_2026-07-31.md](docs/AUDIT_2026-07-31.md).

## Construir

Requisitos de desarrollo comprobados:

- macOS 26 arm64.
- Apple Command Line Tools con Swift 6.3.2.
- Sin Homebrew, Python, Node o Rust en tiempo de ejecución.

```bash
make chosky-test
make chosky-build
make chosky-package
```

Resultados:

- `dist/Chosky Worklog.app`
- `dist/Chosky-Worklog-arm64.dmg`
- `dist/checksums.txt`

## Privacidad

El modo estricto está activado por defecto. Fuera de una sesión, y durante una
pausa, los watchers y las capturas se detienen. La aplicación no implementa
keylogging, audio, cámara, OCR, analytics, telemetría ni servicios cloud.

Los datos viven en:

```text
~/Library/Application Support/com.chosky.worklog/
```

## Licencia

El código nuevo de Chosky Worklog se distribuye bajo MPL-2.0 para mantener
compatibilidad con ActivityWatch. Los componentes upstream conservan sus
avisos; consulta [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
