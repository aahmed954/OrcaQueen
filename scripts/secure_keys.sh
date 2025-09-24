#!/bin/bash
# Secure API keys integration script
# This script safely integrates API keys into the deployment

set -euo pipefail

# Create secure .env file with proper permissions
create_secure_env() {
    local ENV_FILE="/home/starlord/OrcaQueen/.env"

    # Set restrictive permissions
    touch "$ENV_FILE"
    chmod 600 "$ENV_FILE"

    echo "✅ Created secure .env file with 600 permissions"
    echo "⚠️  NEVER commit this file to Git"
}

# Verify .gitignore includes .env
verify_gitignore() {
    if grep -q "^\.env$" /home/starlord/OrcaQueen/.gitignore; then
        echo "✅ .env is in .gitignore"
    else
        echo "❌ Adding .env to .gitignore for security"
        echo ".env" >> /home/starlord/OrcaQueen/.gitignore
    fi
}

# Main
create_secure_env
verify_gitignore

echo "🔒 Security measures applied. Your API keys are protected."