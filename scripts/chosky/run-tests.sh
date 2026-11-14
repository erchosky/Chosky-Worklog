#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="$ROOT/ChoskyWorklog/Sources/ChoskyWorklog"
OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/chosky-tests.XXXXXX")"
trap 'rm -rf "$OUTPUT"' EXIT

ditto --noextattr "$SOURCE" "$OUTPUT/Sources"
ditto --noextattr "$ROOT/ChoskyWorklog/Sources/CSQLite" "$OUTPUT/CSQLite"
cp "$ROOT/ChoskyWorklog/Tests/TestRunner.swift" "$OUTPUT/TestRunner.swift"

swiftc \
  -parse-as-library \
  -module-cache-path "$OUTPUT/ModuleCache" \
  -I "$OUTPUT/CSQLite" \
  -L /usr/lib -lsqlite3 \
  -framework AppKit \
  -framework ApplicationServices \
  -framework Combine \
  -framework CoreGraphics \
  -framework CoreText \
  -framework CryptoKit \
  -framework Foundation \
  -framework ImageIO \
  -framework ScreenCaptureKit \
  -framework UniformTypeIdentifiers \
  "$OUTPUT/Sources/ProductConfig.swift" \
  "$OUTPUT/Sources/Models.swift" \
  "$OUTPUT/Sources/Database.swift" \
  "$OUTPUT/Sources/ScreenshotService.swift" \
  "$OUTPUT/Sources/SessionManager.swift" \
  "$OUTPUT/Sources/ReportExporter.swift" \
  "$OUTPUT/Sources/BackupManager.swift" \
  "$OUTPUT/TestRunner.swift" \
  -o "$OUTPUT/ChoskyWorklogTests"

"$OUTPUT/ChoskyWorklogTests"
