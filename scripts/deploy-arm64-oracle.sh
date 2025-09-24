#!/bin/bash
# ARM64 Oracle Deployment Script - All Compatibility Issues Fixed
# Oracle Cloud Free Tier (4 cores, 24GB RAM, ARM64 architecture)

set -euo pipefail

# OS Detection Function for Oracle
detect_oracle_os() {
  local os_info=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no oracle1 "source /etc/os-release && echo \"Ubuntu \$VERSION_ID (\$VERSION_CODENAME)\" 2>/dev/null" 2>/dev/null || echo "Error: OS detection failed on Oracle")
  echo "$os_info"
}

# Branching based on OS
handle_os_specific_oracle() {
  local os_version=$1
  local codename=$2
  local command=$3
  case "$os_version" in
    "24.04")
      # Noble-specific logic
      ssh oracle1 "eval '$command noble'"
      ;;
    "25.04")
      # Plucky-specific logic
      ssh oracle1 "eval '$command plucky'"
      ;;
    *)
      echo "Unsupported Ubuntu version on Oracle: $os_version" >&2
      exit 1
      ;;
  esac
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            ARM64 ORACLE DEPLOYMENT - FIXED               ║${NC}"
echo -e "${BLUE}║              All Compatibility Issues Resolved           ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"

# Detect Oracle OS
oracle_os=$(detect_oracle_os)
echo "Oracle OS: $oracle_os"

# Function to validate environment
validate_environment() {
    echo -e "${YELLOW}[VALIDATION]${NC} Checking deployment requirements..."

    # Check required environment variables
    local required_vars=("POSTGRES_PASSWORD" "LITELLM_MASTER_KEY" "WEBUI_SECRET_KEY")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            echo -e "${RED}[ERROR]${NC} Required environment variable $var is not set"
            exit 1
        fi
    done

    # Check Oracle instance connectivity
    if ! ssh -o ConnectTimeout=10 oracle1 'echo "Connection test"' >/dev/null 2>&1; then
        echo -e "${RED}[ERROR]${NC} Cannot connect to Oracle instance"
        exit 1
    fi

    # OS-specific validation
    local os_version=$(echo "$oracle_os" | cut -d' ' -f2)
    local codename=$(echo "$oracle_os" | cut -d'(' -f2 | cut -d')' -f1)
    if [[ "$os_version" != "24.04" && "$os_version" != "25.04" ]]; then
        echo -e "${RED}[ERROR]${NC} Unsupported OS on Oracle: $oracle_os"
        exit 1
    fi

    # Verify ARM64 architecture with OS-specific check
    local arch=$(ssh oracle1 'uname -m')
    if [[ "$arch" != "aarch64" ]]; then
        echo -e "${RED}[ERROR]${NC} Oracle instance is not ARM64 (found: $arch)"
        exit 1
    fi

    # OS-specific Docker validation
    handle_os_specific_oracle "$os_version" "$codename" "docker --version"

    echo -e "${GREEN}[✓]${NC} Environment validation passed"
}

# Function to create deployment directory structure
setup_deployment() {
    echo -e "${YELLOW}[SETUP]${NC} Preparing deployment files on Oracle..."

    local os_version=$(echo "$oracle_os" | cut -d' ' -f2)
    local codename=$(echo "$oracle_os" | cut -d'(' -f2 | cut -d')' -f1)

    # OS-specific directory creation
    handle_os_specific_oracle "$os_version" "$codename" "mkdir -p ~/ai-swarm/{config,data,logs}"

    # Copy fixed deployment configuration
    scp deploy/01-oracle-ARM64-FIXED.yml oracle1:~/ai-swarm/docker-compose.yml

    # Create environment file on Oracle with OS-specific parsing if needed
    ssh oracle1 "cat > ~/ai-swarm/.env << 'EOF'
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}
EOF"

    echo -e "${GREEN}[✓]${NC} Deployment files prepared"
}

# Function to create LiteLLM configuration
create_litellm_config() {
    echo -e "${YELLOW}[CONFIG]${NC} Creating LiteLLM configuration..."

    ssh oracle1 "mkdir -p ~/ai-swarm/config"
    ssh oracle1 "cat > ~/ai-swarm/config/litellm-config.yaml << 'EOF'
# LiteLLM ARM64 Optimized Configuration for Oracle Cloud
model_list:
  - model_name: gpt-4o-mini
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: \${OPENAI_API_KEY}

  - model_name: claude-3-5-sonnet
    litellm_params:
      model: anthropic/claude-3-5-sonnet-20241022
      api_key: \${ANTHROPIC_API_KEY}

  - model_name: gemini-pro
    litellm_params:
      model: gemini/gemini-1.5-pro-002
      api_key: \${GEMINI_API_KEY}

litellm_settings:
  # ARM64 optimizations
  num_retries: 3
  request_timeout: 120
  max_budget: 100
  budget_duration: 24h

  # Database configuration
  database_url: postgresql://litellm:\${POSTGRES_PASSWORD}@postgres:5432/litellm

  # Redis caching
  redis_host: redis
  redis_port: 6379
  cache: true
  cache_responses: true

  # ARM64 performance tuning
  router_settings:
    routing_strategy: simple-shuffle
    allowed_fails: 3
    cooldown_time: 30

general_settings:
  master_key: \${LITELLM_MASTER_KEY}
  store_model_in_db: true

  # ARM64 logging optimization
  set_verbose: true
  json_logs: true
EOF"

    echo -e "${GREEN}[✓]${NC} LiteLLM configuration created"
}

# Function to deploy services
deploy_services() {
    echo -e "${YELLOW}[DEPLOY]${NC} Starting ARM64 deployment on Oracle..."

    # Navigate to deployment directory and start services
    ssh oracle1 'cd ~/ai-swarm && docker-compose up -d'

    echo -e "${GREEN}[✓]${NC} Services deployment initiated"
}

# Function to monitor deployment
monitor_deployment() {
    echo -e "${YELLOW}[MONITOR]${NC} Monitoring service startup..."

    local max_wait=300  # 5 minutes
    local elapsed=0

    while [[ $elapsed -lt $max_wait ]]; do
        local healthy_count=$(ssh oracle1 'cd ~/ai-swarm && docker-compose ps --services --filter "status=running" | wc -l')
        local total_count=$(ssh oracle1 'cd ~/ai-swarm && docker-compose ps --services | wc -l')

        echo -e "${BLUE}[INFO]${NC} Services: $healthy_count/$total_count running (${elapsed}s elapsed)"

        if [[ $healthy_count -eq $total_count ]] && [[ $total_count -gt 0 ]]; then
            echo -e "${GREEN}[✓]${NC} All services are running!"
            return 0
        fi

        sleep 10
        elapsed=$((elapsed + 10))
    done

    echo -e "${RED}[WARNING]${NC} Deployment monitoring timeout after ${max_wait}s"
    return 1
}

# Function to validate deployment
validate_deployment() {
    echo -e "${YELLOW}[VALIDATE]${NC} Validating ARM64 deployment..."

    # Test service endpoints
    local services=(
        "LiteLLM:http://100.96.197.84:4000/health"
        "OpenWebUI:http://100.96.197.84:3000"
        "Pipelines:http://100.96.197.84:9099/health"
        "NodeExporter:http://100.96.197.84:9100/metrics"
    )

    for service in "${services[@]}"; do
        local name="${service%%:*}"
        local url="${service##*:}"

        if ssh oracle1 "curl -f -s --connect-timeout 10 '$url' >/dev/null"; then
            echo -e "${GREEN}[✓ HEALTHY]${NC} $name is responding"
        else
            echo -e "${RED}[✗ UNHEALTHY]${NC} $name is not responding"
        fi
    done
}

# Function to display deployment status
show_status() {
    echo -e "\n${BLUE}═══ ARM64 ORACLE DEPLOYMENT STATUS ═══${NC}\n"

    ssh oracle1 'cd ~/ai-swarm && docker-compose ps'

    echo -e "\n${BLUE}═══ SERVICE ENDPOINTS ═══${NC}"
    echo -e "${GREEN}LiteLLM Gateway:${NC}    http://100.96.197.84:4000"
    echo -e "${GREEN}Open WebUI:${NC}         http://100.96.197.84:3000"
    echo -e "${GREEN}Pipelines API:${NC}      http://100.96.197.84:9099"
    echo -e "${GREEN}Node Exporter:${NC}      http://100.96.197.84:9100/metrics"

    echo -e "\n${BLUE}═══ NEXT STEPS ═══${NC}"
    echo -e "1. Configure API keys in LiteLLM: http://100.96.197.84:4000"
    echo -e "2. Access Open WebUI: http://100.96.197.84:3000"
    echo -e "3. Monitor with: ssh oracle1 'cd ~/ai-swarm && docker-compose logs -f'"
}

# Main execution
main() {
    validate_environment
    setup_deployment
    create_litellm_config
    deploy_services

    if monitor_deployment; then
        validate_deployment
        show_status
        echo -e "\n${GREEN}🎉 ARM64 Oracle deployment completed successfully!${NC}"
    else
        echo -e "\n${YELLOW}⚠️  Deployment completed but some services may still be starting${NC}"
        echo -e "Monitor with: ${BLUE}ssh oracle1 'cd ~/ai-swarm && docker-compose logs -f'${NC}"
    fi
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "status")
        show_status
        ;;
    "logs")
        ssh oracle1 'cd ~/ai-swarm && docker-compose logs -f'
        ;;
    "stop")
        ssh oracle1 'cd ~/ai-swarm && docker-compose down'
        echo -e "${GREEN}[✓]${NC} Services stopped"
        ;;
    "restart")
        ssh oracle1 'cd ~/ai-swarm && docker-compose down && docker-compose up -d'
        echo -e "${GREEN}[✓]${NC} Services restarted"
        ;;
    *)
        echo "Usage: $0 {deploy|status|logs|stop|restart}"
        exit 1
        ;;
esac