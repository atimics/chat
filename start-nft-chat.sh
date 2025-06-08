#!/bin/bash

# Chatimics NFT-Gated Matrix Server Startup Script
# This script builds and starts all containerized services

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
    echo_log "Creating .env from .env.example..."
    cp .env.example .env
    echo_warning "Please edit .env file with your configuration before continuing"
    exit 1
fi

# Source environment variables
source .env

# Check required environment variables
REQUIRED_VARS=(
    "HELIUS_API_KEY"
    "AUTHORIZED_NFT_CREATORS"
    "SYNAPSE_ADMIN_TOKEN"
    "MAIN_ROOM_ID"
)

echo_log "Checking required environment variables..."
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo_error "Required environment variable $var is not set"
        exit 1
    fi
done
echo_success "All required environment variables are set"

# Create required directories
echo_log "Creating required directories..."
mkdir -p nft_auth_system/data
mkdir -p synapse_server/data
mkdir -p app_main/server
echo_success "Directories created"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

echo_success "Docker is running"

# Stop any existing containers
echo_log "Stopping any existing containers..."
docker-compose down --remove-orphans

# Build images
echo_log "Building Docker images..."
docker-compose build --no-cache

# Start services
echo_log "Starting services..."
docker-compose up -d

# Wait for services to be healthy
echo_log "Waiting for services to start..."
sleep 10

# Check service health
echo_log "Checking service health..."

# Check Synapse
if curl -sf http://localhost:8008/_matrix/client/versions > /dev/null; then
    echo_success "Matrix Synapse is running"
else
    echo_warning "Matrix Synapse may not be ready yet"
fi

# Check NFT Auth Service
if curl -sf http://localhost:3002/health > /dev/null; then
    echo_success "NFT Auth Service is running"
else
    echo_warning "NFT Auth Service may not be ready yet"
fi

# Check Web Client
if curl -sf http://localhost:3000 > /dev/null; then
    echo_success "Web Client is running"
else
    echo_warning "Web Client may not be ready yet"
fi

echo_log "Services started successfully!"
echo ""
echo_log "🌐 Access your NFT-gated chat at: http://localhost:3000"
echo_log "🔧 Admin API available at: http://localhost:3002/admin"
echo_log "📊 Matrix API available at: http://localhost:8008"
echo ""
echo_log "📋 To view logs:"
echo_log "   docker-compose logs -f [service-name]"
echo_log "   Services: synapse, nft-auth, webclient, cloudflared"
echo ""
echo_log "🛑 To stop all services:"
echo_log "   docker-compose down"
echo ""
echo_log "🔑 Authorized NFT Creators: ${AUTHORIZED_NFT_CREATORS}"
echo_log "🏠 Main Room ID: ${MAIN_ROOM_ID}"

# Show real-time logs from all services
echo_log "Showing real-time logs (Ctrl+C to exit)..."
docker-compose logs -f
