# Servicios y dependencias externas

## Resumen

Chosky Worklog funciona de forma local. No usa cuentas de Supabase, Firebase,
Vercel, OpenAI, Stripe, servicios de correo ni telemetría. No hay secretos de
aplicación ni datos de producción remotos que deban exportarse.

| Servicio o plataforma | Finalidad | Variables | Datos fuera del repositorio | Riesgo y reconexión |
|---|---|---|---|---|
| GitHub / ActivityWatch | Repositorios upstream y descarga del runtime oficial arm64 | Ninguna. Opcional: `CHOSKY_ACTIVITYWATCH_ARCHIVE` para usar una copia local | Releases públicos y repositorios Git públicos | Si desaparece el release, usar una copia externa del asset cuyo hash figura abajo o compilar los submódulos |
| APIs locales de Apple | SwiftUI, AppKit, ScreenCaptureKit, Network, WebKit y permisos TCC | Ninguna | Consentimientos de Grabación de pantalla, Accesibilidad y Red local en macOS | Volver a conceder permisos desde Ajustes del Sistema |
| ActivityWatch local | Servidor y watchers iniciados como procesos hijos de Chosky | Ninguna | Datos de ejecución locales bajo `~/Library/Application Support/Chosky Worklog/` | Los datos personales no forman parte del archivo de código; restaurarlos solo desde un backup separado y privado |

## Runtime ActivityWatch

- Versión fijada: `v0.14.0b2`.
- Asset: `activitywatch-v0.14.0b2-macos-arm64.zip`.
- SHA-256 esperado:
  `33380f395ac873bc28da4453c63365bbae1c7d06dc44cfceafe2adbbe707ed54`.
- Reconexión:

```bash
make chosky-fetch-resources
```

El script descarga el release público, verifica el hash antes de extraerlo y
solo instala `aw-server-rust`, `aw-watcher-afk` y `aw-watcher-window`.

## Elementos que deben guardarse por separado

- Backups privados de la base de datos y evidencias que la persona usuaria
  quiera conservar.
- Certificado Developer ID y credenciales de notarización, si se obtienen en el
  futuro. Nunca deben añadirse al repositorio ni al ZIP de código.
- Opcionalmente, una copia externa del asset oficial ActivityWatch anterior para
  reconstruir sin red.
