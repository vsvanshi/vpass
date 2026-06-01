#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.0.1}"
TAG="${TAG:-v$VERSION}"
DMG="$ROOT/Releases/GitHub/$VERSION/VPass-$VERSION.dmg"

cd "$ROOT"

if [[ ! -f "$DMG" ]]; then
  echo "Missing release DMG: $DMG" >&2
  echo "Run: VERSION=$VERSION NOTARY_PROFILE=vpass-notary ./scripts/build-github-release.sh" >&2
  exit 1
fi

git diff --quiet -- docs/appcast.xml || {
  echo "docs/appcast.xml has uncommitted changes. Commit and push it before publishing." >&2
  exit 1
}

git rev-parse "$TAG" >/dev/null 2>&1 || git tag -a "$TAG" -m "VPass $VERSION"
git push origin "$TAG"

gh release create "$TAG" "$DMG" \
  --repo vsvanshi/vpass \
  --title "VPass $VERSION" \
  --notes "Initial public VPass release."
