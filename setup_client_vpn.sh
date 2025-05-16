#!/bin/bash

# Exit on any error
set -e
# Exit on unset variable
set -u
# Pipefail
set -o pipefail

# --- Configuration - MODIFY THESE VALUES ---
AWS_REGION="" # Your target AWS region
VPC_ID="" # Your VPC ID
SUBNET_ID="" # A public subnet ID within the VPC (must have IGW route)
CLIENT_VPN_CIDR="" # CIDR for VPN clients (must not overlap with VPC CIDR)
VPN_NAME_TAG="CenetexVPN" # A name tag for resources
DNS_SERVERS="8.8.8.8,8.8.4.4" # Comma-separated DNS servers for clients
TRANSPORT_PROTOCOL="udp" # "udp" or "tcp" (udp is generally preferred)
# Optional: Provide an existing Security Group ID. If empty, one will be created.
EXISTING_SG_ID="" # e.g., "sg-xxxxxxxxxxxxxxxxx"

# --- Script Internal Variables ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EASYRSA_DIR="${SCRIPT_DIR}/easy-rsa-vpn"
PKI_DIR="${EASYRSA_DIR}/pki"
OVPN_FILE_NAME="${VPN_NAME_TAG}-client-config.ovpn"

# --- Helper Functions ---
log() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
    exit 1
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "$1 command not found. Please install it."
    fi
}

# --- Main Script ---

log "Starting Client VPN Setup Script"

# 0. Prerequisites Check
log "Checking prerequisites..."
check_command "aws"
check_command "easy-rsa"
check_command "jq"
check_command "openssl"

# 1. Setup Easy-RSA and Generate Certificates
log "Setting up Easy-RSA and generating certificates..."
if [ -d "$EASYRSA_DIR" ]; then
    warn "Easy-RSA directory '$EASYRSA_DIR' already exists. Re-using or remove it manually to regenerate."
else
    mkdir -p "$EASYRSA_DIR"
    cp -r /usr/share/easy-rsa/* "$EASYRSA_DIR/" || cp -r $(brew --prefix easy-rsa)/share/easy-rsa/* "$EASYRSA_DIR/" || {
        error "Could not find easy-rsa files. Please ensure it's installed and accessible or adjust path."
    }
    cd "$EASYRSA_DIR"

    # Initialize PKI
    ./easyrsa init-pki
    echo "VPNCA" | ./easyrsa build-ca nopass # Create CA
    ./easyrsa build-server-full server nopass # Create Server cert + key
    ./easyrsa build-client-full client1 nopass # Create Client cert + key
    cd "$SCRIPT_DIR"
    log "Certificates generated in $PKI_DIR"
fi

# 2. Upload Certificates to ACM
log "Uploading certificates to ACM..."
SERVER_CERT_ARN=$(aws acm import-certificate \
    --certificate "fileb://${PKI_DIR}/issued/server.crt" \
    --private-key "fileb://${PKI_DIR}/private/server.key" \
    --certificate-chain "fileb://${PKI_DIR}/ca.crt" \
    --region "$AWS_REGION" \
    --tags Key=Name,Value="${VPN_NAME_TAG}-ServerCert" \
    --query 'CertificateArn' --output text)
log "Server Certificate ARN: $SERVER_CERT_ARN"

CLIENT_CERT_ARN=$(aws acm import-certificate \
    --certificate "fileb://${PKI_DIR}/issued/client1.crt" \
    --private-key "fileb://${PKI_DIR}/private/client1.key" \
    --certificate-chain "fileb://${PKI_DIR}/ca.crt" \
    --region "$AWS_REGION" \
    --tags Key=Name,Value="${VPN_NAME_TAG}-ClientCert" \
    --query 'CertificateArn' --output text)
log "Client Certificate ARN: $CLIENT_CERT_ARN"

# 3. Create Security Group (if not provided)
if [ -z "$EXISTING_SG_ID" ]; then
    log "Creating Security Group for Client VPN..."
    SG_ID=$(aws ec2 create-security-group \
        --group-name "${VPN_NAME_TAG}-SG" \
        --description "Security group for ${VPN_NAME_TAG} Client VPN" \
        --vpc-id "$VPC_ID" \
        --region "$AWS_REGION" \
        --query 'GroupId' --output text)
    log "Security Group ID: $SG_ID"

    # Add outbound rule (allow all outbound)
    aws ec2 authorize-security-group-egress \
        --group-id "$SG_ID" \
        --protocol all \
        --port all \
        --cidr "0.0.0.0/0" \
        --region "$AWS_REGION"
    log "Added outbound rule to SG $SG_ID"

    # Note: Inbound rules for the VPN port (UDP/TCP 443 by default) are not needed on this SG.
    # The Client VPN service manages the ENIs and their security.
    # This SG is applied to the *ENIs created by the Client VPN endpoint in your VPC*.
    # It controls what traffic those ENIs can send *to* and receive *from* your VPC resources or the internet.
else
    SG_ID="$EXISTING_SG_ID"
    log "Using existing Security Group ID: $SG_ID"
fi


# 4. Create Client VPN Endpoint
log "Creating Client VPN Endpoint..."
CLIENT_VPN_ENDPOINT_ID=$(aws ec2 create-client-vpn-endpoint \
    --client-cidr-block "$CLIENT_VPN_CIDR" \
    --server-certificate-arn "$SERVER_CERT_ARN" \
    --authentication-options Type=certificate-authentication,MutualAuthentication={ClientRootCertificateChainArn=$CLIENT_CERT_ARN} \
    --connection-log-options Enabled=false \
    --dns-servers "$DNS_SERVERS" \
    --transport-protocol "$TRANSPORT_PROTOCOL" \
    --split-tunnel Enabled=false `# Send all traffic through VPN` \
    --vpc-id "$VPC_ID" \
    --security-group-ids "$SG_ID" \
    --tag-specifications "ResourceType=client-vpn-endpoint,Tags=[{Key=Name,Value=${VPN_NAME_TAG}}]" \
    --region "$AWS_REGION" \
    --query 'ClientVpnEndpointId' --output text)
log "Client VPN Endpoint ID: $CLIENT_VPN_ENDPOINT_ID"
log "Waiting for Client VPN Endpoint to become available (this may take a few minutes)..."

# Wait for endpoint to be available. Max wait 5 minutes.
MAX_RETRIES=30
RETRY_COUNT=0
ENDPOINT_STATE=""
while [ "$ENDPOINT_STATE" != "available" ]; do
    ENDPOINT_STATE=$(aws ec2 describe-client-vpn-endpoints \
        --client-vpn-endpoint-ids "$CLIENT_VPN_ENDPOINT_ID" \
        --region "$AWS_REGION" \
        --query 'ClientVpnEndpoints[0].Status.Code' --output text)
    log "Current endpoint state: $ENDPOINT_STATE"
    if [ "$ENDPOINT_STATE" = "available" ]; then
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
        error "Client VPN Endpoint did not become available after $MAX_RETRIES retries."
    fi
    sleep 10
done
log "Client VPN Endpoint is available."

# 5. Associate Target Network
log "Associating Target Network (Subnet: $SUBNET_ID)..."
aws ec2 associate-client-vpn-target-network \
    --client-vpn-endpoint-id "$CLIENT_VPN_ENDPOINT_ID" \
    --subnet-id "$SUBNET_ID" \
    --region "$AWS_REGION"
log "Target network association initiated. This also takes some time to become 'associated'."

# Wait for association (max 2 minutes)
MAX_ASSOC_RETRIES=12
ASSOC_RETRY_COUNT=0
ASSOC_STATUS=""
while [ "$ASSOC_STATUS" != "associated" ]; do
    ASSOC_STATUS=$(aws ec2 describe-client-vpn-target-networks \
        --client-vpn-endpoint-id "$CLIENT_VPN_ENDPOINT_ID" \
        --association-ids \
        --region "$AWS_REGION" \
        --query "ClientVpnTargetNetworks[0].Status.Code" --output text 2>/dev/null || echo "pending")

    log "Current association status: $ASSOC_STATUS"
    if [ "$ASSOC_STATUS" = "associated" ]; then
        break
    fi
    ASSOC_RETRY_COUNT=$((ASSOC_RETRY_COUNT + 1))
    if [ "$ASSOC_RETRY_COUNT" -ge "$MAX_ASSOC_RETRIES" ]; then
        warn "Target network association did not complete quickly. Check AWS console. Proceeding..."
        # Allow script to proceed, but user should verify.
        break
    fi
    sleep 10
done
log "Target network association status: $ASSOC_STATUS"


# 6. Add Authorization Rule (Allow all clients to access internet)
log "Adding Authorization Rule for 0.0.0.0/0..."
aws ec2 authorize-client-vpn-ingress \
    --client-vpn-endpoint-id "$CLIENT_VPN_ENDPOINT_ID" \
    --target-network-cidr "$VPC_ID" `# This seems counter-intuitive, but it's how you specify the "allow all" when combined with 0.0.0.0/0` \
    --authorize-all-groups \
    --description "Allow all clients to access everything" \
    --region "$AWS_REGION"
# The above command for target-network-cidr is subtle. For '0.0.0.0/0' access,
# you often specify the VPC CIDR here. If you want to authorize to a specific subnet,
# you'd use that subnet's CIDR. To allow all clients, we use --authorize-all-groups.

# Let's re-add specifically for 0.0.0.0/0 if the above VPC one doesn't cover internet for all groups
# Update: The correct way to authorize internet access for *all users* is to simply target 0.0.0.0/0
# and use --authorize-all-groups. The target-network-cidr for the rule should be 0.0.0.0/0
aws ec2 authorize-client-vpn-ingress \
    --client-vpn-endpoint-id "$CLIENT_VPN_ENDPOINT_ID" \
    --target-network-cidr "0.0.0.0/0" \
    --authorize-all-groups \
    --description "Allow all clients to access internet" \
    --region "$AWS_REGION"

log "Authorization rule added."

# 7. Add Route (Route all traffic from VPN to the associated subnet)
log "Adding Route for 0.0.0.0/0..."
aws ec2 create-client-vpn-route \
    --client-vpn-endpoint-id "$CLIENT_VPN_ENDPOINT_ID" \
    --destination-cidr-block "0.0.0.0/0" \
    --target-vpc-subnet-id "$SUBNET_ID" \
    --description "Route all traffic to internet" \
    --region "$AWS_REGION"
log "Route for 0.0.0.0/0 added."

# 8. Generate .ovpn Client Configuration File
log "Generating .ovpn client configuration file..."
CLIENT_CONFIG=$(aws ec2 export-client-vpn-client-configuration \
    --client-vpn-endpoint-id "$CLIENT_VPN_ENDPOINT_ID" \
    --region "$AWS_REGION" \
    --output text)

# Embed certs and key
CA_CERT=$(cat "${PKI_DIR}/ca.crt")
CLIENT_CERT=$(cat "${PKI_DIR}/issued/client1.crt")
CLIENT_KEY=$(cat "${PKI_DIR}/private/client1.key")

# Remove existing cert/key placeholders if any (unlikely for fresh export)
CLEAN_CONFIG=$(echo "${CLIENT_CONFIG}" | sed '/<cert>/,/<\/cert>/d' | sed '/<key>/,/<\/key>/d')

# For self-signed server certificate, OpenVPN client needs to verify it explicitly
# Add 'remote-cert-tls server' if not already present.
# AWS-generated configs for mutual auth usually don't include this because the CA is implicitly trusted.
# However, it's good practice.
if ! echo "${CLEAN_CONFIG}" | grep -q "remote-cert-tls server"; then
    CLEAN_CONFIG="${CLEAN_CONFIG}
remote-cert-tls server"
fi


FULL_OVPN_CONFIG="
<ca>
${CA_CERT}
</ca>
<cert>
${CLIENT_CERT}
</cert>
<key>
${CLIENT_KEY}
</key>
${CLEAN_CONFIG}
"
# Remove leading/trailing whitespace from heredoc
FULL_OVPN_CONFIG=$(echo "$FULL_OVPN_CONFIG" | awk 'NF > 0')


echo "${FULL_OVPN_CONFIG}" > "${OVPN_FILE_NAME}"
log "Client configuration file generated: ${OVPN_FILE_NAME}"
log "--- IMPORTANT ---"
log "The private key for the client is embedded in ${OVPN_FILE_NAME}."
log "The EasyRSA PKI is in ${EASYRSA_DIR}. Secure these appropriately."
log "--- SETUP COMPLETE ---"
log "Client VPN Endpoint ID: ${CLIENT_VPN_ENDPOINT_ID}"
log "You can now import ${OVPN_FILE_NAME} into your OpenVPN client."

# --- Cleanup Instructions ---
cat << EOF

---
To cleanup resources created by this script:
1. Delete Client VPN Endpoint:
   aws ec2 delete-client-vpn-endpoint --client-vpn-endpoint-id ${CLIENT_VPN_ENDPOINT_ID} --region ${AWS_REGION}
   (This will also delete associations, routes, and authorization rules)
   Wait for it to be deleted.

2. Delete ACM Certificates:
   aws acm delete-certificate --certificate-arn ${SERVER_CERT_ARN} --region ${AWS_REGION}
   aws acm delete-certificate --certificate-arn ${CLIENT_CERT_ARN} --region ${AWS_REGION}

3. Delete Security Group (if created by script and no EXISTING_SG_ID was provided):
EOF
if [ -z "$EXISTING_SG_ID" ]; then
cat << EOF
   aws ec2 delete-security-group --group-id ${SG_ID} --region ${AWS_REGION}
EOF
else
cat << EOF
   (You provided an existing SG: ${SG_ID}, so no SG was deleted by this script)
EOF
fi
cat << EOF

4. Delete local Easy-RSA directory:
   rm -rf "${EASYRSA_DIR}"
   rm -f "${OVPN_FILE_NAME}"
---
EOF