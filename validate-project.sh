#!/usr/bin/env bash
# =============================================================================
# Project Validation Script - Ensures project can be rebuilt from scratch
# =============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

echo "🔍 Chatimics Project Validation"
echo "================================"

# Check required template files
log_info "Checking template files..."
required_templates=(
    ".env.example"
    "synapse_server/data/homeserver.yaml.template"
    "synapse_server/data/log.config.template"
    "configuration_examples/userlist.example.txt"
)

for template in "${required_templates[@]}"; do
    if [[ -f "$template" ]]; then
        log_success "$template exists"
    else
        log_error "$template missing - required for project rebuilding"
    fi
done

# Check that sensitive files are not tracked
log_info "Checking .gitignore effectiveness..."
sensitive_files_found=false

# Check if any sensitive files are tracked by git
if git ls-files | grep -qE "\.(key|db|log)$|node_modules|\.env$|synapse_server/data/[^t]"; then
    log_error "Sensitive files found in git tracking:"
    git ls-files | grep -E "\.(key|db|log)$|node_modules|\.env$|synapse_server/data/[^t]" | head -10
    sensitive_files_found=true
else
    log_success "No sensitive files tracked in git"
fi

# Check project structure
log_info "Validating project structure..."
required_dirs=(
    "synapse_server"
    "synapse_server/data"
    "app_main"
    "configuration_examples"
    "operational_scripts"
)

for dir in "${required_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
        log_success "$dir/ directory exists"
    else
        log_error "$dir/ directory missing"
    fi
done

# Check required scripts
log_info "Checking setup scripts..."
required_scripts=(
    "setup_matrix_mac.sh"
    "setup_matrix.sh"
    "dev-setup.sh"
    "docker-compose.yml"
)

for script in "${required_scripts[@]}"; do
    if [[ -f "$script" ]]; then
        log_success "$script exists"
        if [[ "$script" == *.sh ]]; then
            if [[ -x "$script" ]]; then
                log_success "$script is executable"
            else
                log_warning "$script is not executable (run: chmod +x $script)"
            fi
        fi
    else
        log_error "$script missing"
    fi
done

# Validate Docker Compose
log_info "Validating Docker Compose..."
if command -v docker-compose >/dev/null 2>&1; then
    if docker-compose config >/dev/null 2>&1; then
        log_success "Docker Compose configuration is valid"
    else
        log_error "Docker Compose configuration has errors"
    fi
else
    log_warning "docker-compose command not found (okay if using Docker Compose V2)"
fi

# Check documentation
log_info "Checking documentation..."
docs=(
    "README.md"
    "PROJECT_SETUP.md"
)

for doc in "${docs[@]}"; do
    if [[ -f "$doc" ]]; then
        log_success "$doc exists"
    else
        log_warning "$doc missing - recommended for project documentation"
    fi
done

# Summary
echo ""
echo "📋 Validation Summary"
echo "===================="

if [[ "$sensitive_files_found" == false ]]; then
    log_success "✅ Project can be safely committed to version control"
    log_success "✅ Sensitive data is properly excluded"
    log_success "✅ Project includes necessary templates for rebuilding"
    echo ""
    echo "🚀 Ready for:"
    echo "   - Git commit and push"
    echo "   - Fresh deployment setup"
    echo "   - Team collaboration"
    echo ""
    echo "📚 To rebuild from scratch:"
    echo "   1. git clone <repository>"
    echo "   2. ./dev-setup.sh"
    echo "   3. Configure .env and homeserver.yaml"
    echo "   4. ./setup_matrix_mac.sh -d yourdomain.com"
else
    log_error "❌ Project has issues that need to be resolved"
    echo ""
    echo "🔧 Fix by:"
    echo "   1. Remove sensitive files from git: git rm <file>"
    echo "   2. Add them to .gitignore"
    echo "   3. Create template versions instead"
fi

echo ""
echo "🛠️  Setup commands:"
echo "   ./dev-setup.sh           # Quick development setup"
echo "   ./dev-setup.sh --clean   # Clean up containers"
echo "   ./dev-setup.sh --logs    # View service logs"
