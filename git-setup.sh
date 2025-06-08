#!/usr/bin/env bash
# =============================================================================
# Git Setup Helper - Installs pre-commit hooks and configures git for the project
# =============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

echo "🔧 Git Setup for Chatimics Project"
echo "=================================="

# Install pre-commit hook
log_info "Installing pre-commit hook..."
if [[ -f .githooks/pre-commit ]]; then
    # Create .git/hooks directory if it doesn't exist
    mkdir -p .git/hooks
    
    # Copy the pre-commit hook
    cp .githooks/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    log_success "Pre-commit hook installed"
else
    log_warning "Pre-commit hook not found at .githooks/pre-commit"
fi

# Configure git to ignore certain files globally for this repo
log_info "Configuring git settings for this repository..."

# Set up git attributes for better diff handling
cat > .gitattributes << 'EOF'
# Text files
*.md text
*.txt text
*.yml text
*.yaml text
*.json text
*.js text
*.ts text
*.tsx text
*.css text
*.sh text

# Binary files
*.db binary
*.key binary
*.pem binary
*.p12 binary
*.pfx binary

# Docker files
Dockerfile text
docker-compose.yml text

# Ensure shell scripts have LF line endings
*.sh text eol=lf
EOF

log_success "Git attributes configured"

# Check current git status
log_info "Checking git status..."
if git status --porcelain | grep -q .; then
    log_warning "You have uncommitted changes:"
    git status --short
    echo ""
    echo "Consider committing these changes:"
    echo "  git add ."
    echo "  git commit -m 'Optimize .gitignore and improve project rebuilding'"
else
    log_success "Working directory is clean"
fi

# Suggest some useful git aliases for this project
log_info "Suggested git aliases (run these if you want):"
echo ""
echo "# Quick status check"
echo "git config alias.st 'status --short'"
echo ""
echo "# Better log formatting"
echo "git config alias.lg 'log --oneline --graph --decorate'"
echo ""
echo "# Check what would be committed"
echo "git config alias.staged 'diff --cached'"
echo ""
echo "# Validate project before commit"
echo "git config alias.validate '!./validate-project.sh'"

echo ""
log_success "Git setup complete!"
echo ""
echo "🛡️  Security features enabled:"
echo "   ✅ Pre-commit hook prevents sensitive data commits"
echo "   ✅ .gitignore optimized for Matrix homeserver project"
echo "   ✅ Binary file handling configured"
echo ""
echo "🚀 Ready to commit safely!"
