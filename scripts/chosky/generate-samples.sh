#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="$ROOT/ChoskyWorklog/Sources/ChoskyWorklog"
DESTINATION="${1:?Falta la carpeta de destino}"
OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/chosky-samples.XXXXXX")"
trap 'rm -rf "$OUTPUT"' EXIT

mkdir -p "$DESTINATION"
ditto --noextattr "$SOURCE" "$OUTPUT/Sources"
ditto --noextattr "$ROOT/ChoskyWorklog/Sources/CSQLite" "$OUTPUT/CSQLite"
cp "$ROOT/ChoskyWorklog/Tests/SampleReportGenerator.swift" "$OUTPUT/SampleReportGenerator.swift"

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
  "$OUTPUT/SampleReportGenerator.swift" \
  -o "$OUTPUT/SampleReportGenerator"

"$OUTPUT/SampleReportGenerator" "$DESTINATION"
