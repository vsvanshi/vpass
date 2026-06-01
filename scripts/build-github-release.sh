#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/VPass.xcodeproj"
SCHEME="VPass"
CONFIGURATION="Release"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
APPCAST_DIR="$ROOT/Releases/Appcast"

cd "$ROOT"

if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
  swift package resolve
fi

MARKETING_VERSION="$(
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings \
    | awk -F' = ' '/MARKETING_VERSION = / {print $2; exit}'
)"
BUILD_NUMBER="$(
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings \
    | awk -F' = ' '/CURRENT_PROJECT_VERSION = / {print $2; exit}'
)"

VERSION="${VERSION:-$MARKETING_VERSION}"
BUILD="${BUILD:-$BUILD_NUMBER}"
TAG="${TAG:-v$VERSION}"
ZIP_NAME="VPass-$VERSION.zip"
DIST_DIR="$ROOT/Releases/GitHub/$VERSION"
WORK_APP="$DIST_DIR/VPass.app"
FINAL_ZIP="$DIST_DIR/$ZIP_NAME"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/vsvanshi/vpass/releases/download/$TAG}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"

echo "Building VPass $VERSION ($BUILD)"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR" "$APPCAST_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  build \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  MARKETING_VERSION="$VERSION"

BUILT_PRODUCTS_DIR="$(
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings \
    | awk -F' = ' '/BUILT_PRODUCTS_DIR = / {print $2; exit}'
)"
BUILT_APP="$BUILT_PRODUCTS_DIR/VPass.app"

ditto "$BUILT_APP" "$WORK_APP"
codesign --verify --deep --strict --verbose=2 "$WORK_APP"

PRE_NOTARY_ZIP="$DIST_DIR/VPass-$VERSION-notary.zip"
ditto -c -k --keepParent "$WORK_APP" "$PRE_NOTARY_ZIP"

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  echo "Submitting notarization request"
  xcrun notarytool submit "$PRE_NOTARY_ZIP" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait

  xcrun stapler staple "$WORK_APP"
  xcrun stapler validate "$WORK_APP"
else
  echo "Skipping notarization because APPLE_ID, APPLE_TEAM_ID, or APPLE_APP_SPECIFIC_PASSWORD is missing."
fi

ditto -c -k --keepParent "$WORK_APP" "$FINAL_ZIP"
cp "$FINAL_ZIP" "$APPCAST_DIR/$ZIP_NAME"

if [[ ! -f "$APPCAST_DIR/$ZIP_NAME.md" ]]; then
  cat > "$APPCAST_DIR/$ZIP_NAME.md" <<NOTES
# VPass $VERSION

- Release notes go here.
NOTES
fi

"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --link "https://github.com/vsvanshi/vpass" \
  -o "$ROOT/docs/appcast.xml" \
  "$APPCAST_DIR"

echo
echo "Release archive: $FINAL_ZIP"
echo "Appcast: $ROOT/docs/appcast.xml"
echo
echo "Next steps:"
echo "1. Commit and push docs/appcast.xml."
echo "2. Create GitHub release $TAG."
echo "3. Upload $FINAL_ZIP as the release asset."
