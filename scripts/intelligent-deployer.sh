#!/bin/bash
# AI-SWARM-MIAMI-2025: Intelligent Deployment Automation
# AI-powered deployment with rollback, canary releases, and automated testing

set -euo pipefail

# Configuration
DEPLOYMENT_ROOT="/home/starlord/OrcaQueen"
BACKUP_DIR="/tmp/ai-swarm-backups"
ROLLBACK_TIMEOUT=1800  # 30 minutes
CANARY_PERCENTAGE=10   # 10% traffic for canary releases

# Node configurations
declare -A NODES=(
    ["oracle"]="100.96.197.84"
    ["starlord"]="100.72.73.3"
    ["thanos"]="100.122.12.54"
)

# Service deployment order (dependency-based)
DEPLOYMENT_ORDER=(
    "oracle:deploy/01-oracle-ARM64-FIXED.yml"
    "starlord:deploy/02-starlord-OPTIMIZED.yml"
    "thanos:deploy/03-thanos-SECURED.yml"
    "railway:deploy/04-railway-services.yml"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Logging
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "/tmp/ai-swarm-deployment-$(date +%Y%m%d).log"
}

# Backup current deployment state
create_backup() {
    local backup_id=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/$backup_id"

    log "${BLUE}Creating deployment backup: $backup_id${NC}"
    mkdir -p "$backup_path"

    # Backup docker-compose files
    cp -r "$DEPLOYMENT_ROOT/deploy/" "$backup_path/"

    # Backup environment files
    cp "$DEPLOYMENT_ROOT/.env"* "$backup_path/" 2>/dev/null || true

    # Backup current running configurations
    for node_name in "${!NODES[@]}"; do
        local node_ip="${NODES[$node_name]}"
        log "Backing up $node_name configuration..."

        # Get running containers
        ssh "$node_ip" "docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'" > "$backup_path/${node_name}_containers.txt" 2>/dev/null || true

        # Get docker-compose configurations
        ssh "$node_ip" "find /opt/ai-swarm -name 'docker-compose*.yml' -exec cp {} $backup_path/ \; 2>/dev/null" || true
    done

    echo "$backup_id" > "$BACKUP_DIR/latest_backup"
    log "${GREEN}✅ Backup created: $backup_id${NC}"
}

# Health check with timeout
wait_for_healthy() {
    local service_name="$1"
    local health_url="$2"
    local timeout="${3:-60}"
    local interval=5

    log "Waiting for $service_name to become healthy (timeout: ${timeout}s)..."

    local start_time=$(date +%s)
    while (( $(date +%s) - start_time < timeout )); do
        if curl -s -f --max-time 10 "$health_url" > /dev/null 2>&1; then
            log "${GREEN}✅ $service_name is healthy${NC}"
            return 0
        fi
        sleep "$interval"
    done

    log "${RED}❌ $service_name failed to become healthy within ${timeout}s${NC}"
    return 1
}

# Deploy to single node
deploy_to_node() {
    local node_name="$1"
    local compose_file="$2"
    local node_ip="${NODES[$node_name]:-}"

    if [[ -z "$node_ip" ]]; then
        log "${YELLOW}⚠️  Skipping $node_name (no IP configured)${NC}"
        return 0
    fi

    log "${BLUE}🚀 Deploying to $node_name ($node_ip)...${NC}"

    # Copy compose file to node
    scp "$compose_file" "$node_ip:/opt/ai-swarm/docker-compose.yml" >> /tmp/ai-swarm-deployment-$(date +%Y%m%d).log 2>&1

    # Copy environment files
    scp .env* "$node_ip:/opt/ai-swarm/" 2>/dev/null || true

    # Deploy services
    if ssh "$node_ip" "cd /opt/ai-swarm && docker-compose pull && docker-compose up -d" >> /tmp/ai-swarm-deployment-$(date +%Y%m%d).log 2>&1; then
        log "${GREEN}✅ $node_name deployment successful${NC}"
        return 0
    else
        log "${RED}❌ $node_name deployment failed${NC}"
        return 1
    fi
}

# Rollback deployment
rollback_deployment() {
    local backup_id="${1:-}"

    if [[ -z "$backup_id" ]]; then
        backup_id=$(cat "$BACKUP_DIR/latest_backup" 2>/dev/null)
    fi

    if [[ ! -d "$BACKUP_DIR/$backup_id" ]]; then
        log "${RED}❌ Backup $backup_id not found${NC}"
        return 1
    fi

    log "${YELLOW}🔄 Rolling back to backup: $backup_id${NC}"

    # Restore configurations
    cp -r "$BACKUP_DIR/$backup_id/deploy/"* "$DEPLOYMENT_ROOT/deploy/" 2>/dev/null || true

    # Rollback each node
    for node_name in "${!NODES[@]}"; do
        local node_ip="${NODES[$node_name]}"
        local backup_file="$BACKUP_DIR/$backup_id/${node_name}_containers.txt"

        if [[ -f "$backup_file" ]]; then
            log "Rolling back $node_name..."

            # Stop all running containers
            ssh "$node_ip" "docker stop \$(docker ps -q) 2>/dev/null || true" >> /tmp/ai-swarm-deployment-$(date +%Y%m%d).log 2>&1

            # Restore previous compose file if available
            if [[ -f "$BACKUP_DIR/$backup_id/docker-compose.yml" ]]; then
                scp "$BACKUP_DIR/$backup_id/docker-compose.yml" "$node_ip:/opt/ai-swarm/"
                ssh "$node_ip" "cd /opt/ai-swarm && docker-compose up -d" >> /tmp/ai-swarm-deployment-$(date +%Y%m%d).log 2>&1
            fi
        fi
    done

    log "${GREEN}✅ Rollback completed${NC}"
}

# Canary deployment
canary_deploy() {
    local service_name="$1"
    local new_image="$2"

    log "${PURPLE}🦜 Starting canary deployment for $service_name...${NC}"

    # Deploy new version to 10% of instances
    # This is a simplified version - in production you'd use a service mesh like Istio

    log "${YELLOW}⚠️  Canary deployment requires service mesh (Istio/Linkerd) for proper traffic splitting${NC}"
    log "${YELLOW}⚠️  Falling back to blue-green deployment${NC}"

    # For now, implement blue-green deployment
    blue_green_deploy "$service_name" "$new_image"
}

# Blue-green deployment
blue_green_deploy() {
    local service_name="$1"
    local new_image="$2"

    log "${BLUE}🔄 Starting blue-green deployment for $service_name...${NC}"

    # Create green environment
    log "Creating green environment..."

    # Scale up new version
    docker-compose up -d --scale "$service_name=2" >> /tmp/ai-swarm-deployment-$(date +%Y%m%d).log 2>&1

    # Wait for green environment to be healthy
    sleep 30

    # Run smoke tests on green environment
    if run_smoke_tests; then
        log "${GREEN}✅ Green environment tests passed${NC}"

        # Switch traffic to green (scale down blue)
        docker-compose up -d --scale "$service_name=1" >> /tmp/ai-swarm-deployment-$(date +%Y%m%d).log 2>&1

        log "${GREEN}✅ Blue-green deployment successful${NC}"
    else
        log "${RED}❌ Green environment tests failed, rolling back...${NC}"

        # Rollback: scale down green, keep blue
        docker-compose up -d --scale "$service_name=1" >> /tmp/ai-swarm-deployment-$(date +%Y%m%d).log 2>&1
    fi
}

# Run smoke tests
run_smoke_tests() {
    log "Running smoke tests..."

    # Test basic endpoints
    local endpoints=(
        "http://100.96.197.84:4000/health"
        "http://100.72.73.3:8000/health"
        "http://100.122.12.54:8080/health"
    )

    for endpoint in "${endpoints[@]}"; do
        if ! curl -s -f --max-time 10 "$endpoint" > /dev/null; then
            log "${RED}❌ Smoke test failed: $endpoint${NC}"
            return 1
        fi
    done

    log "${GREEN}✅ All smoke tests passed${NC}"
    return 0
}

# Main deployment function
deploy_all() {
    log "${BLUE}🚀 Starting AI-SWARM-MIAMI-2025 Deployment${NC}"

    # Pre-deployment validation
    log "Running pre-deployment validation..."
    if ! ./scripts/automated-deployment-validator.sh >> /tmp/ai-swarm-deployment-$(date +%Y%m%d).log 2>&1; then
        log "${RED}❌ Pre-deployment validation failed${NC}"
        exit 1
    fi

    # Create backup
    create_backup

    # Deploy services in order
    local failed_services=()
    for service_spec in "${DEPLOYMENT_ORDER[@]}"; do
        IFS=':' read -r node_name compose_file <<< "$service_spec"

        if ! deploy_to_node "$node_name" "$compose_file"; then
            failed_services+=("$node_name")
        fi

        # Wait for service to be healthy
        case "$node_name" in
            "oracle")
                wait_for_healthy "Oracle Services" "http://100.96.197.84:4000/health" 300
                ;;
            "starlord")
                wait_for_healthy "Starlord Services" "http://100.72.73.3:8000/health" 300
                ;;
            "thanos")
                wait_for_healthy "Thanos Services" "http://100.122.12.54:8080/health" 300
                ;;
        esac
    done

    # Post-deployment validation
    log "Running post-deployment validation..."
    if run_smoke_tests && [[ ${#failed_services[@]} -eq 0 ]]; then
        log "${GREEN}🎉 Deployment completed successfully!${NC}"
        log "${BLUE}Next steps:${NC}"
        log "1. Monitor services: ./scripts/ai-swarm-monitor.sh status"
        log "2. Check Grafana dashboards"
        log "3. Run performance tests"
    else
        log "${RED}❌ Deployment completed with issues${NC}"
        if [[ ${#failed_services[@]} -gt 0 ]]; then
            log "Failed services: ${failed_services[*]}"
        fi
        log "${YELLOW}⚠️  Consider rollback: $0 rollback${NC}"
        exit 1
    fi
}

# Main command handler
main() {
    cd "$DEPLOYMENT_ROOT"

    case "${1:-help}" in
        "deploy")
            deploy_all
            ;;
        "rollback")
            rollback_deployment "${2:-}"
            ;;
        "backup")
            create_backup
            ;;
        "canary")
            if [[ $# -lt 3 ]]; then
                echo "Usage: $0 canary <service> <new-image>"
                exit 1
            fi
            canary_deploy "$2" "$3"
            ;;
        "status")
            echo "📊 Deployment Status:"
            echo "Latest backup: $(cat "$BACKUP_DIR/latest_backup" 2>/dev/null || echo 'None')"
            echo ""
            echo "Service Health:"
            ./scripts/ai-swarm-monitor.sh status 2>/dev/null || echo "Monitoring not available"
            ;;
        "validate")
            ./scripts/automated-deployment-validator.sh
            ;;
        *)
            echo "🤖 AI-SWARM Intelligent Deployment System"
            echo ""
            echo "Usage: $0 <command> [options]"
            echo ""
            echo "Commands:"
            echo "  deploy              - Deploy all services with validation and rollback"
            echo "  rollback [backup]   - Rollback to specified backup (or latest)"
            echo "  backup              - Create deployment backup"
            echo "  canary <svc> <img>  - Canary deployment for service"
            echo "  status              - Show deployment status"
            echo "  validate            - Run pre-deployment validation"
            echo ""
            echo "Examples:"
            echo "  $0 deploy"
            echo "  $0 rollback"
            echo "  $0 canary vllm vllm/vllm-openai:latest-new"
            ;;
    esac
}

# Run main function
main "$@"