#!/bin/bash
# ctl - Short alias wrapper for Control
# Usage: ctl <command> [options]

# Find control binary
CONTROL_BIN=""

# Check common locations
if [[ -x "/usr/local/bin/control" ]]; then
    CONTROL_BIN="/usr/local/bin/control"
elif [[ -x "${HOME}/.local/bin/control" ]]; then
    CONTROL_BIN="${HOME}/.local/bin/control"
elif command -v control &> /dev/null; then
    CONTROL_BIN="$(command -v control)"
else
    # Try relative to script location (dev mode)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -x "${SCRIPT_DIR}/.build/release/control" ]]; then
        CONTROL_BIN="${SCRIPT_DIR}/.build/release/control"
    elif [[ -x "${SCRIPT_DIR}/.build/debug/control" ]]; then
        CONTROL_BIN="${SCRIPT_DIR}/.build/debug/control"
    fi
fi

if [[ -z "$CONTROL_BIN" ]]; then
    echo "Error: control binary not found"
    echo "Install Control with: ./install.sh"
    exit 1
fi

# Pass all arguments to control
exec "$CONTROL_BIN" "$@"
