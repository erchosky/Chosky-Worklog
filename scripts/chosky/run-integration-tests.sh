#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="$ROOT/ChoskyWorklog/Sources/ChoskyWorklog"
OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/chosky-integration.XXXXXX")"
trap 'rm -rf "$OUTPUT"' EXIT

swift build \
  --package-path "$ROOT/ChoskyWorklog" \
  --scratch-path "$OUTPUT/Build" \
  -c release \
  --product ChoskyProcessGuard >/dev/null

export CHOSKY_PROCESS_GUARD_PATH="$OUTPUT/Build/release/ChoskyProcessGuard"

ditto --noextattr "$SOURCE" "$OUTPUT/Sources"
ditto --noextattr "$ROOT/ChoskyWorklog/Sources/CSQLite" "$OUTPUT/CSQLite"
cp "$ROOT/ChoskyWorklog/Tests/IntegrationRunner.swift" "$OUTPUT/IntegrationRunner.swift"

swiftc \
  -parse-as-library \
  -module-cache-path "$OUTPUT/ModuleCache" \
  -I "$OUTPUT/CSQLite" \
  -L /usr/lib -lsqlite3 \
  -framework Combine \
  -framework Foundation \
  "$OUTPUT/Sources/ProductConfig.swift" \
  "$OUTPUT/Sources/Models.swift" \
  "$OUTPUT/Sources/Database.swift" \
  "$OUTPUT/Sources/ActivityWatchSupervisor.swift" \
  "$OUTPUT/IntegrationRunner.swift" \
  -o "$OUTPUT/ChoskyIntegrationTests"

cd "$ROOT"
"$OUTPUT/ChoskyIntegrationTests"
