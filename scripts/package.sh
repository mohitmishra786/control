#!/bin/bash
# Control - Package Creator
# Usage: ./scripts/package.sh [version]
#
# Creates a distributable .pkg installer

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

VERSION="${1:-1.0.0}"
PKG_NAME="Control-${VERSION}"
BUILD_DIR="$PROJECT_DIR/.build/package"
OUTPUT="$PROJECT_DIR/dist/${PKG_NAME}.pkg"

echo "Creating Control package v${VERSION}..."

# Ensure release build
"$SCRIPT_DIR/build.sh" release

# Clean and create package directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/usr/local/bin"
mkdir -p "$BUILD_DIR/Library/LaunchAgents"
mkdir -p "$PROJECT_DIR/dist"

# Copy binary
cp "$PROJECT_DIR/.build/release/control" "$BUILD_DIR/usr/local/bin/control"
cp "$PROJECT_DIR/ctl" "$BUILD_DIR/usr/local/bin/ctl"
chmod +x "$BUILD_DIR/usr/local/bin/"*

# Copy LaunchAgent plist
if [[ -f "$PROJECT_DIR/launchd/com.control.daemon.plist" ]]; then
    cp "$PROJECT_DIR/launchd/com.control.daemon.plist" \
       "$BUILD_DIR/Library/LaunchAgents/"
fi

# Create package
pkgbuild \
    --root "$BUILD_DIR" \
    --identifier "com.control.pkg" \
    --version "$VERSION" \
    --install-location "/" \
    "$OUTPUT"

echo "Package created: $OUTPUT"

# Calculate checksum
shasum -a 256 "$OUTPUT"
