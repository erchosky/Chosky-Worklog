#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Chosky Worklog.app"
DMG="$DIST/Chosky-Worklog-arm64.dmg"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/chosky-dmg-stage.XXXXXX")"
MOUNT_POINT=""
SAMPLES="$DIST/sample-reports"
AUDIT="$DIST/audit"

cleanup() {
  if [ -n "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    rmdir "$MOUNT_POINT" 2>/dev/null || true
  fi
  rm -rf "$STAGE"
}
trap cleanup EXIT

mkdir -p "$SAMPLES" "$AUDIT/test-results" "$AUDIT/dependency-audit" "$AUDIT/license-report"
"$ROOT/scripts/chosky/build-app.sh"
"$ROOT/scripts/chosky/run-tests.sh" | tee "$AUDIT/test-results/native-tests.txt"
"$ROOT/scripts/chosky/run-integration-tests.sh" | tee "$AUDIT/test-results/integration-tests.txt"
"$ROOT/scripts/chosky/run-sharing-tests.sh" | tee "$AUDIT/test-results/sharing-tests.txt"

ditto --noextattr "$APP" "$STAGE/Chosky Worklog.app"
xattr -cr "$STAGE/Chosky Worklog.app"
xattr -d com.apple.FinderInfo "$STAGE/Chosky Worklog.app" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "$STAGE/Chosky Worklog.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create \
  -volname "Chosky Worklog" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"
MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/chosky-dmg.XXXXXX")"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_POINT" "$DMG" >/dev/null
codesign --verify --deep --strict --verbose=4 \
  "$MOUNT_POINT/Chosky Worklog.app" \
  > "$AUDIT/test-results/dmg-codesign.txt" 2>&1
hdiutil detach "$MOUNT_POINT" >/dev/null
rmdir "$MOUNT_POINT"
MOUNT_POINT=""

"$ROOT/scripts/chosky/generate-samples.sh" "$SAMPLES"

if command -v cupsfilter >/dev/null 2>&1; then
  cupsfilter "$ROOT/docs/INSTALLATION.md" > "$DIST/installation-guide.pdf" 2> "$AUDIT/test-results/cupsfilter.log"
fi

cp "$ROOT/docs/FINAL_AUDIT.md" "$AUDIT/FINAL_AUDIT.md"
cp "$ROOT/docs/AUDIT_2026-07-31.md" "$AUDIT/AUDIT_2026-07-31.md"
cp "$ROOT/docs/DEPENDENCIES.md" "$AUDIT/dependency-audit/DEPENDENCIES.md"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$AUDIT/license-report/THIRD_PARTY_NOTICES.md"

/usr/bin/python3 - "$DIST/build-info.json" "$ROOT" <<'PY'
import json
import platform
import subprocess
import sys
from datetime import datetime, timezone

output, root = sys.argv[1:]
data = {
    "product": "Chosky Worklog",
    "bundleIdentifier": "com.chosky.worklog",
    "version": "0.1.0",
    "architecture": platform.machine(),
    "builtAt": datetime.now(timezone.utc).isoformat(),
    "gitCommit": subprocess.check_output(
        ["git", "-C", root, "rev-parse", "HEAD"], text=True
    ).strip(),
    "activityWatchVersion": "0.14.0b2",
    "activityWatchAssetSHA256": "33380f395ac873bc28da4453c63365bbae1c7d06dc44cfceafe2adbbe707ed54",
    "signing": "ad-hoc",
}
with open(output, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, ensure_ascii=False, sort_keys=True)
    handle.write("\n")
PY

(
  cd "$DIST"
  checksum_files=("Chosky-Worklog-arm64.dmg" "build-info.json")
  if [ -f "installation-guide.pdf" ]; then
    checksum_files+=("installation-guide.pdf")
  fi
  shasum -a 256 "${checksum_files[@]}" > checksums.txt
  find "Chosky Worklog.app" -type f -print0 \
    | sort -z \
    | xargs -0 shasum -a 256 >> checksums.txt
)

spctl --assess --type execute --verbose=4 "$APP" > "$AUDIT/test-results/gatekeeper.txt" 2>&1 || true
for _ in 1 2 3 4 5; do
  xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
  if codesign --verify --deep --strict --verbose=4 "$APP" > "$AUDIT/test-results/codesign.txt" 2>&1; then
    break
  fi
done
echo "$DMG"
