#!/bin/bash
# LiteLLM Gateway Deployment Script for Oracle ARM64
# Optimized for Oracle Cloud Free Tier (4 ARM64 cores, 24GB RAM)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
ORACLE_HOST="${ORACLE_HOST:-100.96.197.84}"
ORACLE_USER="${ORACLE_USER:-ubuntu}"
DEPLOY_DIR="/home/${ORACLE_USER}/litellm-gateway"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_banner() {
    echo -e "${PURPLE}"
    echo "═══════════════════════════════════════════════════════════════"
    echo "           LiteLLM Gateway - Oracle ARM64 Deployment"
    echo "                  Optimized for Free Tier"
    echo "═══════════════════════════════════════════════════════════════"
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check SSH access
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${ORACLE_USER}@${ORACLE_HOST}" "echo 'SSH OK'" &>/dev/null; then
        log_error "Cannot connect to Oracle instance at ${ORACLE_HOST}"
        exit 1
    fi
    log_success "SSH connection OK"

    # Check Docker on Oracle
    if ! ssh "${ORACLE_USER}@${ORACLE_HOST}" "docker --version" &>/dev/null; then
        log_error "Docker not installed on Oracle instance"
        exit 1
    fi
    log_success "Docker installed on Oracle"

    # Check Docker Compose
    if ! ssh "${ORACLE_USER}@${ORACLE_HOST}" "docker compose version || docker-compose --version" &>/dev/null; then
        log_warning "Docker Compose not found, installing..."
        install_docker_compose
    fi
    log_success "Docker Compose available"

    # Check environment file
    if [ ! -f "${LOCAL_DIR}/deploy/.env" ]; then
        log_warning ".env file not found. Creating from template..."
        cp "${LOCAL_DIR}/deploy/.env.litellm.template" "${LOCAL_DIR}/deploy/.env"
        log_error "Please edit ${LOCAL_DIR}/deploy/.env with your API keys and configuration"
        exit 1
    fi
    log_success "Environment file found"
}

# Install Docker Compose if needed
install_docker_compose() {
    log_info "Installing Docker Compose on Oracle instance..."
    ssh "${ORACLE_USER}@${ORACLE_HOST}" << 'EOF'
        # Install Docker Compose plugin
        sudo apt-get update
        sudo apt-get install -y docker-compose-plugin

        # Verify installation
        docker compose version
EOF
    log_success "Docker Compose installed"
}

# Test ARM64 compatibility
test_arm64_compatibility() {
    log_info "Testing ARM64 compatibility..."

    local images=(
        "postgres:15-alpine"
        "redis:7-alpine"
        "ghcr.io/berriai/litellm:main-latest"
        "haproxy:2.9-alpine"
        "prom/prometheus:latest"
    )

    for image in "${images[@]}"; do
        log_info "Testing ${image}..."
        if ssh "${ORACLE_USER}@${ORACLE_HOST}" "docker pull --platform=linux/arm64 ${image}" &>/dev/null; then
            log_success "${image} - ARM64 compatible"
        else
            log_error "${image} - ARM64 INCOMPATIBLE"
            return 1
        fi
    done

    log_success "All images are ARM64 compatible"
}

# Create deployment directory structure
create_deployment_structure() {
    log_info "Creating deployment structure on Oracle instance..."

    ssh "${ORACLE_USER}@${ORACLE_HOST}" << EOF
        # Create directory structure
        mkdir -p ${DEPLOY_DIR}/{config,data,logs,backups}
        mkdir -p ${DEPLOY_DIR}/data/{postgres,redis,prometheus}
        mkdir -p ${DEPLOY_DIR}/logs/litellm

        # Set permissions
        chmod -R 755 ${DEPLOY_DIR}
EOF

    log_success "Deployment structure created"
}

# Copy configuration files
copy_configuration() {
    log_info "Copying configuration files..."

    # Create tar archive of necessary files
    tar -czf /tmp/litellm-config.tar.gz \
        -C "${LOCAL_DIR}" \
        deploy/litellm-oracle-arm64-optimized.yml \
        deploy/.env \
        config/litellm-config.yaml \
        config/postgresql-arm64.conf \
        config/haproxy-arm64.cfg \
        config/prometheus-arm64.yml

    # Copy to Oracle instance
    scp /tmp/litellm-config.tar.gz "${ORACLE_USER}@${ORACLE_HOST}:/tmp/"

    # Extract on Oracle instance
    ssh "${ORACLE_USER}@${ORACLE_HOST}" << EOF
        cd ${DEPLOY_DIR}
        tar -xzf /tmp/litellm-config.tar.gz

        # Move files to correct locations
        mv deploy/litellm-oracle-arm64-optimized.yml docker-compose.yml
        mv deploy/.env .env
        mv config/* config/

        # Clean up
        rm -rf deploy
        rm /tmp/litellm-config.tar.gz
EOF

    # Clean up local temp file
    rm /tmp/litellm-config.tar.gz

    log_success "Configuration files copied"
}

# Optimize Oracle system settings
optimize_oracle_system() {
    log_info "Optimizing Oracle system settings for ARM64..."

    ssh "${ORACLE_USER}@${ORACLE_HOST}" << 'EOF'
        # System optimizations for ARM64
        sudo bash -c 'cat >> /etc/sysctl.conf << EOL

# LiteLLM Gateway ARM64 Optimizations
net.core.somaxconn = 1024
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 8096
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3

# Memory optimizations
vm.overcommit_memory = 1
vm.swappiness = 10

# File descriptor limits
fs.file-max = 2097152
fs.nr_open = 2097152
EOL'

        # Apply sysctl settings
        sudo sysctl -p

        # Docker daemon optimizations for ARM64
        sudo bash -c 'cat > /etc/docker/daemon.json << EOL
{
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "10"
    },
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ],
    "max-concurrent-downloads": 10,
    "max-concurrent-uploads": 10,
    "debug": false,
    "hosts": ["unix:///var/run/docker.sock"],
    "live-restore": true,
    "default-ulimits": {
        "nofile": {
            "Hard": 65536,
            "Soft": 65536
        }
    }
}
EOL'

        # Restart Docker to apply changes
        sudo systemctl restart docker
EOF

    log_success "System optimizations applied"
}

# Deploy LiteLLM Gateway
deploy_litellm() {
    log_info "Deploying LiteLLM Gateway..."

    ssh "${ORACLE_USER}@${ORACLE_HOST}" << EOF
        cd ${DEPLOY_DIR}

        # Pull images
        docker compose pull

        # Start services
        docker compose up -d

        # Wait for services to be healthy
        echo "Waiting for services to start..."
        sleep 10

        # Check service status
        docker compose ps
EOF

    log_success "LiteLLM Gateway deployed"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."

    # Check if services are running
    ssh "${ORACLE_USER}@${ORACLE_HOST}" "cd ${DEPLOY_DIR} && docker compose ps --format json" | \
    while IFS= read -r line; do
        if [[ $(echo "$line" | jq -r '.State') != "running" ]]; then
            log_error "Service $(echo "$line" | jq -r '.Name') is not running"
            return 1
        fi
    done

    # Test endpoints
    log_info "Testing endpoints..."

    # Test LiteLLM health
    if curl -sf "http://${ORACLE_HOST}:4000/health" > /dev/null; then
        log_success "LiteLLM health check passed"
    else
        log_error "LiteLLM health check failed"
        return 1
    fi

    # Test HAProxy stats
    if curl -sf "http://${ORACLE_HOST}:8404/stats" > /dev/null; then
        log_success "HAProxy stats available"
    else
        log_warning "HAProxy stats not available (check authentication)"
    fi

    # Test Prometheus
    if curl -sf "http://${ORACLE_HOST}:9090/-/healthy" > /dev/null; then
        log_success "Prometheus healthy"
    else
        log_warning "Prometheus not healthy"
    fi

    log_success "Deployment verified successfully"
}

# Performance test
performance_test() {
    log_info "Running performance tests..."

    # Test response time
    local response_time=$(curl -o /dev/null -s -w '%{time_total}' "http://${ORACLE_HOST}:4000/health")
    log_info "Health endpoint response time: ${response_time}s"

    # Test concurrent requests
    log_info "Testing concurrent requests..."
    ab -n 100 -c 10 "http://${ORACLE_HOST}:4000/health" 2>/dev/null | grep -E "Requests per second|Time per request"

    log_success "Performance tests completed"
}

# Show deployment info
show_deployment_info() {
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                    Deployment Information${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${GREEN}LiteLLM Gateway:${NC}   http://${ORACLE_HOST}:4000"
    echo -e "${GREEN}HAProxy:${NC}          http://${ORACLE_HOST}:8080"
    echo -e "${GREEN}HAProxy Stats:${NC}    http://${ORACLE_HOST}:8404/stats"
    echo -e "${GREEN}Prometheus:${NC}       http://${ORACLE_HOST}:9090"
    echo
    echo -e "${YELLOW}API Documentation:${NC} http://${ORACLE_HOST}:4000/docs"
    echo -e "${YELLOW}Health Check:${NC}     http://${ORACLE_HOST}:4000/health"
    echo -e "${YELLOW}Metrics:${NC}          http://${ORACLE_HOST}:4000/metrics"
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${GREEN}To view logs:${NC}"
    echo "  ssh ${ORACLE_USER}@${ORACLE_HOST} 'cd ${DEPLOY_DIR} && docker compose logs -f'"
    echo
    echo -e "${GREEN}To stop services:${NC}"
    echo "  ssh ${ORACLE_USER}@${ORACLE_HOST} 'cd ${DEPLOY_DIR} && docker compose down'"
    echo
    echo -e "${GREEN}To restart services:${NC}"
    echo "  ssh ${ORACLE_USER}@${ORACLE_HOST} 'cd ${DEPLOY_DIR} && docker compose restart'"
    echo
}

# Main deployment flow
main() {
    print_banner

    # Parse arguments
    case "${1:-deploy}" in
        deploy)
            check_prerequisites
            test_arm64_compatibility
            create_deployment_structure
            copy_configuration
            optimize_oracle_system
            deploy_litellm
            verify_deployment
            performance_test
            show_deployment_info
            log_success "Deployment completed successfully!"
            ;;
        test)
            test_arm64_compatibility
            verify_deployment
            performance_test
            ;;
        stop)
            ssh "${ORACLE_USER}@${ORACLE_HOST}" "cd ${DEPLOY_DIR} && docker compose down"
            log_success "Services stopped"
            ;;
        restart)
            ssh "${ORACLE_USER}@${ORACLE_HOST}" "cd ${DEPLOY_DIR} && docker compose restart"
            log_success "Services restarted"
            ;;
        logs)
            ssh "${ORACLE_USER}@${ORACLE_HOST}" "cd ${DEPLOY_DIR} && docker compose logs -f"
            ;;
        status)
            ssh "${ORACLE_USER}@${ORACLE_HOST}" "cd ${DEPLOY_DIR} && docker compose ps"
            ;;
        *)
            echo "Usage: $0 {deploy|test|stop|restart|logs|status}"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"