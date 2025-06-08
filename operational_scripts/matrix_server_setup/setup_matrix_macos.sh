#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Error on line $LINENO" >&2; exit 1' ERR

# Utility: get absolute path
get_realpath() { 
  local p="$1"; 
  local dir; dir=$(cd "$(dirname "$p")" && pwd -P); 
  echo "${dir}/$(basename "$p")"; 
}

function usage() {
  cat <<EOF
Usage: $0 -d DOMAIN [-i INSTALL_DIR] [--skip-dns] [-h]
  -d, --domain       Fully qualified domain (e.g., chat.example.com)
  -i, --install-dir  Install base directory (default: ~/matrix-synapse)
  --skip-dns         Skip DNS automation (manual DNS on macOS)
  -h, --help         Show this help message
EOF
  exit 1
}

# Default values
DOMAIN=""
INSTALL_DIR="$HOME/matrix-synapse"
SKIP_DNS="no"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--domain) DOMAIN="$2"; shift 2;;
    -i|--install-dir) INSTALL_DIR="$2"; shift 2;;
    --skip-dns) SKIP_DNS="yes"; shift;;
    -h|--help) usage;;
    *) echo "Unknown option: $1" >&2; usage;;
  esac
done
[[ -n "$DOMAIN" ]] || { echo "Error: Domain is required" >&2; usage; }

# Ensure macOS
if [[ "$(uname)" != "Darwin" ]]; then
  echo "Error: This script only supports macOS." >&2; exit 1
fi

# Ensure Homebrew
if ! command -v brew >/dev/null; then
  echo "Error: Homebrew not found. Install from https://brew.sh/" >&2; exit 1
fi

echo "==> Installing prerequisites..."
brew update
# Docker Desktop
if [[ ! -d "/Applications/Docker.app" ]]; then
  echo "Installing Docker Desktop..."
  brew install --cask docker
else
  echo "Docker Desktop already installed"
fi
# CLI tools
brew install docker-compose cloudflared certbot awscli jq curl || true

echo "==> Waiting for Docker Desktop to launch..."
until docker info >/dev/null 2>&1; do
  echo "Please start Docker Desktop and press Enter to continue..."
  read -r
done

# Setup directories
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.cloudflared"
mkdir -p "$CONFIG_DIR"
mkdir -p "$INSTALL_DIR"

echo "==> Configuring Cloudflare Tunnel..."
# Extract Tunnel ID
CFG_SRC="$REPO_DIR/config.yml"
if [[ ! -f "$CFG_SRC" ]]; then
  echo "Error: config.yml not found in repo" >&2; exit 1
fi
TUNNEL_ID=$(grep -E '^tunnel:' "$CFG_SRC" | awk '{print $2}')
CREDS_SRC="$REPO_DIR/${TUNNEL_ID}.json"
if [[ ! -f "$CREDS_SRC" ]]; then
  echo "Error: credentials file $CREDS_SRC not found" >&2; exit 1
fi
# Copy or update credentials file
DEST_CREDS="$CONFIG_DIR/${TUNNEL_ID}.json"
if [[ ! -f "$DEST_CREDS" ]] || ! cmp -s "$CREDS_SRC" "$DEST_CREDS"; then
  cp "$CREDS_SRC" "$DEST_CREDS"
  echo "Copied tunnel credentials"
else
  echo "Tunnel credentials up to date"
fi
# Generate config.yml with correct paths and domain
DEST_CFG="$CONFIG_DIR/config.yml"
# Only copy if not the same file
if [[ "$(get_realpath "$CFG_SRC")" != "$(get_realpath "$DEST_CFG")" ]]; then
  cp "$CFG_SRC" "$DEST_CFG"
  echo "Copied tunnel config to $DEST_CFG"
else
  echo "Tunnel config already present at $DEST_CFG, skipping copy"
fi
sed -i '' -E "s|credentials-file:.*|credentials-file: $DEST_CREDS|" "$DEST_CFG"
sed -i '' -E "s|hostname:.*|hostname: $DOMAIN|" "$DEST_CFG"
echo "Cloudflare Tunnel config written to $DEST_CFG"

echo "==> Configuring Synapse..."
# Copy synapse_server directory if missing
SYNAPSE_DIR="$INSTALL_DIR/synapse_server"
DATA_DIR="$SYNAPSE_DIR/data"
if [[ ! -d "$SYNAPSE_DIR" ]]; then
  cp -r "$REPO_DIR/synapse_server" "$SYNAPSE_DIR"
  echo "Copied Synapse server directory"
else
  echo "Synapse server directory already exists"
fi
# Docker Compose
DC_SRC="$REPO_DIR/docker-compose.yml"
DC_DST="$INSTALL_DIR/docker-compose.yml"
cp "$DC_SRC" "$DC_DST"

# Patch homeserver.yaml
HS_YAML="$DATA_DIR/homeserver.yaml"
if [[ ! -f "$HS_YAML" ]]; then
  echo "Error: homeserver.yaml not found in data directory" >&2; exit 1
fi
echo "Patching homeserver.yaml for domain $DOMAIN"
sed -i '' -E "s|^server_name:.*|server_name: \"$DOMAIN\"|" "$HS_YAML"
sed -i '' -E "s|^log_config:.*|log_config: \"/data/${DOMAIN}.log.config\"|" "$HS_YAML"
sed -i '' -E "s|^signing_key_path:.*|signing_key_path: \"/data/${DOMAIN}.signing.key\"|" "$HS_YAML"
# Rename keys/logs if domain changed
OLD_NAME=$(basename "$(grep '^log_config:' "$HS_YAML" | awk -F '"' '{print $2}')" .log.config)
if [[ "$OLD_NAME" != "$DOMAIN" ]]; then
  mv "$DATA_DIR/${OLD_NAME}.log.config" "$DATA_DIR/${DOMAIN}.log.config" 2>/dev/null || true
  mv "$DATA_DIR/${OLD_NAME}.signing.key" "$DATA_DIR/${DOMAIN}.signing.key" 2>/dev/null || true
fi

echo "==> Starting services..."
cd "$INSTALL_DIR"
docker-compose pull
docker-compose up -d

echo "==> Ensuring cloudflared service..."
if brew services list | grep -q '^cloudflared .* started'; then
  echo "cloudflared already running"
else
  brew services start cloudflared || true
  echo "cloudflared service started"
fi

if [[ "$SKIP_DNS" != "yes" ]]; then
  echo "Note: DNS automation is not supported on macOS. Please create CNAME and SRV records manually."
fi

echo "==> Connectivity checks for $DOMAIN"
echo -n "HTTP: "
curl -sSf -o /dev/null "https://$DOMAIN/_matrix/client/versions" && echo OK || echo FAILED
echo -n "Federation: "
curl -sSf -o /dev/null "https://$DOMAIN:8448/federation/v1/version" && echo OK || echo FAILED
echo -n "SRV lookup: "
dig +short SRV _matrix._tcp.$DOMAIN || echo "none"

echo "==> Setup/repair complete for $DOMAIN"