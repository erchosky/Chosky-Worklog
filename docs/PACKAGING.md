# Empaquetado

```bash
./scripts/chosky/package.sh
```

Produce `.app`, DMG UDZO, ejemplos, guía PDF, auditoría, información de build y
checksums. El DMG incluye un enlace a `/Applications`.

Firma principal:

```bash
codesign --force --deep --sign - --identifier com.chosky.worklog \
  "dist/Chosky Worklog.app"
```

La firma es ad hoc. Gatekeeper puede rechazarla como no notarizada. No se
desactiva Gatekeeper ni SIP.

Con una cuenta futura, sustituir `-` por una identidad Developer ID, activar
hardened runtime después de validar los auxiliares, usar `notarytool` y
`stapler`. Esa ruta no es requisito actual.
