#!/bin/bash
# Control - macOS Power User Interaction Manager
# Installer Script
#
# Usage: ./install.sh [--prefix=/usr/local] [--config] [--uninstall]
#
# Options:
#   --prefix=PATH   Installation prefix (default: /usr/local)
#   --config        Copy default configuration to ~/.config/control/
#   --uninstall     Remove installed files

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Defaults
PREFIX="/usr/local"
INSTALL_CONFIG=false
UNINSTALL=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
for arg in "$@"; do
    case $arg in
        --prefix=*)
            PREFIX="${arg#*=}"
            ;;
        --config)
            INSTALL_CONFIG=true
            ;;
        --uninstall)
            UNINSTALL=true
            ;;
        --help|-h)
            echo "Control Installer"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --prefix=PATH   Installation prefix (default: /usr/local)"
            echo "  --config        Copy default configuration to ~/.config/control/"
            echo "  --uninstall     Remove installed files"
            echo "  --help          Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $arg${NC}"
            exit 1
            ;;
    esac
done

# Paths
BIN_DIR="${PREFIX}/bin"
CONFIG_DIR="${HOME}/.config/control"
LAUNCHD_DIR="${HOME}/Library/LaunchAgents"

print_step() {
    echo -e "${BLUE}=>${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check requirements
check_requirements() {
    print_step "Checking requirements..."
    
    # Check macOS version
    OS_VERSION=$(sw_vers -productVersion)
    MAJOR_VERSION=$(echo "$OS_VERSION" | cut -d. -f1)
    
    if [[ $MAJOR_VERSION -lt 12 ]]; then
        print_error "Control requires macOS 12.0 or later (found: $OS_VERSION)"
        exit 1
    fi
    print_success "macOS version: $OS_VERSION"
    
    # Check for Swift
    if command -v swift &> /dev/null; then
        SWIFT_VERSION=$(swift --version | head -1)
        print_success "Swift: $SWIFT_VERSION"
    else
        print_warning "Swift not found - cannot build from source"
    fi
}

# Build from source
build() {
    print_step "Building Control..."
    
    if [[ ! -f "${SCRIPT_DIR}/Package.swift" ]]; then
        print_error "Package.swift not found. Are you running from the source directory?"
        exit 1
    fi
    
    cd "${SCRIPT_DIR}"
    
    # Build release
    swift build -c release
    
    if [[ ! -f ".build/release/control" ]]; then
        print_error "Build failed - binary not found"
        exit 1
    fi
    
    print_success "Build complete"
}

# Install binary
install_binary() {
    print_step "Installing binary to ${BIN_DIR}..."
    
    # Create bin directory
    mkdir -p "${BIN_DIR}"
    
    # Copy binary
    cp "${SCRIPT_DIR}/.build/release/control" "${BIN_DIR}/control"
    chmod +x "${BIN_DIR}/control"
    
    # Copy ctl wrapper if exists
    if [[ -f "${SCRIPT_DIR}/ctl" ]]; then
        cp "${SCRIPT_DIR}/ctl" "${BIN_DIR}/ctl"
        chmod +x "${BIN_DIR}/ctl"
        print_success "Installed: ${BIN_DIR}/ctl"
    fi
    
    print_success "Installed: ${BIN_DIR}/control"
}

# Install configuration
install_config() {
    print_step "Installing configuration to ${CONFIG_DIR}..."
    
    mkdir -p "${CONFIG_DIR}"
    
    # Copy default config
    if [[ -f "${SCRIPT_DIR}/config/default.toml" ]]; then
        if [[ ! -f "${CONFIG_DIR}/control.toml" ]]; then
            cp "${SCRIPT_DIR}/config/default.toml" "${CONFIG_DIR}/control.toml"
            print_success "Installed: ${CONFIG_DIR}/control.toml"
        else
            print_warning "Config already exists, skipping"
        fi
    fi
    
    # Copy presets
    if [[ -d "${SCRIPT_DIR}/config/presets" ]]; then
        mkdir -p "${CONFIG_DIR}/presets"
        cp -r "${SCRIPT_DIR}/config/presets/"* "${CONFIG_DIR}/presets/" 2>/dev/null || true
        print_success "Installed presets to ${CONFIG_DIR}/presets/"
    fi
}

# Install LaunchAgent
install_launchd() {
    print_step "Installing LaunchAgent..."
    
    mkdir -p "${LAUNCHD_DIR}"
    
    # Generate plist with correct binary path
    cat > "${LAUNCHD_DIR}/com.control.daemon.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.control.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BIN_DIR}/control</string>
        <string>daemon</string>
        <string>run</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>${CONFIG_DIR}/daemon.log</string>
    <key>StandardErrorPath</key>
    <string>${CONFIG_DIR}/daemon.log</string>
</dict>
</plist>
EOF
    
    print_success "Installed: ${LAUNCHD_DIR}/com.control.daemon.plist"
}

# Uninstall
uninstall() {
    print_step "Uninstalling Control..."
    
    # Stop daemon if running
    launchctl unload "${LAUNCHD_DIR}/com.control.daemon.plist" 2>/dev/null || true
    
    # Remove files
    rm -f "${BIN_DIR}/control"
    rm -f "${BIN_DIR}/ctl"
    rm -f "${LAUNCHD_DIR}/com.control.daemon.plist"
    
    print_success "Control uninstalled"
    print_warning "Config files in ${CONFIG_DIR} were preserved"
}

# Post-install
post_install() {
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Control installed successfully!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo "Binary location: ${BIN_DIR}/control"
    echo ""
    echo "Quick start:"
    echo "  control status          # Check system status"
    echo "  control window --help   # Window management"
    echo "  control daemon start    # Start background service"
    echo ""
    
    # Check if bin dir is in PATH
    if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
        print_warning "${BIN_DIR} is not in your PATH"
        echo "  Add to your shell config:"
        echo "    export PATH=\"${BIN_DIR}:\$PATH\""
    fi
}

# Main
main() {
    echo ""
    echo -e "${BLUE}Control Installer${NC}"
    echo "======================================"
    echo ""
    
    if $UNINSTALL; then
        uninstall
        exit 0
    fi
    
    check_requirements
    build
    install_binary
    
    if $INSTALL_CONFIG; then
        install_config
    fi
    
    install_launchd
    post_install
}

main
