#!/usr/bin/env bash
# =============================================================================
# Chatimics Development Setup Script
# Quick setup for development environment
# =============================================================================

set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Docker status
check_docker() {
    if ! command_exists docker; then
        log_error "Docker not found. Please install Docker Desktop first."
        echo "Visit: https://www.docker.com/products/docker-desktop/"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker Desktop."
        exit 1
    fi
    
    log_success "Docker is running"
}

# Main setup function
main() {
    echo "🚀 Chatimics Development Setup"
    echo "================================"
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    check_docker
    
    # Check if .env exists
    if [[ ! -f .env ]]; then
        if [[ -f .env.example ]]; then
            log_info "Creating .env from template..."
            cp .env.example .env
            log_warning "Please edit .env with your actual configuration values"
            log_info "Required: MATRIX_SERVER_URL, NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID, etc."
        else
            log_error ".env.example not found. Please check your project structure."
            exit 1
        fi
    else
        log_success ".env file exists"
    fi
    
    # Check Node.js for app_main
    if [[ -d app_main ]]; then
        log_info "Setting up web client dependencies..."
        cd app_main
        if [[ -f package.json ]]; then
            if command_exists npm; then
                npm install
                log_success "Web client dependencies installed"
            else
                log_warning "npm not found. Skipping web client dependency installation."
            fi
        fi
        cd ..
    fi
    
    # Install binary dependencies
    log_info "Installing binary dependencies..."
    if [[ -x "./install-binaries.sh" ]]; then
        ./install-binaries.sh --node --verify
        log_success "Binary dependencies installed"
    else
        log_warning "install-binaries.sh not found or not executable"
    fi
    
    # Validate docker-compose configuration
    log_info "Validating Docker Compose configuration..."
    if docker-compose config >/dev/null 2>&1; then
        log_success "Docker Compose configuration is valid"
    else
        log_error "Docker Compose configuration has errors"
        docker-compose config
        exit 1
    fi
    
    # Pull Docker images
    log_info "Pulling Docker images..."
    docker-compose pull
    log_success "Docker images updated"
    
    # Check if synapse_server/data exists and has templates
    if [[ ! -d synapse_server/data ]]; then
        log_info "Creating synapse_server/data directory..."
        mkdir -p synapse_server/data
    fi
    
    # Initialize homeserver.yaml if needed
    if [[ ! -f synapse_server/data/homeserver.yaml ]] && [[ -f synapse_server/data/homeserver.yaml.template ]]; then
        log_info "Initializing homeserver.yaml from template..."
        cp synapse_server/data/homeserver.yaml.template synapse_server/data/homeserver.yaml
        log_warning "Please configure synapse_server/data/homeserver.yaml with your domain"
    fi
    
    # Start services
    log_info "Starting services..."
    docker-compose up -d
    
    # Wait a moment for services to start
    sleep 5
    
    # Check service status
    log_info "Checking service status..."
    if docker-compose ps | grep -q "Up"; then
        log_success "Services are running"
        
        echo ""
        echo "🎉 Setup Complete!"
        echo "=================="
        echo "Services running:"
        docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
        echo ""
        echo "📝 Next steps:"
        echo "1. Configure .env with your actual values"
        echo "2. Update synapse_server/data/homeserver.yaml with your domain"
        echo "3. Set up Cloudflare tunnel configuration"
        echo "4. Register admin user: ./register_admin.sh -u admin -p password -d yourdomain.com"
        echo ""
        echo "📚 For detailed setup guide, see: PROJECT_SETUP.md"
        echo ""
        echo "🔍 View logs: docker-compose logs -f"
        echo "🛑 Stop services: docker-compose down"
        
    else
        log_error "Some services failed to start"
        echo "Service status:"
        docker-compose ps
        echo ""
        echo "Check logs with: docker-compose logs"
    fi
}

# Script options
case "${1:-}" in
    --clean)
        log_info "Cleaning up containers and volumes..."
        docker-compose down -v
        docker system prune -f
        log_success "Cleanup complete"
        ;;
    --logs)
        docker-compose logs -f
        ;;
    --status)
        docker-compose ps
        ;;
    --help|-h)
        echo "Chatimics Development Setup"
        echo ""
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "Options:"
        echo "  (no args)    Run full development setup"
        echo "  --clean      Clean up containers and volumes"
        echo "  --logs       Follow service logs"
        echo "  --status     Show service status"
        echo "  --help       Show this help message"
        echo ""
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
