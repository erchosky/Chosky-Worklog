#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="$ROOT/ChoskyWorklog/Sources/ChoskyWorklog"
OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/chosky-sharing.XXXXXX")"
trap 'rm -rf "$OUTPUT"' EXIT

ditto --noextattr "$SOURCE" "$OUTPUT/Sources"
ditto --noextattr "$ROOT/ChoskyWorklog/Sources/CSQLite" "$OUTPUT/CSQLite"
cp "$ROOT/ChoskyWorklog/Tests/SharingIntegrationRunner.swift" "$OUTPUT/SharingIntegrationRunner.swift"

swiftc \
  -parse-as-library \
  -module-cache-path "$OUTPUT/ModuleCache" \
  -I "$OUTPUT/CSQLite" \
  -L /usr/lib -lsqlite3 \
  -framework Combine \
  -framework CryptoKit \
  -framework Foundation \
  -framework Network \
  -framework Security \
  "$OUTPUT/Sources/ProductConfig.swift" \
  "$OUTPUT/Sources/Models.swift" \
  "$OUTPUT/Sources/Database.swift" \
  "$OUTPUT/Sources/SharingServer.swift" \
  "$OUTPUT/SharingIntegrationRunner.swift" \
  -o "$OUTPUT/ChoskySharingTests"

"$OUTPUT/ChoskySharingTests"
