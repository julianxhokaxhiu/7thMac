#!/bin/bash
# =============================================================================
# build_app.sh  —  Assembles 7thHeaven.app from components
#
# Prerequisites:
#   1. Wine runtime extracted from Gcenx build placed at:
#      ./wine_runtime/   (the contents of the tar.xz from Gcenx releases)
#   2. Run this script from the repo root
#
# Usage:
#   ./build_app.sh [--sign "Developer ID Application: Your Name (TEAMID)"] [--dmg]
#
# Output:
#   ./dist/7thHeaven.app
# =============================================================================

set -euo pipefail

if [[ "$_BUILD_BRANCH" == "refs/heads/master" || "$_BUILD_BRANCH" == "refs/tags/canary" ]]; then
  export _IS_BUILD_CANARY="true"
  export _IS_GITHUB_RELEASE="true"
elif [[ "$_BUILD_BRANCH" == refs/tags/* ]]; then
  _BUILD_VERSION="${_BUILD_VERSION%-*}.0"
  export _BUILD_VERSION
  export _IS_GITHUB_RELEASE="true"
fi
export _RELEASE_VERSION="v${_BUILD_VERSION}"

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
APP_NAME="7thHeaven"
BUNDLE_ID="com.tsunamods.7thHeaven"
VERSION="${_BUILD_VERSION:-0.0.0}"
SIGN_IDENTITY=""
BUILD_DMG="false"

SCRIPT_DIR="$(pwd)"
WINE_BASE="$SCRIPT_DIR/wine_runtime"
WINE_SRC="$WINE_BASE/Contents/Resources/wine"   # resolved later to support multiple archive layouts
DIST="$SCRIPT_DIR/.dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"

echo "--------------------------------------------------"
echo "RELEASE VERSION: $_RELEASE_VERSION"
echo "--------------------------------------------------"

echo "_BUILD_VERSION=${_BUILD_VERSION}" >> "${GITHUB_ENV}"
echo "_RELEASE_VERSION=${_RELEASE_VERSION}" >> "${GITHUB_ENV}"
echo "_IS_BUILD_CANARY=${_IS_BUILD_CANARY}" >> "${GITHUB_ENV}"
echo "_IS_GITHUB_RELEASE=${_IS_GITHUB_RELEASE}" >> "${GITHUB_ENV}"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --sign)
      SIGN_IDENTITY="${2:-}"
      shift 2
      ;;
    --dmg)
      BUILD_DMG="true"
      shift
      ;;
    *)
      echo "ERROR: Unknown argument: $1"
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Download and extract Wine runtime if needed
# ---------------------------------------------------------------------------
resolve_wine_src() {
  # Different Wine archives can unpack in different layouts depending on release packaging.
  local candidate
  for candidate in \
    "$WINE_BASE/Contents/Resources/wine" \
    "$WINE_BASE" \
    "$WINE_BASE/Contents/Resources/wine/Contents/Resources/wine"; do
    if [ -f "$candidate/bin/wine" ]; then
      WINE_SRC="$candidate"
      return 0
    fi
  done

  return 1
}

download_wine_runtime() {
  local wine_url="https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.4/wine-staging-11.4-osx64.tar.xz"
  local wine_archive="$SCRIPT_DIR/wine-staging-11.4-osx64.tar.xz"

  echo "→ Downloading Wine runtime..."
  if ! command -v curl &> /dev/null; then
    echo "ERROR: curl is required but not installed"
    exit 1
  fi

  if curl -fsSL --progress-bar -o "$wine_archive" "$wine_url"; then
    echo "✓ Download complete"
  else
    echo "ERROR: Failed to download Wine runtime from: $wine_url"
    exit 1
  fi

  echo "→ Extracting Wine runtime (this may take a few minutes)..."
  mkdir -p "$WINE_BASE"

  if tar -xf "$wine_archive" -C "$WINE_BASE" --strip-components=1; then
    echo "✓ Extraction complete"
    rm -f "$wine_archive"  # clean up archive after successful extraction

    if ! resolve_wine_src; then
      echo "ERROR: Wine runtime extracted but wine binary could not be located"
      echo "Checked under: $WINE_BASE"
      exit 1
    fi

    echo "✓ Resolved Wine runtime path: $WINE_SRC"
  else
    echo "ERROR: Failed to extract Wine runtime"
    rm -f "$wine_archive"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Validate prerequisites
# ---------------------------------------------------------------------------
if [ ! -d "$WINE_BASE" ]; then
  echo "Wine runtime not found. Downloading..."
  download_wine_runtime
elif ! resolve_wine_src; then
  echo "Wine runtime directory exists but is incomplete. Re-downloading..."
  rm -rf "$WINE_BASE"
  download_wine_runtime
fi

echo "→ Using Wine runtime path: $WINE_SRC"

if [ ! -f "$WINE_SRC/bin/wine" ]; then
  echo "ERROR: wine binary not found in $WINE_SRC/bin/"
  echo "The Wine runtime extraction may have failed. Try manually deleting wine_runtime/ and running this script again."
  exit 1
fi


# ---------------------------------------------------------------------------
# Clean previous build
# ---------------------------------------------------------------------------
echo "→ Cleaning previous build..."
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" \
         "$CONTENTS/Resources" \
         "$CONTENTS/Resources/wine"

# ---------------------------------------------------------------------------
# Copy Wine runtime
# ---------------------------------------------------------------------------
echo "→ Copying Wine runtime (this may take a moment)..."
cp -r "$WINE_SRC/." "$CONTENTS/Resources/wine/"
echo "   Wine size: $(du -sh "$CONTENTS/Resources/wine" | cut -f1)"

# ---------------------------------------------------------------------------
# Compile Swift launcher
# ---------------------------------------------------------------------------
echo "→ Compiling Swift launcher..."
swiftc -O -o "$CONTENTS/MacOS/7thHeaven" "$SCRIPT_DIR/launcher.swift"
chmod +x "$CONTENTS/MacOS/7thHeaven"
echo "   Launcher compiled successfully."

# ---------------------------------------------------------------------------
# Copy Info.plist
# ---------------------------------------------------------------------------
echo "→ Writing Info.plist..."
cp "$SCRIPT_DIR/Info.plist" "$CONTENTS/Info.plist"

# Set bundle version fields from _BUILD_VERSION (or default)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"

# ---------------------------------------------------------------------------
# Copy icon
# ---------------------------------------------------------------------------
echo "→ Writing AppIcon.icns..."
cp "$SCRIPT_DIR/app.icns" "$CONTENTS/Resources/AppIcon.icns"

# ---------------------------------------------------------------------------
# Fix executable permissions on all Wine binaries
# ---------------------------------------------------------------------------
echo "→ Fixing Wine binary permissions..."
find "$CONTENTS/Resources/wine/bin" -type f -exec chmod +x {} \;
find "$CONTENTS/Resources/wine/lib" -name "*.dylib" -type f -exec chmod 755 {} \; 2>/dev/null || true

# ---------------------------------------------------------------------------
# Remove Wine's quarantine attributes (prevents Gatekeeper blocking Wine libs)
# ---------------------------------------------------------------------------
echo "→ Stripping quarantine attributes..."
xattr -cr "$APP" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Code signing
# ---------------------------------------------------------------------------
if [ -n "$SIGN_IDENTITY" ]; then
  echo "→ Signing with: $SIGN_IDENTITY"

  # Sign Wine dylibs first (inside-out signing)
  find "$CONTENTS/Resources/wine/lib" -name "*.dylib" | while read -r lib; do
    codesign --force --sign "$SIGN_IDENTITY" --entitlements "$SCRIPT_DIR/entitlements.plist" "$lib" 2>/dev/null || true
  done

  # Sign Wine binaries
  find "$CONTENTS/Resources/wine/bin" -type f | while read -r bin; do
    codesign --force --sign "$SIGN_IDENTITY" --entitlements "$SCRIPT_DIR/entitlements.plist" "$bin" 2>/dev/null || true
  done

  # Sign the whole bundle
  codesign \
    --force \
    --options runtime \
    --entitlements "$SCRIPT_DIR/entitlements.plist" \
    --sign "$SIGN_IDENTITY" \
    "$APP"

  echo "   Signed successfully."
  echo ""
  echo "→ To notarize for distribution:"
  echo "   zip -r dist/7thHeaven.zip dist/7thHeaven.app"
  echo "   xcrun notarytool submit dist/7thHeaven.zip \\"
  echo "     --apple-id you@email.com \\"
  echo "     --team-id YOURTEAMID \\"
  echo "     --password APP_SPECIFIC_PASS \\"
  echo "     --wait"
  echo "   xcrun stapler staple dist/7thHeaven.app"
else
  echo "→ Ad-hoc signing with entitlements (required for Apple Silicon)..."

  # Sign Wine dylibs first (inside-out signing)
  find "$CONTENTS/Resources/wine/lib" -name "*.dylib" | while read -r lib; do
    codesign --force --sign - --entitlements "$SCRIPT_DIR/entitlements.plist" "$lib" 2>/dev/null || true
  done

  # Sign Wine binaries
  find "$CONTENTS/Resources/wine/bin" -type f | while read -r bin; do
    codesign --force --sign - --entitlements "$SCRIPT_DIR/entitlements.plist" "$bin" 2>/dev/null || true
  done

  # Sign the whole bundle with entitlements (critical for Wine on Apple Silicon)
  codesign \
    --force \
    --sign - \
    --entitlements "$SCRIPT_DIR/entitlements.plist" \
    "$APP"

  echo "   Ad-hoc signed with Wine entitlements."
  echo "   On first launch: Right-click → Open to bypass Gatekeeper."
fi

# ---------------------------------------------------------------------------
# Build DMG (optional)
# ---------------------------------------------------------------------------
if [ "$BUILD_DMG" = "true" ]; then
  if ! command -v hdiutil &> /dev/null; then
    echo "ERROR: hdiutil not found. DMG creation requires macOS."
    exit 1
  fi

  echo "→ Building DMG..."
  DMG_STAGE="$DIST/dmg"
  DMG_PATH="$DIST/$APP_NAME.dmg"
  rm -rf "$DMG_STAGE"
  mkdir -p "$DMG_STAGE"
  cp -R "$APP" "$DMG_STAGE/"
  hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH"
  echo "   DMG created at: $DMG_PATH"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================"
echo "  ✓ Build complete!"
echo "============================================"
echo ""
echo "  App bundle : $APP"
echo "  Total size : $(du -sh "$APP" | cut -f1)"
echo ""
