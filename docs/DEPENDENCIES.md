# Dependencias

## Runtime nativo

Frameworks Apple: SwiftUI, AppKit, Foundation, Combine, ScreenCaptureKit,
ImageIO, UniformTypeIdentifiers, CryptoKit, Network, WebKit, CoreGraphics,
CoreText, ApplicationServices y SQLite3 del sistema.

No hay Swift Package externo.

## ActivityWatch empaquetado

Asset oficial: `activitywatch-v0.14.0b2-macos-arm64.zip`.

```text
SHA-256 33380f395ac873bc28da4453c63365bbae1c7d06dc44cfceafe2adbbe707ed54
```

Se copian:

- `aw-server-rust` (Mach-O arm64, servidor y webui embebida);
- `aw-watcher-afk` (PyInstaller/Python 3.9 arm64);
- `aw-watcher-window` (PyInstaller/Python 3.9 arm64).

Los lockfiles completos de Rust/Python viven en los submódulos fijados.
El runtime PyInstaller mostró una advertencia de deprecación de
`pkg_resources`; se registra como deuda upstream.

## Build

Swift 6.3.2, iconutil, sips, codesign, hdiutil, ditto, shasum, cupsfilter y
Python del sistema solo para generar plist/JSON.
