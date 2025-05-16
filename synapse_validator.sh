#!/usr/bin/env bash
# Enhanced Synapse Setup Validator with UI, Guided Fixes, Logging, and Component Status Summary
# Requires: bash, brew, docker, docker-compose, cloudflared, jq, curl, whiptail, dig

set -euo pipefail
# Improved trap to report failing command
trap 'last_cmd="$BASH_COMMAND"; echo "[ERROR] Command \"$last_cmd\" on line $LINENO failed." >&2; error "Command \"$last_cmd\" on line $LINENO failed."' ERR

# Status tracking using a simple string list
STATUS_LIST=""
record_status() { STATUS_LIST+="$1:$2\n"; }

# UI and logging functions
echo_log() { echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] $1"; }
error() { local msg="$1"; echo_log "[ERROR] $msg"; record_status "$CURRENT_CHECK" "FAIL"; whiptail --title "Error" --msgbox "$msg" 12 60; }
info() { whiptail --title "Info" --msgbox "$1" 10 60; }

# Ask for parameters via dialog
DOMAIN=$(whiptail --inputbox "Enter your fully qualified domain (e.g., chat.example.com):" 10 60 "" --title "Domain Input" 3>&1 1>&2 2>&3)
INSTALL_DIR=$(whiptail --inputbox "Install base directory:" 10 60 "${HOME}/matrix-synapse" --title "Install Directory" 3>&1 1>&2 2>&3)

# Set up logging to a file inside install dir
setup_log() { mkdir -p "$(dirname "$LOG_FILE")"; echo "Logging output to $LOG_FILE"; exec > >(tee -a "$LOG_FILE") 2>&1; }
LOG_FILE="${INSTALL_DIR}/synapse_validator.log"
setup_log

echo_log "Starting Synapse validator for domain=$DOMAIN, install_dir=$INSTALL_DIR"

if (whiptail --title "Skip DNS Automation?" --yesno "Do you want to skip DNS automation (Manual DNS on macOS)?" 8 60); then
  SKIP_DNS="yes"
else
  SKIP_DNS="no"
fi

# Colors for console fallback
RED="\033[0;31m"; GREEN="\033[0;32m"; NC="\033[0m"

# Validation functions
check_os() {
  CURRENT_CHECK="OS"
  echo_log "Checking OS"
  if [[ "$(uname)" != "Darwin" ]]; then
    error "This validator only supports macOS. You're running $(uname)."
    return
  fi
  record_status "$CURRENT_CHECK" "PASS"
  echo -e "${GREEN}macOS detected${NC}"
}

check_command() {
  local cmd="$1"; local install_hint="$2"
  CURRENT_CHECK="Command:$cmd"
  echo_log "Checking for $cmd"
  if ! command -v "$cmd" &>/dev/null; then
    error "$cmd not found. Install via: $install_hint"
    return
  fi
  record_status "$CURRENT_CHECK" "PASS"
  echo -e "${GREEN}$cmd available${NC}"
}

check_docker_daemon() {
  CURRENT_CHECK="DockerDaemon"
  echo_log "Checking Docker daemon"
  if ! docker info &>/dev/null; then
    whiptail --title "Docker Daemon" --msgbox "Docker Desktop is installed but not running. Please start Docker Desktop and click OK." 10 60
    until docker info &>/dev/null; do :; done
  fi
  record_status "$CURRENT_CHECK" "PASS"
  echo -e "${GREEN}Docker daemon running${NC}"
}

check_config() {
  local file="$1"; local desc="$2"
  CURRENT_CHECK="$desc"
  echo_log "Validating $desc at $file"
  if [[ ! -f "$file" ]]; then
    error "$desc file not found at $file"
    return
  fi
  record_status "$CURRENT_CHECK" "PASS"
  echo -e "${GREEN}$desc found${NC}"
}

validate_dns() {
  CURRENT_CHECK="DNS:SRV"
  echo_log "Validating SRV record for _matrix._tcp.$DOMAIN"
  local srv
  srv=$(dig +short SRV _matrix._tcp.${DOMAIN})
  if [[ -z "$srv" ]]; then
    error "No SRV record found for _matrix._tcp.${DOMAIN}. Create a record: _matrix._tcp.${DOMAIN} -> ${DOMAIN}:8448"
    return
  fi
  record_status "$CURRENT_CHECK" "PASS"
  echo -e "${GREEN}SRV record exists: $srv${NC}"
}

validate_https() {
  CURRENT_CHECK="HTTPS://$DOMAIN"
  echo_log "Testing HTTPS endpoint https://$DOMAIN"
  if ! curl -sSf --head "https://${DOMAIN}/_matrix/client/versions" &>/dev/null; then
    error "Failed to reach https://${DOMAIN}/_matrix/client/versions. Check TLS cert and Cloudflare tunnel."
    return
  fi
  record_status "$CURRENT_CHECK" "PASS"
  echo -e "${GREEN}HTTPS endpoint OK${NC}"
}

validate_tunnel() {
  CURRENT_CHECK="Tunnel:Metrics"
  echo_log "Validating Cloudflared tunnel metrics"
  if ! curl -sSf http://127.0.0.1:20242/metrics &>/dev/null; then
    record_status "$CURRENT_CHECK" "FAIL"
    echo -e "${RED}Cloudflared metrics endpoint unreachable${NC}"
  else
    record_status "$CURRENT_CHECK" "PASS"
    echo -e "${GREEN}Cloudflared metrics endpoint OK${NC}"
  fi

  CURRENT_CHECK="DNS:CNAME"
  echo_log "Checking CNAME record for $DOMAIN"
  local cname
  cname=$(dig +short CNAME ${DOMAIN})
  if [[ -z "$cname" ]]; then
    record_status "$CURRENT_CHECK" "FAIL"
    echo -e "${RED}No CNAME for ${DOMAIN}${NC}"
  else
    record_status "$CURRENT_CHECK" "PASS"
    echo -e "${GREEN}CNAME for ${DOMAIN}: ${cname}${NC}"
  fi
}

validate_synapse_service() {
  CURRENT_CHECK="Synapse:Container"
  echo_log "Checking Synapse Docker container"
  if (cd "$INSTALL_DIR" && docker-compose ps | grep -qE 'synapse.*Up'); then
    record_status "$CURRENT_CHECK" "PASS"
    echo -e "${GREEN}Synapse container running${NC}"
  else
    record_status "$CURRENT_CHECK" "FAIL"
    echo -e "${RED}Synapse container not running${NC}"
  fi

  CURRENT_CHECK="Synapse:HTTPAPI"
  echo_log "Testing Synapse HTTP API on localhost:8008"
  if ! curl -sSf --head "http://localhost:8008/_matrix/client/versions" &>/dev/null; then
    record_status "$CURRENT_CHECK" "FAIL"
    echo -e "${RED}Synapse HTTP API unreachable on port 8008${NC}"
  else
    record_status "$CURRENT_CHECK" "PASS"
    echo -e "${GREEN}Synapse HTTP API OK on port 8008${NC}"
  fi

  CURRENT_CHECK="Synapse:Federation"
  echo_log "Testing Synapse federation API on port 8448"
  if ! curl -sSf --head "http://${DOMAIN}:8448/federation/v1/version" &>/dev/null; then
    record_status "$CURRENT_CHECK" "FAIL"
    echo -e "${RED}Synapse federation API unreachable on port 8448${NC}"
  else
    record_status "$CURRENT_CHECK" "PASS"
    echo -e "${GREEN}Synapse federation API OK on port 8448${NC}"
  fi
}

# Run validations
printf "
=== Validating Environment ===
"
check_os
check_command brew "https://brew.sh/"
check_command docker "brew install docker"
check_command docker-compose "brew install docker-compose"
check_command cloudflared "brew install cloudflared"
check_command jq "brew install jq"
check_command curl "brew install curl"
check_docker_daemon

printf "
=== Validating Files ===
"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
check_config "$REPO_DIR/config.yml" "Cloudflare config"

TUNNEL_ID=$(grep -E '^tunnel:' "$REPO_DIR/config.yml" | awk '{print $2}')
check_config "$REPO_DIR/${TUNNEL_ID}.json" "Tunnel credentials"

printf "
=== Validating DNS & Connectivity ===
"
validate_dns
validate_https

printf "
=== Validating Tunnel ===
"
validate_tunnel

printf "
=== Validating Synapse Service ===
"
validate_synapse_service

# Summary of statuses
printf "
=== Component Status Summary ===
"
echo -e "$STATUS_LIST" | while IFS=":" read -r component status; do
  if [[ "$status" == "PASS" ]]; then
    echo -e "${GREEN}✔ $component${NC}"
  else
    echo -e "${RED}✘ $component${NC}"
  fi
done

info "All checks complete! Detailed logs in $LOG_FILE and summary above."
