#!/bin/bash
# Control - Code Signing Script
# Usage: ./scripts/sign.sh [identity]
#
# Requires: Apple Developer certificate in Keychain

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default signing identity (use - for ad-hoc)
IDENTITY="${1:--}"
BINARY="$PROJECT_DIR/.build/release/control"
ENTITLEMENTS="$PROJECT_DIR/control.entitlements"

if [[ ! -f "$BINARY" ]]; then
    echo "Error: Release binary not found. Run: ./scripts/build.sh release"
    exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "Warning: Entitlements file not found"
    ENTITLEMENTS=""
fi

echo "Signing Control binary..."

if [[ -n "$ENTITLEMENTS" ]]; then
    codesign --force --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$IDENTITY" \
        "$BINARY"
else
    codesign --force --options runtime \
        --sign "$IDENTITY" \
        "$BINARY"
fi

echo "Verifying signature..."
codesign --verify --verbose "$BINARY"

echo "Code signing complete"

# Show signature info
codesign -dvv "$BINARY" 2>&1 | head -10
