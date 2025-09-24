#!/bin/bash
# AI-SWARM-MIAMI-2025 Master Deployment Script
# This script orchestrates the complete 3-node AI swarm deployment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT=$(dirname "$(realpath "$0")")
ORACLE_IP="100.96.197.84"
STARLORD_IP="100.72.73.3"
THANOS_IP="100.122.12.54"
DEPLOYMENT_MODE="${1:-production}"  # production or development

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          AI-SWARM-MIAMI-2025 DEPLOYMENT ORCHESTRATOR          ║${NC}"
echo -e "${BLUE}║                     Uncensored AI at Scale                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to print section headers
print_section() {
    echo -e "\n${CYAN}═══ $1 ═══${NC}\n"
}

# Function to check prerequisites
check_prerequisites() {
    print_section "CHECKING PREREQUISITES"

    # Check for required tools
    local tools=("docker" "docker-compose" "ssh" "git" "curl" "jq")
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            echo -e "${GREEN}[✓]${NC} $tool is installed"
        else
            echo -e "${RED}[✗]${NC} $tool is not installed"
            exit 1
        fi
    done

    # Check for .env file
    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        echo -e "${RED}[✗]${NC} .env file not found!"
        echo -e "${YELLOW}[!]${NC} Creating .env from template..."
        cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
        echo -e "${RED}[!]${NC} Please edit .env file with your actual values and run again"
        exit 1
    fi

    # Source environment variables
    set -a
    source "$PROJECT_ROOT/.env"
    set +a

    # Validate critical environment variables
    if [[ "$LITELLM_MASTER_KEY" == "sk-CHANGE-THIS-TO-SECURE-RANDOM-STRING" ]]; then
        echo -e "${RED}[✗]${NC} Default LITELLM_MASTER_KEY detected! Please change in .env"
        exit 1
    fi

    if [[ "$POSTGRES_PASSWORD" == "CHANGE-THIS-TO-SECURE-PASSWORD" ]]; then
        echo -e "${RED}[✗]${NC} Default POSTGRES_PASSWORD detected! Please change in .env"
        exit 1
    fi

    # ARM compatibility check for Oracle
    echo -e "${YELLOW}[→]${NC} Validating ARM compatibility on Oracle..."
    oracle_arch=$(ssh "root@$ORACLE_IP" "uname -m")
    if [[ "$oracle_arch" != "aarch64" ]]; then
        echo -e "${RED}[✗]${NC} Oracle node is not ARM64 (got $oracle_arch)"
        exit 1
    fi
    arm_test=$(ssh "root@$ORACLE_IP" "docker run --rm --platform linux/arm64 arm64v8/hello-world" 2>/dev/null || echo "failed")
    if [[ "$arm_test" != "failed" ]]; then
        echo -e "${GREEN}[✓]${NC} ARM Docker support confirmed on Oracle"
    else
        echo -e "${RED}[✗]${NC} ARM Docker test failed on Oracle"
        exit 1
    fi

    echo -e "${GREEN}[✓]${NC} All prerequisites met"
}

# Function to validate infrastructure
validate_infrastructure() {
    print_section "VALIDATING INFRASTRUCTURE"

    # Run the infrastructure validation script
    if bash "$PROJECT_ROOT/deploy/00-infrastructure-validation.sh"; then
        echo -e "${GREEN}[✓]${NC} Infrastructure validation passed"
    else
        echo -e "${RED}[✗]${NC} Infrastructure validation failed"
        exit 1
    fi
}

# Function to setup network
setup_network() {
    print_section "CONFIGURING NETWORK"

    echo -e "${YELLOW}[→]${NC} Setting up Tailscale routing..."

    # Enable IP forwarding
    echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf > /dev/null
    sudo sysctl -p > /dev/null

    # Configure Tailscale subnet routing
    sudo tailscale up --advertise-routes=172.20.0.0/24,172.21.0.0/24,172.22.0.0/24 \
        --accept-routes --accept-dns=false || true

    # Create Docker networks
    echo -e "${YELLOW}[→]${NC} Creating Docker networks..."
    docker network create aiswarm --subnet=172.21.0.0/24 2>/dev/null || true

    echo -e "${GREEN}[✓]${NC} Network configuration complete"
}

# Function to generate secrets
generate_secrets() {
    print_section "GENERATING SECRETS"

    # Generate secure random passwords if not set
    if [ -z "${WEBUI_SECRET_KEY:-}" ]; then
        WEBUI_SECRET_KEY=$(openssl rand -hex 32)
        echo "WEBUI_SECRET_KEY=$WEBUI_SECRET_KEY" >> "$PROJECT_ROOT/.env"
        echo -e "${GREEN}[✓]${NC} Generated WEBUI_SECRET_KEY"
    fi

    if [ -z "${ADMIN_PASSWORD:-}" ]; then
        ADMIN_PASSWORD=$(openssl rand -base64 16)
        echo "ADMIN_PASSWORD=$ADMIN_PASSWORD" >> "$PROJECT_ROOT/.env"
        echo -e "${GREEN}[✓]${NC} Generated ADMIN_PASSWORD"
    fi

    echo -e "${GREEN}[✓]${NC} Secrets generation complete"
}

# Function to deploy Oracle services
deploy_oracle() {
    print_section "DEPLOYING ORACLE NODE"

    echo -e "${YELLOW}[→]${NC} Copying files to Oracle node..."

    # Create deployment directory on Oracle
    ssh -o StrictHostKeyChecking=no "root@$ORACLE_IP" "mkdir -p /opt/ai-swarm"

    # Copy necessary files
    scp -r "$PROJECT_ROOT/deploy" "root@$ORACLE_IP:/opt/ai-swarm/"
    scp -r "$PROJECT_ROOT/config" "root@$ORACLE_IP:/opt/ai-swarm/"
    scp -r "$PROJECT_ROOT/scripts" "root@$ORACLE_IP:/opt/ai-swarm/"
    scp "$PROJECT_ROOT/.env" "root@$ORACLE_IP:/opt/ai-swarm/"

    echo -e "${YELLOW}[→]${NC} Starting Oracle services..."

    # Deploy services
    ssh "root@$ORACLE_IP" "cd /opt/ai-swarm && docker-compose -f deploy/01-deploy-oracle.yml up -d"

    # Wait for services to be ready
    echo -e "${YELLOW}[→]${NC} Waiting for Oracle services to start..."
    sleep 30

    # Health check
    if curl -f "http://$ORACLE_IP:3000/health" &>/dev/null; then
        echo -e "${GREEN}[✓]${NC} Open WebUI is running"
    else
        echo -e "${RED}[✗]${NC} Open WebUI failed to start"
        return 1
    fi

    if curl -f "http://$ORACLE_IP:4000/health" &>/dev/null; then
        echo -e "${GREEN}[✓]${NC} LiteLLM Gateway is running"
    else
        echo -e "${RED}[✗]${NC} LiteLLM Gateway failed to start"
        return 1
    fi

    # Vault health check
    if curl -f "http://$ORACLE_IP:8200/v1/sys/health?standbyok=true" &>/dev/null; then
        echo -e "${GREEN}[✓]${NC} Vault is running"
    else
        echo -e "${RED}[✗]${NC} Vault failed to start"
        return 1
    fi

    # Rotate API keys using Vault
    echo -e "${YELLOW}[→]${NC} Rotating API keys with Vault..."
    ssh "root@$ORACLE_IP" "cd /opt/ai-swarm && VAULT_ADDR=http://localhost:8200 VAULT_TOKEN=${VAULT_DEV_ROOT_TOKEN} python scripts/key_rotation.py all"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[✓]${NC} API key rotation complete"
    else
        echo -e "${YELLOW}[!]${NC} API key rotation warning - check manually"
    fi

    echo -e "${GREEN}[✓]${NC} Oracle node deployment complete"
}

# Function to deploy Starlord services
deploy_starlord() {
    print_section "DEPLOYING STARLORD NODE"

    echo -e "${YELLOW}[→]${NC} Checking existing Qdrant..."

    # Verify Qdrant is running
    if curl -f "http://localhost:6333/health" &>/dev/null; then
        echo -e "${GREEN}[✓]${NC} Qdrant is already running on port 6333"
    else
        echo -e "${YELLOW}[!]${NC} WARNING: Qdrant not detected on port 6333"
        echo -e "${YELLOW}[!]${NC} Please ensure Qdrant is running before continuing"
    fi

    echo -e "${YELLOW}[→]${NC} Starting Starlord services..."

    # Deploy services locally
    cd "$PROJECT_ROOT"
    docker-compose -f deploy/02-deploy-starlord.yml up -d

    # Wait for services
    echo -e "${YELLOW}[→]${NC} Waiting for vLLM to initialize..."
    sleep 60

    # Health check
    if curl -f "http://localhost:8000/health" &>/dev/null; then
        echo -e "${GREEN}[✓]${NC} vLLM server is running"
    else
        echo -e "${RED}[✗]${NC} vLLM server failed to start"
        return 1
    fi

    echo -e "${GREEN}[✓]${NC} Starlord node deployment complete"
}

# Function to deploy Thanos services
deploy_thanos() {
    print_section "DEPLOYING THANOS NODE"

    echo -e "${YELLOW}[→]${NC} Copying files to Thanos node..."

    # Create deployment directory
    ssh -o StrictHostKeyChecking=no "root@$THANOS_IP" "mkdir -p /opt/ai-swarm"

    # Copy necessary files
    scp -r "$PROJECT_ROOT/deploy" "root@$THANOS_IP:/opt/ai-swarm/"
    scp -r "$PROJECT_ROOT/config" "root@$THANOS_IP:/opt/ai-swarm/"
    scp -r "$PROJECT_ROOT/services" "root@$THANOS_IP:/opt/ai-swarm/" 2>/dev/null || true
    scp "$PROJECT_ROOT/.env" "root@$THANOS_IP:/opt/ai-swarm/"

    echo -e "${YELLOW}[→]${NC} Starting Thanos services..."

    # Deploy services
    ssh "root@$THANOS_IP" "cd /opt/ai-swarm && docker-compose -f deploy/03-deploy-thanos.yml up -d"

    # Wait for services
    echo -e "${YELLOW}[→]${NC} Waiting for Thanos services to start..."
    sleep 45

    # Health check
    if curl -f "http://$THANOS_IP:8080/" &>/dev/null; then
        echo -e "${GREEN}[✓]${NC} SillyTavern is running"
    else
        echo -e "${YELLOW}[!]${NC} SillyTavern may still be starting up"
    fi

    if curl -f "http://$THANOS_IP:8001/" &>/dev/null; then
        echo -e "${GREEN}[✓]${NC} GPT Researcher is running"
    else
        echo -e "${YELLOW}[!]${NC} GPT Researcher may still be starting up"
    fi

    echo -e "${GREEN}[✓]${NC} Thanos node deployment complete"
}

# Function to configure LiteLLM routing
configure_litellm() {
    print_section "CONFIGURING MODEL ROUTING"

    cat > "$PROJECT_ROOT/config/litellm.yaml" << EOF
model_list:
  - model_name: llama-3.2-dark-champion
    litellm_params:
      model: openai/meta-llama/Llama-2-13b-chat-hf
      api_base: http://$STARLORD_IP:8000/v1
      api_key: dummy

  - model_name: hermes-3-8b
    litellm_params:
      model: openai/hermes-3-8b
      api_base: http://$STARLORD_IP:8000/v1
      api_key: dummy

  - model_name: deepseek-v3
    litellm_params:
      model: deepseek/deepseek-v3.1
      api_key: \${OPENROUTER_API_KEY}

  - model_name: gemini-flash
    litellm_params:
      model: gemini/gemini-1.5-flash
      api_key: \${GEMINI_API_KEY}

router_settings:
  routing_strategy: least_busy
  num_retries: 3
  timeout: 600
  allowed_fails: 3

general_settings:
  master_key: \${LITELLM_MASTER_KEY}
  database_url: postgresql://litellm:\${POSTGRES_PASSWORD}@postgres:5432/litellm
  cache: true
  cache_params:
    type: redis
    host: redis
    port: 6379
EOF

    # Copy config to Oracle
    scp "$PROJECT_ROOT/config/litellm.yaml" "root@$ORACLE_IP:/opt/ai-swarm/config/"

    # Restart LiteLLM to apply config
    ssh "root@$ORACLE_IP" "docker restart oracle-litellm"

    echo -e "${GREEN}[✓]${NC} Model routing configured"
}

# Function to run post-deployment tests
run_tests() {
    print_section "RUNNING POST-DEPLOYMENT TESTS"

    echo -e "${YELLOW}[→]${NC} Testing service connectivity..."

    # Test Oracle services
    if curl -f "http://$ORACLE_IP:3000/health" &>/dev/null; then
        echo -e "${GREEN}[✓]${NC} Oracle: Open WebUI accessible"
    else
        echo -e "${RED}[✗]${NC} Oracle: Open WebUI not accessible"
    fi

    if curl -f "http://$ORACLE_IP:4000/health" &>/dev/null; then
        echo -e "${GREEN}[✓]${NC} Oracle: LiteLLM Gateway accessible"
    else
        echo -e "${RED}[✗]${NC} Oracle: LiteLLM Gateway not accessible"
    fi

    # Test Starlord services
    if curl -f "http://$STARLORD_IP:8000/v1/models" &>/dev/null; then
        echo -e "${GREEN}[✓]${NC} Starlord: vLLM API accessible"
    else
        echo -e "${RED}[✗]${NC} Starlord: vLLM API not accessible"
    fi

    if curl -f "http://$STARLORD_IP:6333/health" &>/dev/null; then
        echo -e "${GREEN}[✓]${NC} Starlord: Qdrant accessible"
    else
        echo -e "${RED}[✗]${NC} Starlord: Qdrant not accessible"
    fi

    # Test Thanos services
    if curl -f "http://$THANOS_IP:8080/" &>/dev/null; then
        echo -e "${GREEN}[✓]${NC} Thanos: SillyTavern accessible"
    else
        echo -e "${YELLOW}[!]${NC} Thanos: SillyTavern may still be starting"
    fi

    # Test end-to-end inference
    echo -e "${YELLOW}[→]${NC} Testing end-to-end inference..."

    response=$(curl -s -X POST "http://$ORACLE_IP:4000/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
        -d '{
            "model": "hermes-3-8b",
            "messages": [{"role": "user", "content": "Say hello"}],
            "max_tokens": 10
        }' 2>/dev/null || echo "failed")

    if [[ "$response" == *"content"* ]]; then
        echo -e "${GREEN}[✓]${NC} End-to-end inference test passed"
    else
        echo -e "${YELLOW}[!]${NC} End-to-end inference test incomplete (models may still be loading)"
    fi
}

# Function to setup automated backups
backup_setup() {
    print_section "SETTING UP AUTOMATED BACKUPS"
    
    # Oracle - Postgres backup
    ssh "root@$ORACLE_IP" "
        mkdir -p /backup/postgres
        echo '0 2 * * * docker exec oracle-postgres pg_dump -U litellm litellm > /backup/postgres/\$(date +\%Y\%m\%d).sql' | crontab -
    "
    echo -e "${GREEN}[✓]${NC} Postgres backup cron set on Oracle"
    
    # Starlord - Qdrant snapshot
    ssh "starlord@$STARLORD_IP" "
        mkdir -p /backup/qdrant
        echo '0 2 * * * curl -X PUT \"http://localhost:6333/collections/gemini-embeddings/snapshot\" -o /backup/qdrant/\$(date +\%Y\%m\%d).snapshot' | crontab -
    "
    echo -e "${GREEN}[✓]${NC} Qdrant backup cron set on Starlord"
    
    echo -e "${GREEN}[✓]${NC} Automated backups configured (daily at 2AM)"
}

# Function to display access information
display_access_info() {
    print_section "DEPLOYMENT COMPLETE"

    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    ACCESS INFORMATION                         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Primary Interfaces:${NC}"
    echo -e "  Open WebUI:      ${BLUE}http://$ORACLE_IP:3000${NC}"
    echo -e "  SillyTavern:     ${BLUE}http://$THANOS_IP:8080${NC}"
    echo -e "  GPT Researcher:  ${BLUE}http://$THANOS_IP:8001${NC}"
    echo ""
    echo -e "${CYAN}API Endpoints:${NC}"
    echo -e "  LiteLLM Gateway: ${BLUE}http://$ORACLE_IP:4000/v1${NC}"
    echo -e "  vLLM Direct:     ${BLUE}http://$STARLORD_IP:8000/v1${NC}"
    echo -e "  Qdrant Vector:   ${BLUE}http://$STARLORD_IP:6333${NC}"
    echo ""
    echo -e "${CYAN}Monitoring:${NC}"
    echo -e "  Starlord GPU:    ${BLUE}http://$STARLORD_IP:9091/metrics${NC}"
    echo -e "  Thanos Thermal:  ${BLUE}http://$THANOS_IP:9092/metrics${NC}"
    echo ""
    echo -e "${YELLOW}Default Credentials:${NC}"
    echo -e "  Admin Password:  Check .env file for ADMIN_PASSWORD"
    echo -e "  API Key:         Check .env file for LITELLM_MASTER_KEY"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
}

# Main deployment flow
main() {
    echo -e "${YELLOW}Deployment Mode: $DEPLOYMENT_MODE${NC}"
    echo ""

    # Pre-flight checks
    check_prerequisites
    validate_infrastructure

    # Network setup
    setup_network

    # Security setup
    if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
        generate_secrets
    fi

    # Deploy services in order
    deploy_oracle
    deploy_starlord
    deploy_thanos

    # Configure routing
    configure_litellm

    # Run tests
    run_tests

    # Setup backups
    backup_setup

    # Display access info
    display_access_info

    echo -e "\n${GREEN}[✓] AI-SWARM-MIAMI-2025 deployment completed successfully!${NC}"
    echo -e "${CYAN}[i] To monitor logs: docker-compose logs -f [service-name]${NC}"
    echo -e "${CYAN}[i] To stop services: docker-compose down${NC}"
}

# Run main deployment
main "$@"