#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.0.1}"
TAG="${TAG:-v$VERSION}"
DMG="$ROOT/Releases/GitHub/$VERSION/VPass-$VERSION.dmg"
NOTES_FILE="$ROOT/Releases/Appcast/VPass-$VERSION.dmg.md"
ASSETS=("$DMG")

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

for delta in "$ROOT"/Releases/Appcast/*.delta; do
  [[ -f "$delta" ]] || continue
  ASSETS+=("$delta")
done

RELEASE_ARGS=(
  "$TAG"
  "${ASSETS[@]}"
  --repo vsvanshi/vpass
  --title "VPass $VERSION"
)

if [[ -f "$NOTES_FILE" ]]; then
  RELEASE_ARGS+=(--notes-file "$NOTES_FILE")
else
  RELEASE_ARGS+=(--notes "VPass $VERSION release.")
fi

gh release create "${RELEASE_ARGS[@]}"
