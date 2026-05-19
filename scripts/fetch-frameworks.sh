#!/usr/bin/env bash
# fetch-frameworks.sh
# Clones facebook/idb at a pinned SHA, applies our compat patches, builds the
# four Meta-licensed frameworks (FBControlCore, FBSimulatorControl,
# FBDeviceControl, XCTestBootstrap), and drops them in cli/Frameworks/.
#
# Usage:
#   scripts/fetch-frameworks.sh [<idb-sha>]
#
# Requirements:
#   - Xcode 14+ (private SPI surface tracks Xcode majors; pin in CI)
#   - brew install xcodegen
#
# Patches applied (see scripts/patches/):
#   - idb-xcode-select-macos26.patch — falls back to `xcode-select -p` when
#     /var/db/xcode_select_link is missing (macOS 26+ default state).

set -euo pipefail

IDB_SHA="${1:-}"
if [[ -z "$IDB_SHA" ]]; then
  echo "error: pass an idb commit SHA as the first argument." >&2
  echo "  Find a known-good SHA on https://github.com/facebook/idb/commits/main" >&2
  exit 64
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${TMPDIR:-/tmp}/iostesting-idb-build"
DEST="${REPO_ROOT}/cli/Frameworks"
PATCH_DIR="${REPO_ROOT}/scripts/patches"

echo "==> Cloning facebook/idb @ ${IDB_SHA}"
rm -rf "$WORK_DIR"
git clone --filter=blob:none https://github.com/facebook/idb.git "$WORK_DIR"
( cd "$WORK_DIR" && git checkout "$IDB_SHA" )

echo "==> Applying patches"
shopt -s nullglob
for patch in "$PATCH_DIR"/*.patch; do
  echo "    applying $(basename "$patch")"
  ( cd "$WORK_DIR" && git apply "$patch" )
done
shopt -u nullglob

echo "==> Verifying tooling"
command -v xcodegen >/dev/null || { echo "install xcodegen: brew install xcodegen"; exit 1; }

echo "==> Building frameworks (XcodeGen + idb build.sh)"
( cd "$WORK_DIR" && ./build.sh build frameworks )

mkdir -p "$DEST"
# idb's build.sh produces Debug artifacts when invoked as `build frameworks`.
# Switch to Release here if/when distribution needs stripped binaries.
for fw in FBControlCore FBSimulatorControl FBDeviceControl XCTestBootstrap; do
  src="$WORK_DIR/Build/Products/Debug/${fw}.framework"
  if [[ ! -d "$src" ]]; then
    echo "error: expected framework not found: $src" >&2
    exit 1
  fi
  rm -rf "${DEST:?}/${fw}.framework"
  cp -R "$src" "$DEST/"
  echo "    copied ${fw}.framework"
done

echo "==> Done. Frameworks in $DEST"
echo "    Pinned SHA: $IDB_SHA"
echo "    Patches applied from $PATCH_DIR"
echo "    THIRD_PARTY_LICENSES.txt already covers idb MIT."
