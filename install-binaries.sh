#!/usr/bin/env bash
# =============================================================================
# Binary Asset Management Script for Chatimics
# Downloads and manages binary dependencies that shouldn't be in git
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Binary asset configuration
BINARY_ASSETS_DIR="binary_assets"
DOWNLOAD_BASE_URL="https://github.com/OpenVPN/easy-rsa/releases/download"
EASYRSA_VERSION="v3.1.7"

# Platform detection
detect_platform() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux) echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

# Download EasyRSA binary distribution
download_easyrsa_binaries() {
    local platform="$1"
    local target_dir="$2"
    
    log_info "Downloading EasyRSA binaries for $platform..."
    
    case "$platform" in
        "windows")
            local url="${DOWNLOAD_BASE_URL}/${EASYRSA_VERSION}/EasyRSA-${EASYRSA_VERSION}-win32.zip"
            local archive_name="EasyRSA-${EASYRSA_VERSION}-win32.zip"
            ;;
        "linux")
            local url="${DOWNLOAD_BASE_URL}/${EASYRSA_VERSION}/EasyRSA-${EASYRSA_VERSION}.tgz"
            local archive_name="EasyRSA-${EASYRSA_VERSION}.tgz"
            ;;
        "macos")
            local url="${DOWNLOAD_BASE_URL}/${EASYRSA_VERSION}/EasyRSA-${EASYRSA_VERSION}.tgz"
            local archive_name="EasyRSA-${EASYRSA_VERSION}.tgz"
            ;;
        *)
            log_error "Unsupported platform: $platform"
            return 1
            ;;
    esac
    
    # Create download directory
    mkdir -p "$target_dir"
    cd "$target_dir"
    
    # Download if not already present
    if [[ ! -f "$archive_name" ]]; then
        log_info "Downloading from: $url"
        if command -v curl >/dev/null; then
            curl -L -o "$archive_name" "$url"
        elif command -v wget >/dev/null; then
            wget -O "$archive_name" "$url"
        else
            log_error "Neither curl nor wget found. Please install one of them."
            return 1
        fi
        log_success "Downloaded $archive_name"
    else
        log_info "$archive_name already exists, skipping download"
    fi
    
    # Extract based on file type
    case "$archive_name" in
        *.zip)
            if command -v unzip >/dev/null; then
                unzip -q "$archive_name"
                log_success "Extracted $archive_name"
            else
                log_error "unzip command not found"
                return 1
            fi
            ;;
        *.tgz|*.tar.gz)
            tar -xzf "$archive_name"
            log_success "Extracted $archive_name"
            ;;
    esac
    
    cd - >/dev/null
}

# Install Node.js binary dependencies
install_node_binaries() {
    log_info "Installing Node.js dependencies..."
    
    # Install root dependencies
    if [[ -f package.json ]]; then
        npm install
        log_success "Root Node.js dependencies installed"
    fi
    
    # Install app_main dependencies
    if [[ -d app_main && -f app_main/package.json ]]; then
        cd app_main
        npm install
        cd ..
        log_success "Web client dependencies installed"
    fi
}

# Verify binary installations
verify_binaries() {
    log_info "Verifying binary installations..."
    
    local errors=0
    
    # Check Docker
    if ! command -v docker >/dev/null; then
        log_error "Docker not found"
        ((errors++))
    else
        log_success "Docker found"
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose >/dev/null && ! docker compose version >/dev/null 2>&1; then
        log_error "Docker Compose not found"
        ((errors++))
    else
        log_success "Docker Compose found"
    fi
    
    # Check Node.js
    if ! command -v node >/dev/null; then
        log_warning "Node.js not found (optional for Docker-only setup)"
    else
        log_success "Node.js found: $(node --version)"
    fi
    
    # Check npm
    if ! command -v npm >/dev/null; then
        log_warning "npm not found (optional for Docker-only setup)"
    else
        log_success "npm found: $(npm --version)"
    fi
    
    return $errors
}

# Create binary asset manifest
create_manifest() {
    local manifest_file="$BINARY_ASSETS_DIR/manifest.json"
    
    cat > "$manifest_file" << EOF
{
  "version": "1.0.0",
  "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "platform": "$(detect_platform)",
  "assets": {
    "easyrsa": {
      "version": "$EASYRSA_VERSION",
      "source": "https://github.com/OpenVPN/easy-rsa",
      "purpose": "VPN PKI management utilities"
    },
    "node_modules": {
      "source": "npm",
      "purpose": "Node.js runtime dependencies"
    }
  },
  "install_commands": [
    "./install-binaries.sh --easyrsa",
    "./install-binaries.sh --node",
    "./install-binaries.sh --verify"
  ]
}
EOF
    
    log_success "Created binary asset manifest"
}

# Main installation functions
install_easyrsa() {
    local platform=$(detect_platform)
    log_info "Installing EasyRSA binaries for $platform..."
    
    # Only download if we need cross-platform support
    # For now, use the existing checked-in binaries
    if [[ "$platform" == "windows" ]] && [[ ! -d "easy-rsa-vpn/distro/windows" ]]; then
        download_easyrsa_binaries "$platform" "$BINARY_ASSETS_DIR"
        
        # Copy to project locations
        if [[ -d "$BINARY_ASSETS_DIR/EasyRSA-${EASYRSA_VERSION}" ]]; then
            cp -r "$BINARY_ASSETS_DIR/EasyRSA-${EASYRSA_VERSION}/" easy-rsa-vpn/
            cp -r "$BINARY_ASSETS_DIR/EasyRSA-${EASYRSA_VERSION}/" vpn_setup/easy-rsa-vpn/
        fi
    else
        log_success "EasyRSA binaries already present or not needed for $platform"
    fi
}

install_node() {
    install_node_binaries
}

verify() {
    verify_binaries
}

# Show usage
usage() {
    cat << EOF
Binary Asset Management for Chatimics

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    --easyrsa     Install EasyRSA PKI binaries
    --node        Install Node.js dependencies
    --verify      Verify all binary dependencies
    --all         Install all binary assets (default)
    --clean       Clean downloaded binary assets
    --manifest    Create/update binary asset manifest
    --help        Show this help

EXAMPLES:
    $0                    # Install all binary assets
    $0 --node             # Install only Node.js dependencies
    $0 --verify           # Check if all binaries are installed
    $0 --clean            # Clean downloaded assets

NOTES:
    - This script manages binary files that are too large for git
    - EasyRSA Windows binaries are included for cross-platform support
    - Node.js dependencies are managed via npm
    - Docker images are managed via docker-compose

EOF
}

# Main execution
main() {
    echo "🔧 Chatimics Binary Asset Manager"
    echo "================================="
    
    case "${1:---all}" in
        --easyrsa)
            install_easyrsa
            ;;
        --node)
            install_node
            ;;
        --verify)
            if verify; then
                log_success "All binary dependencies verified"
            else
                log_error "Some binary dependencies are missing"
                exit 1
            fi
            ;;
        --all)
            install_easyrsa
            install_node
            verify
            create_manifest
            ;;
        --clean)
            log_info "Cleaning binary assets..."
            rm -rf "$BINARY_ASSETS_DIR"
            rm -rf node_modules
            rm -rf app_main/node_modules
            log_success "Binary assets cleaned"
            ;;
        --manifest)
            create_manifest
            ;;
        --help|-h)
            usage
            ;;
        *)
            log_error "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
}

# Create binary assets directory
mkdir -p "$BINARY_ASSETS_DIR"

# Run main function
main "$@"
