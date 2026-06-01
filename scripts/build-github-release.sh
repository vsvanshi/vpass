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
DMG_NAME="VPass-$VERSION.dmg"
DIST_DIR="$ROOT/Releases/GitHub/$VERSION"
WORK_APP="$DIST_DIR/VPass.app"
DMG_STAGING="$DIST_DIR/dmg-root"
FINAL_DMG="$DIST_DIR/$DMG_NAME"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/vsvanshi/vpass/releases/download/$TAG/}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
PROCESSED_ENTITLEMENTS="$DIST_DIR/VPass.entitlements"

echo "Building VPass $VERSION ($BUILD)"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR" "$APPCAST_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CURRENT_PROJECT_VERSION="$BUILD" \
  MARKETING_VERSION="$VERSION"

BUILT_PRODUCTS_DIR="$(
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings \
    | awk -F' = ' '/BUILT_PRODUCTS_DIR = / {print $2; exit}'
)"
BUILT_APP="$BUILT_PRODUCTS_DIR/VPass.app"

ditto "$BUILT_APP" "$WORK_APP"
sed "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.varunsuryawanshi.vpass/g" "$ROOT/AppStore/VPass.entitlements" > "$PROCESSED_ENTITLEMENTS"

if [[ -d "$WORK_APP/Contents/Frameworks/Sparkle.framework" ]]; then
  SPARKLE_FRAMEWORK="$WORK_APP/Contents/Frameworks/Sparkle.framework"
  for item in \
    "$SPARKLE_FRAMEWORK/Versions/Current/Autoupdate" \
    "$SPARKLE_FRAMEWORK/Versions/Current/Updater.app" \
    "$SPARKLE_FRAMEWORK/Versions/Current/XPCServices/Downloader.xpc" \
    "$SPARKLE_FRAMEWORK/Versions/Current/XPCServices/Installer.xpc" \
    "$SPARKLE_FRAMEWORK/Versions/Current"; do
    if [[ -e "$item" ]]; then
      codesign \
        --force \
        --timestamp \
        --options runtime \
        --preserve-metadata=identifier,entitlements,flags \
        --sign "$SIGNING_IDENTITY" \
        "$item"
    fi
  done
fi

codesign \
  --force \
  --timestamp \
  --options runtime \
  --entitlements "$PROCESSED_ENTITLEMENTS" \
  --sign "$SIGNING_IDENTITY" \
  "$WORK_APP"
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
elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "Submitting notarization request with keychain profile $NOTARY_PROFILE"
  xcrun notarytool submit "$PRE_NOTARY_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

  xcrun stapler staple "$WORK_APP"
  xcrun stapler validate "$WORK_APP"
else
  echo "Skipping notarization because NOTARY_PROFILE or APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_SPECIFIC_PASSWORD are missing."
fi

rm -rf "$DMG_STAGING" "$FINAL_DMG"
mkdir -p "$DMG_STAGING"
ditto "$WORK_APP" "$DMG_STAGING/VPass.app"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
  -volname "VPass $VERSION" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$FINAL_DMG"

codesign \
  --force \
  --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$FINAL_DMG"

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  echo "Submitting DMG notarization request"
  xcrun notarytool submit "$FINAL_DMG" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait

  xcrun stapler staple "$FINAL_DMG"
  xcrun stapler validate "$FINAL_DMG"
elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "Submitting DMG notarization request with keychain profile $NOTARY_PROFILE"
  xcrun notarytool submit "$FINAL_DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

  xcrun stapler staple "$FINAL_DMG"
  xcrun stapler validate "$FINAL_DMG"
fi

spctl --assess --type open --verbose=4 "$FINAL_DMG" || true
cp "$FINAL_DMG" "$APPCAST_DIR/$DMG_NAME"

if [[ ! -f "$APPCAST_DIR/$DMG_NAME.md" ]]; then
  cat > "$APPCAST_DIR/$DMG_NAME.md" <<NOTES
# VPass $VERSION

- Release notes go here.
NOTES
fi

"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --link "https://github.com/vsvanshi/vpass" \
  --maximum-versions 1 \
  -o "$ROOT/docs/appcast.xml" \
  "$APPCAST_DIR"

echo
echo "Release DMG: $FINAL_DMG"
echo "Appcast: $ROOT/docs/appcast.xml"
echo
echo "Next steps:"
echo "1. Commit and push docs/appcast.xml."
echo "2. Create GitHub release $TAG."
echo "3. Upload $FINAL_DMG as the release asset."
