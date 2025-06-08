# --- Manual OVPN Generation (Robust) ---
CLIENT_VPN_ENDPOINT_ID="" # From your logs
AWS_REGION=""                                # Your script's config
VPN_NAME_TAG="CenetexVPNx0"                           # Your script's config
OVPN_FILE_NAME="${VPN_NAME_TAG}-client-config.ovpn"

# SCRIPT_DIR can be determined more simply if you are in the correct directory
# Or, if your easy-rsa-vpn is definitely in the current directory:
PKI_DIR="./easy-rsa-vpn/pki" # Relative path

echo "[INFO] Generating .ovpn client configuration file for ${CLIENT_VPN_ENDPOINT_ID}..."
CLIENT_CONFIG=$(aws ec2 export-client-vpn-client-configuration \
    --client-vpn-endpoint-id "$CLIENT_VPN_ENDPOINT_ID" \
    --region "$AWS_REGION" \
    --output text)

if [ -z "$CLIENT_CONFIG" ]; then
    echo "[ERROR] Failed to export client configuration from AWS."
    # Consider exiting if this is part of a larger script: exit 1
else
    echo "[INFO] Successfully exported base client configuration."
fi

echo "[INFO] Embedding certificates..."
CA_CERT_FILE="${PKI_DIR}/ca.crt"
CLIENT_CERT_FILE="${PKI_DIR}/issued/client1.crt" # Assuming client name is 'client1'
CLIENT_KEY_FILE="${PKI_DIR}/private/client1.key"   # Assuming client name is 'client1'

if [ ! -f "$CA_CERT_FILE" ]; then echo "[ERROR] CA cert not found: $CA_CERT_FILE"; exit 1; fi
if [ ! -f "$CLIENT_CERT_FILE" ]; then echo "[ERROR] Client cert not found: $CLIENT_CERT_FILE"; exit 1; fi
if [ ! -f "$CLIENT_KEY_FILE" ]; then echo "[ERROR] Client key not found: $CLIENT_KEY_FILE"; exit 1; fi

CA_CERT=$(cat "$CA_CERT_FILE")
CLIENT_CERT=$(cat "$CLIENT_CERT_FILE")
CLIENT_KEY=$(cat "$CLIENT_KEY_FILE")

echo "[INFO] Processing base configuration..."
# Remove existing <cert>, <key>, and <ca> blocks from AWS exported config
CLEAN_CONFIG=$(echo "${CLIENT_CONFIG}" | \
    sed '/<cert>/,/<\/cert>/d' | \
    sed '/<key>/,/<\/key>/d' | \
    sed '/<ca>/,/<\/ca>/d')

# Add 'remote-cert-tls server' if not already present
# Use a different delimiter for grep's pattern to avoid issues if the string contains '/'
if ! echo "${CLEAN_CONFIG}" | grep -q "remote-cert-tls server"; then
    # Append it; ensure it's on a new line if CLEAN_CONFIG isn't empty
    if [ -n "$CLEAN_CONFIG" ]; then
        CLEAN_CONFIG="${CLEAN_CONFIG}
remote-cert-tls server"
    else
        CLEAN_CONFIG="remote-cert-tls server"
    fi
fi
echo "[INFO] Base configuration processed."

echo "[INFO] Assembling final .ovpn content..."
# Assemble the full configuration
# Place CLEAN_CONFIG first, then our cert/key blocks.
# Using printf for more control over newlines.
FULL_OVPN_CONFIG=$(printf "%s\n\n<ca>\n%s\n</ca>\n\n<cert>\n%s\n</cert>\n\n<key>\n%s\n</key>\n" \
    "${CLEAN_CONFIG}" \
    "${CA_CERT}" \
    "${CLIENT_CERT}" \
    "${CLIENT_KEY}")

# Optional: Remove truly empty lines (not just whitespace lines) for tidiness
# This awk script prints lines that are not entirely empty.
FULL_OVPN_CONFIG=$(echo "$FULL_OVPN_CONFIG" | awk 'NF > 0')

echo "${FULL_OVPN_CONFIG}" > "${OVPN_FILE_NAME}"
echo "[INFO] Client configuration file generated: ${OVPN_FILE_NAME}"
echo "--- IMPORTANT ---"
echo "The private key for the client is embedded in ${OVPN_FILE_NAME}."
echo "The EasyRSA PKI is in $(cd "${PKI_DIR}/.." && pwd). Secure these appropriately."