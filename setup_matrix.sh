#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Error on line $LINENO" >&2; exit 1' ERR

function usage() {
  cat <<EOF
Usage: $0 -d DOMAIN [-z ZONE_ID] [--aws-region REGION] [--skip-dns] [-h]
  -d, --domain DOMAIN       Fully qualified domain for the Matrix server (e.g., chat.example.com)
  -z, --zone-id ZONE_ID     AWS Route53 Hosted Zone ID to configure DNS records
  -r, --aws-region REGION   AWS Region (default: from AWS CLI config)
  --skip-dns                Skip Route53 DNS configuration
  -h, --help                Show this help message
EOF
  exit 1
}

# Parse arguments
DOMAIN=""
ZONE_ID=""
AWS_REGION=""
SKIP_DNS="no"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--domain)
      DOMAIN="$2"; shift 2;;
    -z|--zone-id)
      ZONE_ID="$2"; shift 2;;
    -r|--aws-region)
      AWS_REGION="$2"; shift 2;;
    --skip-dns)
      SKIP_DNS="yes"; shift;;
    -h|--help)
      usage;;
    *)
      echo "Unknown option: $1" >&2; usage;;
  esac
done

# Ensure domain is provided
if [[ -z "$DOMAIN" ]]; then
  echo "Error: Domain is required" >&2; usage
fi

# Must run as root
if [[ $(id -u) -ne 0 ]]; then
  echo "Error: This script must be run as root or with sudo" >&2
  exit 1
fi

echo "=== Starting Matrix Synapse setup for $DOMAIN ==="

# Verify apt-get is available
if ! command -v apt-get >/dev/null; then
  echo "Error: apt-get not found. Only Debian/Ubuntu supported." >&2; exit 1
fi

echo "Installing prerequisites..."
apt-get update -qq
apt-get install -y docker.io docker-compose certbot python3-certbot-dns-cloudflare awscli curl jq dnsutils apt-transport-https gnupg

# Install cloudflared if missing
if ! command -v cloudflared >/dev/null; then
  echo "Installing cloudflared..."
  curl -sL https://packages.cloudflare.com/install.sh | bash
  apt-get update -qq
  apt-get install -y cloudflared
fi

# Directories
CONFIG_DIR=/etc/cloudflared
INSTALL_DIR=/opt/matrix-synapse
REPO_DIR=$(pwd)
mkdir -p "$CONFIG_DIR"
mkdir -p "$INSTALL_DIR"

# Configure Cloudflare Tunnel
if [[ ! -f "$REPO_DIR/config.yml" ]]; then
  echo "Error: config.yml not found in $REPO_DIR" >&2; exit 1
fi
TUNNEL_ID=$(grep '^tunnel:' "$REPO_DIR/config.yml" | awk '{print $2}')
CREDS_SRC="$REPO_DIR/${TUNNEL_ID}.json"
if [[ ! -f "$CREDS_SRC" ]]; then
  echo "Error: Tunnel credentials file $CREDS_SRC not found" >&2; exit 1
fi
cp "$CREDS_SRC" "$CONFIG_DIR/${TUNNEL_ID}.json"
cp "$REPO_DIR/config.yml" "$CONFIG_DIR/config.yml"
# Update tunnel config for target domain and credentials path
sed -i "s|credentials-file:.*|credentials-file: $CONFIG_DIR/${TUNNEL_ID}.json|" "$CONFIG_DIR/config.yml"
sed -i "s|hostname: .*|hostname: $DOMAIN|" "$CONFIG_DIR/config.yml"

echo "Cloudflare tunnel configured (ID: $TUNNEL_ID)"

echo "Copying Synapse docker-compose and data..."
cp -r "$REPO_DIR/data" "$INSTALL_DIR/data"
cp "$REPO_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"

# Update homeserver.yaml for the new domain
HOMESERVER_YAML="$INSTALL_DIR/data/homeserver.yaml"
if [[ ! -f "$HOMESERVER_YAML" ]]; then
  echo "Error: homeserver.yaml not found at $HOMESERVER_YAML" >&2; exit 1
fi
OLD_DOMAIN=$(grep '^server_name:' "$HOMESERVER_YAML" | awk -F '"' '{print $2}')
sed -i "s|server_name:.*|server_name: \"$DOMAIN\"|" "$HOMESERVER_YAML"
sed -i "s|log_config:.*|log_config: \"/data/${DOMAIN}.log.config\"|" "$HOMESERVER_YAML"
sed -i "s|signing_key_path:.*|signing_key_path: \"/data/${DOMAIN}.signing.key\"|" "$HOMESERVER_YAML"
# Rename old log config and signing key if present
mv "$INSTALL_DIR/data/${OLD_DOMAIN}.log.config" "$INSTALL_DIR/data/${DOMAIN}.log.config" 2>/dev/null || true
mv "$INSTALL_DIR/data/${OLD_DOMAIN}.signing.key" "$INSTALL_DIR/data/${DOMAIN}.signing.key" 2>/dev/null || true

echo "Starting Docker Compose services..."
cd "$INSTALL_DIR"
docker-compose pull
docker-compose up -d

echo "Restarting cloudflared service..."
systemctl enable cloudflared
systemctl restart cloudflared
echo "cloudflared status:"; systemctl status cloudflared --no-pager

# Configure AWS Route53 DNS if requested
if [[ "$SKIP_DNS" != "yes" && -n "$ZONE_ID" ]]; then
  if ! command -v aws >/dev/null; then echo "AWS CLI not found; skipping DNS setup." >&2; else
    echo "Configuring Route53 DNS records in zone $ZONE_ID..."
    # Detect public IP
    SERVER_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || true)
    if [[ -z "$SERVER_IP" ]]; then
      echo "Could not detect public IP; please ensure AWS CLI has permissions or specify manually." >&2
      exit 1
    fi
    # Prepare change batch
    TMP_JSON=$(mktemp)
    cat > "$TMP_JSON" <<EOF
{
  "Comment": "Matrix server DNS records",
  "Changes": [
    {"Action": "UPSERT", "ResourceRecordSet": {"Name": "$DOMAIN", "Type": "CNAME", "TTL": 300, "ResourceRecords": [{"Value": "${TUNNEL_ID}.cfargotunnel.com"}]}},
    {"Action": "UPSERT", "ResourceRecordSet": {"Name": "_matrix._tcp.$DOMAIN", "Type": "SRV", "TTL": 300, "ResourceRecords": [{"Value": "0 0 8448 $DOMAIN."}]}}
  ]
}
EOF
    aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch file://"$TMP_JSON"
    rm -f "$TMP_JSON"
  fi
else
  echo "Skipping Route53 DNS configuration"
fi

echo "Running connectivity checks..."
echo "HTTP endpoint:";
if curl -sSf -o /dev/null "https://$DOMAIN/_matrix/client/versions"; then echo "OK"; else echo "FAILED"; fi
echo "Federation endpoint:";
if curl -sSf -o /dev/null "https://$DOMAIN:8448/federation/v1/version"; then echo "OK"; else echo "FAILED"; fi
echo "SRV record lookup:";
dig +short SRV _matrix._tcp.$DOMAIN || echo "No SRV record found"

echo "=== Setup complete for $DOMAIN ==="