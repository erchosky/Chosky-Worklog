# Build macOS

Comprobado en macOS 26.5.1 arm64 con Swift 6.3.2:

```bash
./scripts/chosky/build-app.sh
```

El script:

1. ejecuta `swift build -c release`;
2. crea la estructura `.app`;
3. copia los tres auxiliares arm64 fijados;
4. genera `AppIcon.icns`;
5. escribe `Info.plist`;
6. aplica firma ad hoc profunda;
7. verifica `codesign`.

No requiere Xcode completo, Homebrew, Rust, Python o Node para compilar el
shell. `/usr/bin/python3` se usa solo para escribir plist/JSON en scripts de
build; no se incluye como requisito de runtime.
