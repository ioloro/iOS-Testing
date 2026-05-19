#!/usr/bin/env bash
# check-version-drift.sh
# Verifies that package.json, SKILL.md frontmatter, and the CLI's
# CommandConfiguration.version all reference the same version string.
# Run in CI on every PR.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PKG_VERSION=$(grep -E '"version":' package.json | head -1 | sed -E 's/.*"version": *"([^"]+)".*/\1/')
SKILL_VERSION=$(grep -E '^version:' skills/ios-testing/SKILL.md | head -1 | sed -E 's/^version: *"?([^"]+)"?.*/\1/')
CLI_VERSION=$(grep -E 'version: "[^"]+"' cli/Sources/iostesting/Commands/RootCommand.swift | head -1 | sed -E 's/.*version: *"([^"]+)".*/\1/')
CHANGELOG_TOP=$(grep -E '^## \[' CHANGELOG.md | head -1 | sed -E 's/^## \[([^]]+)\].*/\1/')

echo "package.json:     $PKG_VERSION"
echo "SKILL.md:         $SKILL_VERSION"
echo "RootCommand.swift: $CLI_VERSION"
echo "CHANGELOG.md top: $CHANGELOG_TOP"

failed=0
if [[ "$PKG_VERSION" != "$SKILL_VERSION" ]]; then
  echo "DRIFT: package.json ($PKG_VERSION) vs skill ($SKILL_VERSION)" >&2
  failed=1
fi
if [[ "$PKG_VERSION" != "$CLI_VERSION" ]]; then
  echo "DRIFT: package.json ($PKG_VERSION) vs CLI ($CLI_VERSION)" >&2
  failed=1
fi
if [[ "$PKG_VERSION" != "$CHANGELOG_TOP" ]]; then
  echo "DRIFT: package.json ($PKG_VERSION) vs CHANGELOG top ($CHANGELOG_TOP)" >&2
  failed=1
fi

if [[ $failed -eq 0 ]]; then
  echo "OK: all version markers at $PKG_VERSION"
fi
exit $failed
