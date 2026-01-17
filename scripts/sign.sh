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

# Determine runtime options based on identity
# Hardened runtime only works with real signing identities, not ad-hoc (-)
if [[ "$IDENTITY" == "-" || -z "$IDENTITY" ]]; then
    RUNTIME_OPTS=""
else
    RUNTIME_OPTS="--options runtime"
fi

if [[ ! -f "$BINARY" ]]; then
    echo "Error: Release binary not found. Run: ./scripts/build.sh release"
    exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "Warning: Entitlements file not found"
    ENTITLEMENTS=""
fi

echo "Signing Control binary..."
echo "Identity: $IDENTITY"
echo "Runtime options: ${RUNTIME_OPTS:-none}"

if [[ -n "$ENTITLEMENTS" ]]; then
    # shellcheck disable=SC2086
    codesign --force $RUNTIME_OPTS \
        --entitlements "$ENTITLEMENTS" \
        --sign "$IDENTITY" \
        "$BINARY"
else
    # shellcheck disable=SC2086
    codesign --force $RUNTIME_OPTS \
        --sign "$IDENTITY" \
        "$BINARY"
fi

echo "Verifying signature..."
codesign --verify --verbose "$BINARY"

echo "Code signing complete"

# Show signature info
codesign -dvv "$BINARY" 2>&1 | head -10
