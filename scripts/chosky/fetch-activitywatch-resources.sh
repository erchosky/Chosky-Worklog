#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DESTINATION="$ROOT/ChoskyWorklog/Resources/ActivityWatch"
VERSION="v0.14.0b2"
ASSET="activitywatch-v0.14.0b2-macos-arm64.zip"
URL="https://github.com/ActivityWatch/activitywatch/releases/download/$VERSION/$ASSET"
EXPECTED_SHA256="33380f395ac873bc28da4453c63365bbae1c7d06dc44cfceafe2adbbe707ed54"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/chosky-activitywatch.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

ARCHIVE="$WORK/$ASSET"
if [ -n "${CHOSKY_ACTIVITYWATCH_ARCHIVE:-}" ]; then
  if [ ! -f "$CHOSKY_ACTIVITYWATCH_ARCHIVE" ]; then
    echo "CHOSKY_ACTIVITYWATCH_ARCHIVE no apunta a un archivo." >&2
    exit 1
  fi
  /usr/bin/ditto --noextattr "$CHOSKY_ACTIVITYWATCH_ARCHIVE" "$ARCHIVE"
else
  /usr/bin/curl --fail --location --retry 3 --output "$ARCHIVE" "$URL"
fi

ACTUAL_SHA256="$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "El SHA-256 del runtime ActivityWatch no coincide; no se instalará." >&2
  exit 1
fi

/usr/bin/ditto -x -k "$ARCHIVE" "$WORK/extracted"
SOURCE="$WORK/extracted/activitywatch"
for component in aw-server-rust aw-watcher-afk aw-watcher-window; do
  if [ ! -d "$SOURCE/$component" ]; then
    echo "El archivo oficial no contiene $component." >&2
    exit 1
  fi
done

/bin/mkdir -p "$DESTINATION"
for component in aw-server-rust aw-watcher-afk aw-watcher-window; do
  STAGED_COMPONENT="$WORK/$component"
  /usr/bin/ditto --noextattr "$SOURCE/$component" "$STAGED_COMPONENT"
  /bin/rm -rf "$DESTINATION/$component"
  /bin/mv "$STAGED_COMPONENT" "$DESTINATION/$component"
done

echo "ActivityWatch $VERSION instalado y verificado en $DESTINATION"
