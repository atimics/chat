#!/bin/bash

# NFT Auth System Admin Script
# Manage authorized creators, users, and system configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

echo_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

echo_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if .env file exists
if [[ ! -f .env ]]; then
    echo_error ".env file not found!"
    exit 1
fi

source .env

NFT_AUTH_API="http://localhost:3002"

# Function to check if service is running
check_service() {
    if curl -sf "$NFT_AUTH_API/health" > /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to list registered users
list_users() {
    echo_log "Fetching registered users..."
    
    if ! check_service; then
        echo_error "NFT Auth Service is not running. Start it with: ./start-nft-chat.sh"
        exit 1
    fi
    
    curl -s -H "Authorization: Bearer $SYNAPSE_ADMIN_TOKEN" \
         "$NFT_AUTH_API/admin/users" | \
    jq -r '.users[] | "\(.pseudonym) (@\(.matrix_user_id)) - Wallet: \(.wallet_address[0:8])... - NFT Creator: \(.nft_creator_address[0:8])... - Registered: \(.registration_timestamp) - Active: \(.is_active)"'
}

# Function to show system status
show_status() {
    echo_log "System Status:"
    echo ""
    
    # Check service health
    if check_service; then
        echo_success "NFT Auth Service: Running"
        
        # Get health info
        HEALTH=$(curl -s "$NFT_AUTH_API/health")
        echo_log "Authorized Creators: $(echo "$HEALTH" | jq -r '.authorizedCreators')"
        echo_log "Last Check: $(echo "$HEALTH" | jq -r '.timestamp')"
    else
        echo_error "NFT Auth Service: Not Running"
    fi
    
    # Check Matrix
    if curl -sf http://localhost:8008/_matrix/client/versions > /dev/null; then
        echo_success "Matrix Synapse: Running"
    else
        echo_error "Matrix Synapse: Not Running"
    fi
    
    # Check database
    if [[ -f "$NFT_AUTH_DB_PATH" ]]; then
        USER_COUNT=$(sqlite3 "$NFT_AUTH_DB_PATH" "SELECT COUNT(*) FROM nft_registrations WHERE is_active = 1;" 2>/dev/null || echo "0")
        echo_log "Active Users: $USER_COUNT"
    else
        echo_warning "Database not found: $NFT_AUTH_DB_PATH"
    fi
}

# Function to add authorized creator
add_creator() {
    echo_log "Adding new authorized NFT creator..."
    echo -n "Enter Solana wallet address: "
    read -r wallet_address
    
    if [[ ${#wallet_address} -lt 32 ]]; then
        echo_error "Invalid Solana wallet address"
        exit 1
    fi
    
    # Update .env file
    if grep -q "AUTHORIZED_NFT_CREATORS=" .env; then
        # Add to existing list
        sed -i.bak "s/AUTHORIZED_NFT_CREATORS=\(.*\)/AUTHORIZED_NFT_CREATORS=\1,$wallet_address/" .env
    else
        # Create new entry
        echo "AUTHORIZED_NFT_CREATORS=$wallet_address" >> .env
    fi
    
    echo_success "Added creator: $wallet_address"
    echo_warning "Restart the service for changes to take effect: docker-compose restart nft-auth"
}

# Function to create main room
create_main_room() {
    echo_log "Creating main chat room..."
    
    # Create room via Matrix API
    ROOM_RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer $SYNAPSE_ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        "http://localhost:8008/_matrix/client/r0/createRoom" \
        -d '{
            "name": "Chatimics Main",
            "topic": "Welcome to the NFT-gated community chat!",
            "preset": "public_chat",
            "visibility": "public"
        }')
    
    ROOM_ID=$(echo "$ROOM_RESPONSE" | jq -r '.room_id')
    
    if [[ "$ROOM_ID" != "null" && "$ROOM_ID" != "" ]]; then
        echo_success "Created room: $ROOM_ID"
        echo_log "Update your .env file with: MAIN_ROOM_ID=$ROOM_ID"
    else
        echo_error "Failed to create room"
        echo "$ROOM_RESPONSE"
    fi
}

# Function to show help
show_help() {
    echo "NFT Auth System Admin Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  status        Show system status"
    echo "  users         List registered users"
    echo "  add-creator   Add authorized NFT creator"
    echo "  create-room   Create main chat room"
    echo "  logs          Show service logs"
    echo "  restart       Restart NFT auth service"
    echo "  help          Show this help"
    echo ""
}

# Function to show logs
show_logs() {
    echo_log "Showing NFT Auth Service logs..."
    docker-compose logs -f nft-auth
}

# Function to restart service
restart_service() {
    echo_log "Restarting NFT Auth Service..."
    docker-compose restart nft-auth
    echo_success "Service restarted"
}

# Main command handling
case "${1:-help}" in
    "status")
        show_status
        ;;
    "users")
        list_users
        ;;
    "add-creator")
        add_creator
        ;;
    "create-room")
        create_main_room
        ;;
    "logs")
        show_logs
        ;;
    "restart")
        restart_service
        ;;
    "help"|*)
        show_help
        ;;
esac
