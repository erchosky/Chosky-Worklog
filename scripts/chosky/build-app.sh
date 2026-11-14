#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$ROOT/ChoskyWorklog"
DIST="$ROOT/dist"
FINAL_APP="$DIST/Chosky Worklog.app"
ACTIVITYWATCH="$PROJECT/Resources/ActivityWatch"
SIGNING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/chosky-signing.XXXXXX")"
trap 'rm -rf "$SIGNING_ROOT"' EXIT
APP="$SIGNING_ROOT/Chosky Worklog.app"
CONTENTS="$APP/Contents"
BUILD_ROOT="$SIGNING_ROOT/Build"
ICONSET="$SIGNING_ROOT/ChoskyWorklog.iconset"

for component in aw-server-rust aw-watcher-afk aw-watcher-window; do
  if [ ! -d "$ACTIVITYWATCH/$component" ]; then
    echo "Faltan los runtimes de ActivityWatch. Ejecuta: make chosky-fetch-resources" >&2
    exit 1
  fi
done

swift build \
  --package-path "$PROJECT" \
  --scratch-path "$BUILD_ROOT" \
  -c release \
  --product ChoskyWorklog
swift build \
  --package-path "$PROJECT" \
  --scratch-path "$BUILD_ROOT" \
  -c release \
  --product ChoskyProcessGuard

rm -rf "$FINAL_APP" "$ICONSET"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$ICONSET"

cp "$BUILD_ROOT/release/ChoskyWorklog" "$CONTENTS/MacOS/ChoskyWorklog"
cp "$BUILD_ROOT/release/ChoskyProcessGuard" "$CONTENTS/MacOS/ChoskyProcessGuard"
chmod 755 "$CONTENTS/MacOS/ChoskyWorklog"
chmod 755 "$CONTENTS/MacOS/ChoskyProcessGuard"
mkdir -p "$CONTENTS/Resources/ActivityWatch"
cp -RX "$PROJECT/Resources/ActivityWatch/." "$CONTENTS/Resources/ActivityWatch/"

SOURCE_ICON="$PROJECT/Resources/AppIcon-1024.png"
sips -z 16 16 "$SOURCE_ICON" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$SOURCE_ICON" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SOURCE_ICON" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$SOURCE_ICON" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

/usr/bin/python3 - "$CONTENTS/Info.plist" <<'PY'
import plistlib
import sys

info = {
    "CFBundleDevelopmentRegion": "es",
    "CFBundleDisplayName": "Chosky Worklog",
    "CFBundleExecutable": "ChoskyWorklog",
    "CFBundleIconFile": "AppIcon",
    "CFBundleIdentifier": "com.chosky.worklog",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "Chosky Worklog",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "0.1.0",
    "CFBundleVersion": "1",
    "LSMinimumSystemVersion": "14.0",
    "LSMultipleInstancesProhibited": True,
    "NSHighResolutionCapable": True,
    "NSScreenCaptureUsageDescription": "Chosky Worklog realiza capturas de evidencia solo durante una sesión de trabajo activa.",
    "NSLocalNetworkUsageDescription": "Permite compartir temporalmente un panel privado de solo lectura en la red local.",
    "NSHumanReadableCopyright": "© 2026 Chosky Worklog contributors",
}
with open(sys.argv[1], "wb") as handle:
    plistlib.dump(info, handle, sort_keys=True)
PY

xattr -cr "$APP"
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -d com.apple.ResourceFork "$APP" 2>/dev/null || true
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP" 2>/dev/null || true
codesign --force --deep --sign - --identifier com.chosky.worklog "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

ditto "$APP" "$FINAL_APP"
final_verified=false
for _ in 1 2 3 4 5; do
  xattr -d com.apple.FinderInfo "$FINAL_APP" 2>/dev/null || true
  xattr -d com.apple.ResourceFork "$FINAL_APP" 2>/dev/null || true
  if codesign --verify --deep --strict --verbose=2 "$FINAL_APP"; then
    final_verified=true
    break
  fi
done
if [ "$final_verified" != true ]; then
  echo "Aviso: el proveedor de archivos volvió a añadir FinderInfo tras copiar; el bundle temporal firmado sí fue verificado." >&2
fi

rm -rf "$ICONSET"
echo "$FINAL_APP"
