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
CLIENT_VPN_CIDR="10.88.0.0/16" # CIDR for VPN clients (must not overlap with VPC CIDR)
VPN_NAME_TAG="CenetexVPNx0" # A name tag for resources
SERVER_CERT_CN="vpn.example.com" 
DNS_SERVERS="8.8.8.8,1.1.1.1" # Comma-separated DNS servers for clients
TRANSPORT_PROTOCOL="udp" # "udp" or "tcp" (udp is generally preferred)
# Optional: Provide an existing Security Group ID. If empty, one will be created.
EXISTING_SG_ID="" # e.g., "sg-xxxxxxxxxxxxxxxxx"


# --- Script Internal Variables ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EASYRSA_DIR="${SCRIPT_DIR}/easy-rsa-vpn" # Directory to clone/use easy-rsa
EASYRSA_EXECUTABLE="${EASYRSA_DIR}/easyrsa" # Path to the easyrsa executable after cloning
PKI_DIR="${EASYRSA_DIR}/pki"
OVPN_FILE_NAME="${VPN_NAME_TAG}-client-config.ovpn"
EASYRSA_REPO_URL="https://github.com/OpenVPN/easy-rsa.git"
EASYRSA_VERSION_TAG="v3.2.2" # Specify a version tag, or leave empty for main branch

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
check_command "git" # Added git
check_command "jq"
check_command "openssl"

# 1. Setup Easy-RSA and Generate Certificates
# 1. Setup Easy-RSA and Generate Certificates
log "Setting up Easy-RSA..."
if [ -d "$EASYRSA_DIR" ]; then
    warn "Easy-RSA directory '$EASYRSA_DIR' already exists. Using existing."
    # We'll verify the executable path later, inside the directory
else
    log "Cloning Easy-RSA from ${EASYRSA_REPO_URL}..."
    if [ -n "$EASYRSA_VERSION_TAG" ]; then
        # Clone specific tag/branch
        git clone --depth 1 --branch "$EASYRSA_VERSION_TAG" "$EASYRSA_REPO_URL" "$EASYRSA_DIR"
    else
        # Clone default branch (usually main/master) with depth 1
        git clone --depth 1 "$EASYRSA_REPO_URL" "$EASYRSA_DIR"
    fi
    log "Easy-RSA cloned into $EASYRSA_DIR"
fi

# Navigate into the main easy-rsa directory to run its scripts
cd "$EASYRSA_DIR"

# Determine the correct path for the easyrsa executable
EASYRSA_CMD=""
if [ -f "./easyrsa" ]; then
    EASYRSA_CMD="./easyrsa"
elif [ -f "./easyrsa3/easyrsa" ]; then # Check for easyrsa3 subdirectory, common in v3.x tags
    EASYRSA_CMD="./easyrsa3/easyrsa"
else
    error "Could not find 'easyrsa' executable in the cloned Easy-RSA directory (${EASYRSA_DIR}). Searched for ./easyrsa and ./easyrsa3/easyrsa."
fi

log "Using Easy-RSA command: ${EASYRSA_CMD} from PWD: $(pwd)"
log "Generating certificates using Easy-RSA..."

# Ensure a clean PKI directory for fresh certificate generation
log "Ensuring a clean PKI directory at ${PKI_DIR}..."
if [ -d "$PKI_DIR" ]; then # PKI_DIR is $EASYRSA_DIR/pki, and we are in $EASYRSA_DIR
    log "Removing existing PKI subdirectory: pki"
    rm -rf "./pki" # Use relative path as we are inside EASYRSA_DIR
fi

# Initialize PKI. The PKI_DIR is set relative to $EASYRSA_DIR.
# The easyrsa script by default creates 'pki' in the current working directory ($PWD),
# which is $EASYRSA_DIR at this point. This matches our $PKI_DIR definition.
$EASYRSA_CMD init-pki
echo "VPNCA" | $EASYRSA_CMD build-ca nopass # Create CA

# --- MODIFIED SERVER CERTIFICATE GENERATION ---
log "Generating server certificate with CN: ${SERVER_CERT_CN}"
$EASYRSA_CMD build-server-full "${SERVER_CERT_CN}" nopass # Create Server cert + key using the FQDN
# --- END MODIFICATION ---

$EASYRSA_CMD build-client-full client1 nopass # Create Client cert + key

# Important: Navigate back to the original script directory
cd "$SCRIPT_DIR"
log "Certificates generated in $PKI_DIR"

# 2. Upload Certificates to ACM
log "Uploading certificates to ACM..."

# --- MODIFIED SERVER CERTIFICATE UPLOAD ---
SERVER_CERT_ARN=$(aws acm import-certificate \
    --certificate "fileb://${PKI_DIR}/issued/${SERVER_CERT_CN}.crt" \
    --private-key "fileb://${PKI_DIR}/private/${SERVER_CERT_CN}.key" \
    --certificate-chain "fileb://${PKI_DIR}/ca.crt" \
    --region "$AWS_REGION" \
    --tags Key=Name,Value="${VPN_NAME_TAG}-ServerCert" \
    --query 'CertificateArn' --output text)
# --- END MODIFICATION ---
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
    log "DEBUG: About to execute 'aws ec2 create-security-group'..."

    set +e # Temporarily disable exit on error
    SG_ID_CREATE_COMMAND_OUTPUT=$(aws ec2 create-security-group \
        --group-name "${VPN_NAME_TAG}-SG" \
        --description "Security group for ${VPN_NAME_TAG} Client VPN" \
        --vpc-id "$VPC_ID" \
        --region "$AWS_REGION" \
        --query 'GroupId' --output text 2>&1) # Capture stdout and stderr
    SG_ID_CREATE_COMMAND_EXIT_CODE=$?
    set -e # Re-enable exit on error

    log "DEBUG: 'aws ec2 create-security-group' command finished."
    log "DEBUG: Exit code: ${SG_ID_CREATE_COMMAND_EXIT_CODE}"
    log "DEBUG: Output:"
    echo "--- CREATE SECURITY GROUP OUTPUT START ---"
    echo "${SG_ID_CREATE_COMMAND_OUTPUT}"
    echo "--- CREATE SECURITY GROUP OUTPUT END ---"

    if [ "${SG_ID_CREATE_COMMAND_EXIT_CODE}" -ne 0 ]; then
        error "Failed to create Security Group. Exit Code: ${SG_ID_CREATE_COMMAND_EXIT_CODE}. Output above."
    fi

    # If successful, the output should be the Group ID
    SG_ID="${SG_ID_CREATE_COMMAND_OUTPUT}"
    # Basic validation: Check if SG_ID looks like an SG ID (starts with 'sg-')
    if [[ ! "$SG_ID" == sg-* ]]; then
        error "Failed to parse Security Group ID from 'create-security-group' output. Full output was: ${SG_ID_CREATE_COMMAND_OUTPUT}"
    fi
    log "Security Group ID successfully created/retrieved: $SG_ID"

    # Add outbound rule (allow all outbound)
    log "Attempting to add outbound rule (0.0.0.0/0) to SG $SG_ID..."
    log "DEBUG: Variables: SG_ID='${SG_ID}', AWS_REGION='${AWS_REGION}'"
    log "DEBUG: Executing AWS CLI command for egress rule (with set -e temporarily disabled)..."

    set +e # Temporarily disable exit on error
    AWS_EGRESS_COMMAND_OUTPUT=$(aws ec2 authorize-security-group-egress \
        --group-id "${SG_ID}" \
        --protocol "all" \
        --port "all" \
        --cidr "0.0.0.0/0" \
        --region "${AWS_REGION}" 2>&1)
    AWS_EGRESS_COMMAND_EXIT_CODE=$?
    set -e # Re-enable exit on error

    log "DEBUG: AWS command for egress rule finished."
    log "DEBUG: AWS command exit code: ${AWS_EGRESS_COMMAND_EXIT_CODE}"
    log "DEBUG: AWS command output captured:"
    echo "--- AWS CLI EGRESS RULE OUTPUT START ---"
    echo "${AWS_EGRESS_COMMAND_OUTPUT}"
    echo "--- AWS CLI EGRESS RULE OUTPUT END ---"

    if [ "${AWS_EGRESS_COMMAND_EXIT_CODE}" -eq 0 ]; then
        log "Successfully added outbound rule to SG ${SG_ID}."
    else
        log "INFO: AWS command for egress rule failed with exit code ${AWS_EGRESS_COMMAND_EXIT_CODE}. Checking if it's 'InvalidPermission.Duplicate'..."
        if echo "${AWS_EGRESS_COMMAND_OUTPUT}" | grep -q "InvalidPermission.Duplicate"; then
            log "INFO: Outbound rule (0.0.0.0/0) already exists for SG ${SG_ID}. This is normal. Continuing."
        else
            error "Failed to authorize security group egress for SG ${SG_ID}. Exit code: ${AWS_EGRESS_COMMAND_EXIT_CODE}. Full output above."
        fi
    fi
else
    SG_ID="$EXISTING_SG_ID"
    log "Using existing Security Group ID: $SG_ID"
fi


# 4. Create Client VPN Endpoint
log "Creating Client VPN Endpoint..."
log "DEBUG: About to execute 'aws ec2 create-client-vpn-endpoint'..."

IFS=',' read -r -a DNS_SERVERS_FOR_CLI <<< "$DNS_SERVERS"

set +e
CLIENT_VPN_ENDPOINT_ID_COMMAND_OUTPUT=$(aws ec2 create-client-vpn-endpoint \
    --client-cidr-block "$CLIENT_VPN_CIDR" \
    --server-certificate-arn "$SERVER_CERT_ARN" \
    --authentication-options "Type=certificate-authentication,MutualAuthentication={ClientRootCertificateChainArn=$CLIENT_CERT_ARN}" \
    --connection-log-options "Enabled=false" \
    --dns-servers "${DNS_SERVERS_FOR_CLI[@]}" \
    --transport-protocol "$TRANSPORT_PROTOCOL" \
    --vpc-id "$VPC_ID" \
    --security-group-ids "$SG_ID" \
    --tag-specifications "ResourceType=client-vpn-endpoint,Tags=[{Key=Name,Value=${VPN_NAME_TAG}}]" \
    --region "$AWS_REGION" \
    --query 'ClientVpnEndpointId' --output text 2>&1)
CLIENT_VPN_ENDPOINT_ID_COMMAND_EXIT_CODE=$?
set -e

log "DEBUG: 'aws ec2 create-client-vpn-endpoint' command finished."
log "DEBUG: Exit code: ${CLIENT_VPN_ENDPOINT_ID_COMMAND_EXIT_CODE}"
log "DEBUG: Output:"
echo "--- CREATE CLIENT VPN ENDPOINT OUTPUT START ---"
echo "${CLIENT_VPN_ENDPOINT_ID_COMMAND_OUTPUT}"
echo "--- CREATE CLIENT VPN ENDPOINT OUTPUT END ---"

if [ "${CLIENT_VPN_ENDPOINT_ID_COMMAND_EXIT_CODE}" -ne 0 ]; then
    if echo "${CLIENT_VPN_ENDPOINT_ID_COMMAND_OUTPUT}" | grep -q "usage: aws"; then
         error "Failed to create Client VPN Endpoint due to incorrect options (AWS CLI usage help shown). Exit Code: ${CLIENT_VPN_ENDPOINT_ID_COMMAND_EXIT_CODE}. Output above."
    elif echo "${CLIENT_VPN_ENDPOINT_ID_COMMAND_OUTPUT}" | grep -q "command not found"; then
         error "Failed to create Client VPN Endpoint due to a shell parsing error. Exit Code: ${CLIENT_VPN_ENDPOINT_ID_COMMAND_EXIT_CODE}. Output above."
    else
         error "Failed to create Client VPN Endpoint. Exit Code: ${CLIENT_VPN_ENDPOINT_ID_COMMAND_EXIT_CODE}. Output above."
    fi
fi

CLIENT_VPN_ENDPOINT_ID="${CLIENT_VPN_ENDPOINT_ID_COMMAND_OUTPUT}"
if [[ ! "$CLIENT_VPN_ENDPOINT_ID" == cvpn-endpoint-* ]]; then
    error "Failed to parse Client VPN Endpoint ID. The command output was: '${CLIENT_VPN_ENDPOINT_ID_COMMAND_OUTPUT}'. Expected 'cvpn-endpoint-...'"
fi
log "Client VPN Endpoint ID: ${CLIENT_VPN_ENDPOINT_ID} created. Initial state typically 'pending-associate'."

# 5. Associate Target Network
log "Associating Target Network (Subnet: $SUBNET_ID) with $CLIENT_VPN_ENDPOINT_ID..."
set +e
ASSOCIATION_COMMAND_OUTPUT=$(aws ec2 associate-client-vpn-target-network \
    --client-vpn-endpoint-id "$CLIENT_VPN_ENDPOINT_ID" \
    --subnet-id "$SUBNET_ID" \
    --region "$AWS_REGION" \
    --output json 2>&1)
ASSOCIATION_COMMAND_EXIT_CODE=$?
set -e

log "DEBUG: 'aws ec2 associate-client-vpn-target-network' command finished."
log "DEBUG: Exit code: ${ASSOCIATION_COMMAND_EXIT_CODE}"
log "DEBUG: Output:"
echo "--- ASSOCIATE TARGET NETWORK OUTPUT START ---"
echo "${ASSOCIATION_COMMAND_OUTPUT}"
echo "--- ASSOCIATE TARGET NETWORK OUTPUT END ---"

if [ "${ASSOCIATION_COMMAND_EXIT_CODE}" -ne 0 ]; then
    error "Failed to initiate target network association. Exit Code: ${ASSOCIATION_COMMAND_EXIT_CODE}. Output above."
fi

ASSOCIATION_ID=$(echo "$ASSOCIATION_COMMAND_OUTPUT" | jq -r '.AssociationId // empty')

if [ -z "$ASSOCIATION_ID" ]; then
    error "Failed to parse AssociationId from 'associate-client-vpn-target-network' output. Full output was: $ASSOCIATION_COMMAND_OUTPUT"
fi
log "Target network association initiated with Association ID: $ASSOCIATION_ID. Waiting for it to become 'associated'."

# Wait for association to be 'associated'
MAX_ASSOC_RETRIES=24 # Approx 4 minutes (24 * 10s)
ASSOC_RETRY_COUNT=0
ASSOC_STATUS=""
while true; do # Loop indefinitely until success or timeout
    # Query by Association ID for precise status
    ASSOC_DETAILS_OUTPUT=$(aws ec2 describe-client-vpn-target-networks \
        --client-vpn-endpoint-id "$CLIENT_VPN_ENDPOINT_ID" \
        --association-ids "$ASSOCIATION_ID" \
        --region "$AWS_REGION" \
        --output json 2>/dev/null) # Suppress stderr for transient errors

    if [ -n "$ASSOC_DETAILS_OUTPUT" ] && echo "$ASSOC_DETAILS_OUTPUT" | jq -e '.ClientVpnTargetNetworks[0]' > /dev/null; then
        ASSOC_STATUS=$(echo "$ASSOC_DETAILS_OUTPUT" | jq -r ".ClientVpnTargetNetworks[0].Status.Code")
    else
        # If describe call fails or returns empty, assume pending or still creating
        ASSOC_STATUS="associating" # Or "pending", or "checking"
        log "DEBUG: Waiting for association details to populate for $ASSOCIATION_ID..."
    fi

    log "Current association status for $ASSOCIATION_ID (Subnet $SUBNET_ID): $ASSOC_STATUS"
    if [ "$ASSOC_STATUS" = "associated" ]; then
        log "Target network $SUBNET_ID successfully associated with $CLIENT_VPN_ENDPOINT_ID."
        break
    elif [ "$ASSOC_STATUS" = "failed" ] || [ "$ASSOC_STATUS" = "disassociated" ]; then
         # Get more details on failure if possible
        ASSOC_STATUS_MESSAGE=$(echo "$ASSOC_DETAILS_OUTPUT" | jq -r ".ClientVpnTargetNetworks[0].Status.Message // \"No additional message\"")
        error "Target network association $ASSOCIATION_ID failed or disassociated. Status: $ASSOC_STATUS. Message: $ASSOC_STATUS_MESSAGE. Endpoint: $CLIENT_VPN_ENDPOINT_ID"
    fi

    ASSOC_RETRY_COUNT=$((ASSOC_RETRY_COUNT + 1))
    if [ "$ASSOC_RETRY_COUNT" -ge "$MAX_ASSOC_RETRIES" ]; then
        error "Target network association $ASSOCIATION_ID did not become 'associated' after $MAX_ASSOC_RETRIES retries. Last status: $ASSOC_STATUS. Endpoint: $CLIENT_VPN_ENDPOINT_ID"
    fi
    sleep 10
done

# Now, wait for the Client VPN Endpoint itself to become "available"
log "Waiting for Client VPN Endpoint $CLIENT_VPN_ENDPOINT_ID to become available (this may take a few minutes)..."
MAX_ENDPOINT_RETRIES=18 # Approx 3 minutes post-association
ENDPOINT_RETRY_COUNT=0
ENDPOINT_STATE=""
while true; do # Loop indefinitely
    ENDPOINT_STATE_OUTPUT=$(aws ec2 describe-client-vpn-endpoints \
        --client-vpn-endpoint-ids "$CLIENT_VPN_ENDPOINT_ID" \
        --region "$AWS_REGION" \
        --query 'ClientVpnEndpoints[0].Status.Code' --output text 2>/dev/null)

    if [ -n "$ENDPOINT_STATE_OUTPUT" ]; then
        ENDPOINT_STATE="$ENDPOINT_STATE_OUTPUT"
    else
        ENDPOINT_STATE="provisioning" # Or "checking"
        log "DEBUG: Waiting for endpoint details to populate for $CLIENT_VPN_ENDPOINT_ID..."
    fi

    log "Current endpoint state for $CLIENT_VPN_ENDPOINT_ID: $ENDPOINT_STATE"
    if [ "$ENDPOINT_STATE" = "available" ]; then
        log "Client VPN Endpoint $CLIENT_VPN_ENDPOINT_ID is available."
        break
    elif [ "$ENDPOINT_STATE" = "deleted" ] || [ "$ENDPOINT_STATE" = "deleting" ]; then
        error "Client VPN Endpoint $CLIENT_VPN_ENDPOINT_ID is $ENDPOINT_STATE. Aborting."
    fi

    ENDPOINT_RETRY_COUNT=$((ENDPOINT_RETRY_COUNT + 1))
    if [ "$ENDPOINT_RETRY_COUNT" -ge "$MAX_ENDPOINT_RETRIES" ]; then
        error "Client VPN Endpoint $CLIENT_VPN_ENDPOINT_ID did not become available after $MAX_ENDPOINT_RETRIES retries (post-association). Last state: $ENDPOINT_STATE"
    fi
    sleep 10
done


# 6. Add Authorization Rule (Allow all clients to access internet)
log "Adding Authorization Rule for 0.0.0.0/0..."
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

# Remove existing cert/key placeholders if any
CLEAN_CONFIG=$(echo "${CLIENT_CONFIG}" | sed '/<cert>/,/<\/cert>/d' | sed '/<key>/,/<\/key>/d')

# Add 'remote-cert-tls server'
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

4. Delete local Easy-RSA directory (cloned by the script):
   rm -rf "${EASYRSA_DIR}"
   rm -f "${OVPN_FILE_NAME}"
---
EOF