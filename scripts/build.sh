#!/bin/bash
# Control - Build Script
# Usage: ./scripts/build.sh [debug|release]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default to debug
BUILD_TYPE="${1:-debug}"

echo "Building Control ($BUILD_TYPE)..."
cd "$PROJECT_DIR"

case "$BUILD_TYPE" in
    debug)
        swift build
        echo "Build complete: .build/debug/control"
        ;;
    release)
        swift build -c release
        echo "Build complete: .build/release/control"
        ;;
    clean)
        swift package clean
        rm -rf .build
        echo "Clean complete"
        ;;
    *)
        echo "Usage: $0 [debug|release|clean]"
        exit 1
        ;;
esac
