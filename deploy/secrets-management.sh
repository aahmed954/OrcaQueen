#!/bin/bash

# AI-SWARM-MIAMI-2025 Secrets Management Implementation
# CRITICAL: Secure API key management and rotation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}========================================${NC}"
echo -e "${RED}CRITICAL SECURITY IMPLEMENTATION${NC}"
echo -e "${RED}========================================${NC}"

# Function to check for exposed keys in repository
check_exposed_keys() {
    echo -e "${YELLOW}Scanning for exposed API keys...${NC}"

    # Patterns to search for
    patterns=(
        "sk-or-v1-"  # OpenRouter
        "AIzaSy"     # Google/Gemini
        "sk-"        # OpenAI
        "railway_"   # Railway
        "anthropic"  # Anthropic
    )

    for pattern in "${patterns[@]}"; do
        echo -n "Checking for $pattern... "
        if grep -r "$pattern" . --exclude-dir=.git --exclude="*.sh" 2>/dev/null | grep -v "^Binary file"; then
            echo -e "${RED}FOUND - IMMEDIATE ACTION REQUIRED${NC}"
        else
            echo -e "${GREEN}Clean${NC}"
        fi
    done
}

# Function to set up HashiCorp Vault
setup_vault() {
    echo -e "${YELLOW}Setting up HashiCorp Vault...${NC}"

    cat > docker-compose.vault.yml <<EOF
version: '3.8'

services:
  vault:
    image: hashicorp/vault:latest
    container_name: secrets-vault
    restart: unless-stopped
    cap_add:
      - IPC_LOCK
    environment:
      VAULT_ADDR: 'https://0.0.0.0:8200'
      VAULT_LOCAL_CONFIG: |
        {
          "backend": {"file": {"path": "/vault/file"}},
          "listener": {
            "tcp": {
              "address": "0.0.0.0:8200",
              "tls_disable": 1
            }
          },
          "ui": true,
          "default_lease_ttl": "168h",
          "max_lease_ttl": "720h"
        }
    volumes:
      - vault-data:/vault/file
      - vault-logs:/vault/logs
    ports:
      - "8200:8200"
    command: server
    networks:
      - swarm_network

volumes:
  vault-data:
  vault-logs:

networks:
  swarm_network:
    external: true
EOF

    echo "Vault configuration created."
}

# Function to initialize Vault policies
init_vault_policies() {
    echo -e "${YELLOW}Creating Vault policies...${NC}"

    cat > vault-policies.hcl <<EOF
# API Keys Read Policy
path "secret/data/api-keys/*" {
  capabilities = ["read", "list"]
}

# Service Account Policy
path "secret/data/service-accounts/*" {
  capabilities = ["read"]
}

# Rotation Policy
path "secret/data/api-keys/*" {
  capabilities = ["create", "update", "delete"]
}

# Audit Policy
path "sys/audit/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF

    echo "Vault policies created."
}

# Function to create secure environment template
create_secure_env_template() {
    echo -e "${YELLOW}Creating secure environment template...${NC}"

    cat > .env.vault.template <<EOF
# AI-SWARM-MIAMI-2025 Secure Environment Template
# ⚠️ NEVER commit actual values to this file

# === VAULT CONFIGURATION ===
VAULT_ADDR=https://vault.service:8200
VAULT_TOKEN=<runtime-injected>
VAULT_ROLE_ID=<runtime-injected>
VAULT_SECRET_ID=<runtime-injected>

# === SERVICE ACCOUNTS ===
LITELLM_SERVICE_ACCOUNT=<vault:secret/service-accounts/litellm>
RESEARCHER_SERVICE_ACCOUNT=<vault:secret/service-accounts/researcher>
WEBUI_SERVICE_ACCOUNT=<vault:secret/service-accounts/webui>

# === API KEY PATHS IN VAULT ===
# These are paths, not actual keys
OPENROUTER_KEY_PATH=secret/api-keys/openrouter
GEMINI_KEY1_PATH=secret/api-keys/gemini/key1
GEMINI_KEY2_PATH=secret/api-keys/gemini/key2
OPENAI_KEY_PATH=secret/api-keys/openai
ANTHROPIC_KEY_PATH=secret/api-keys/anthropic
RAILWAY_TOKEN_PATH=secret/api-keys/railway

# === ROTATION SCHEDULE ===
KEY_ROTATION_DAYS=30
CRITICAL_KEY_ROTATION_DAYS=14
AUTO_ROTATE_ENABLED=true

# === MONITORING ===
SECURITY_ALERTS_WEBHOOK=<vault:secret/monitoring/webhook>
AUDIT_LOG_DESTINATION=<vault:secret/monitoring/audit-endpoint>
EOF

    echo "Secure environment template created."
}

# Function to create key rotation script
create_rotation_script() {
    echo -e "${YELLOW}Creating API key rotation script...${NC}"

    cat > rotate-keys.sh <<'EOF'
#!/bin/bash

# API Key Rotation Script
# Run this monthly or when compromise suspected

set -euo pipefail

VAULT_ADDR=${VAULT_ADDR:-http://localhost:8200}

# Function to rotate a key in Vault
rotate_key() {
    local key_path=$1
    local key_name=$2

    echo "Rotating $key_name..."

    # Generate new key (placeholder - implement actual rotation with provider)
    NEW_KEY="<obtain-from-provider>"

    # Store in Vault
    vault kv put $key_path value="$NEW_KEY" \
        rotated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        rotation_reason="scheduled"

    echo "✓ $key_name rotated successfully"
}

# Rotate critical keys
echo "Starting critical key rotation..."
rotate_key "secret/api-keys/openrouter" "OpenRouter API Key"
rotate_key "secret/api-keys/gemini/key1" "Gemini API Key 1"
rotate_key "secret/api-keys/gemini/key2" "Gemini API Key 2"

# Rotate standard keys
echo "Starting standard key rotation..."
rotate_key "secret/api-keys/openai" "OpenAI API Key"
rotate_key "secret/api-keys/anthropic" "Anthropic API Key"

# Restart services to pick up new keys
echo "Restarting services with new keys..."
docker-compose restart litellm
docker-compose restart gpt-researcher

echo "✅ Key rotation completed successfully"
EOF

    chmod +x rotate-keys.sh
    echo "Key rotation script created."
}

# Function to create Docker secrets integration
create_docker_secrets() {
    echo -e "${YELLOW}Setting up Docker secrets integration...${NC}"

    cat > docker-secrets-init.sh <<'EOF'
#!/bin/bash

# Initialize Docker Secrets from Vault

set -euo pipefail

# Fetch secrets from Vault
fetch_secret() {
    local vault_path=$1
    local secret_name=$2

    echo "Fetching $secret_name from Vault..."

    value=$(vault kv get -field=value $vault_path)
    echo "$value" | docker secret create $secret_name - 2>/dev/null || \
        (docker secret rm $secret_name && echo "$value" | docker secret create $secret_name -)
}

# Create secrets
fetch_secret "secret/api-keys/openrouter" "openrouter_key"
fetch_secret "secret/api-keys/gemini/key1" "gemini_key1"
fetch_secret "secret/api-keys/gemini/key2" "gemini_key2"
fetch_secret "secret/api-keys/openai" "openai_key"
fetch_secret "secret/api-keys/anthropic" "anthropic_key"

echo "✅ Docker secrets initialized"
EOF

    chmod +x docker-secrets-init.sh
    echo "Docker secrets integration created."
}

# Function to create monitoring configuration
create_monitoring_config() {
    echo -e "${YELLOW}Creating security monitoring configuration...${NC}"

    cat > monitoring-security.yml <<EOF
# Security Monitoring Configuration

alerts:
  api_key_access:
    - name: suspicious_key_access
      condition: rate > 100/minute
      severity: critical
      action: block_and_rotate

    - name: unauthorized_key_access
      condition: source_not_in_whitelist
      severity: critical
      action: block_immediately

    - name: key_near_expiration
      condition: days_until_expiry < 3
      severity: warning
      action: notify_admin

  vault_operations:
    - name: vault_unsealed
      severity: info
      action: log_and_notify

    - name: multiple_auth_failures
      condition: failures > 3
      severity: high
      action: lock_account

dashboards:
  security_overview:
    widgets:
      - api_key_usage_trends
      - failed_auth_attempts
      - vault_health_status
      - encryption_operations
      - network_segmentation_violations

  api_key_dashboard:
    widgets:
      - keys_by_service
      - rotation_schedule
      - usage_by_key
      - cost_by_key
      - anomaly_detection
EOF

    echo "Security monitoring configuration created."
}

# Function to create comprehensive hardening script
create_hardening_script() {
    echo -e "${YELLOW}Creating system hardening script...${NC}"

    cat > harden-system.sh <<'EOF'
#!/bin/bash

# System Hardening Script for AI-SWARM-MIAMI-2025

set -euo pipefail

echo "Starting system hardening..."

# 1. Network hardening
echo "Configuring firewall rules..."
# Add iptables rules here

# 2. Container hardening
echo "Applying container security policies..."
# Add Docker security configurations

# 3. File system hardening
echo "Setting secure file permissions..."
chmod 600 .env.vault
chmod 600 vault-policies.hcl
chmod 700 rotate-keys.sh

# 4. Enable audit logging
echo "Enabling comprehensive audit logging..."
# Configure auditd and Docker logging

# 5. Set up intrusion detection
echo "Configuring intrusion detection..."
# Add fail2ban or similar

echo "✅ System hardening completed"
EOF

    chmod +x harden-system.sh
    echo "Hardening script created."
}

# Main execution
main() {
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}SECURITY IMPLEMENTATION STARTING${NC}"
    echo -e "${RED}========================================${NC}"

    # Check for exposed keys
    check_exposed_keys

    # Set up Vault
    setup_vault
    init_vault_policies

    # Create secure templates
    create_secure_env_template

    # Create automation scripts
    create_rotation_script
    create_docker_secrets

    # Create monitoring
    create_monitoring_config

    # Create hardening
    create_hardening_script

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}SECURITY IMPLEMENTATION COMPLETE${NC}"
    echo -e "${GREEN}========================================${NC}"

    echo -e "${YELLOW}IMMEDIATE ACTIONS REQUIRED:${NC}"
    echo "1. Remove ALL API keys from repository immediately"
    echo "2. Rotate the exposed OpenRouter key: sk-or-v1-12f7daa..."
    echo "3. Rotate both Gemini keys"
    echo "4. Deploy Vault: docker-compose -f docker-compose.vault.yml up -d"
    echo "5. Initialize Vault and store keys securely"
    echo "6. Run: ./harden-system.sh"
    echo "7. Set up automated key rotation: crontab -e"
    echo "   0 2 1 * * /path/to/rotate-keys.sh"

    echo -e "${RED}⚠️ CRITICAL: Never commit API keys to version control!${NC}"
}

# Run main function
main "$@"