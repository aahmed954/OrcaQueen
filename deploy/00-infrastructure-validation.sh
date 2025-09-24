#!/bin/bash
# AI-SWARM-MIAMI-2025: Infrastructure Validation Script
# Validates all three nodes before deployment

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        AI-SWARM-MIAMI-2025 Infrastructure Validator        ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Node configuration
ORACLE_IP="100.96.197.84"
STARLORD_IP="100.72.73.3"
THANOS_IP="100.122.12.54"

# Validation results
VALIDATION_PASSED=true
VALIDATION_REPORT=""

# Function to check node connectivity
check_node_connectivity() {
    local node_name=$1
    local node_ip=$2

    echo -e "${YELLOW}[CHECK]${NC} Testing connectivity to $node_name ($node_ip)..."

    if ping -c 2 -W 5 $node_ip > /dev/null 2>&1; then
        echo -e "${GREEN}[✓]${NC} $node_name is reachable"
        return 0
    else
        echo -e "${RED}[✗]${NC} $node_name is unreachable"
        VALIDATION_PASSED=false
        return 1
    fi
}

# Function to validate node hardware
validate_node_hardware() {
    local node_name=$1
    local node_ip=$2
    local expected_ram=$3
    local expected_gpu=$4

    echo -e "${YELLOW}[CHECK]${NC} Validating hardware on $node_name..."

    # SSH command to gather hardware info
    local hw_info=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no $node_ip '
        echo "CPU_CORES=$(nproc)"
        echo "RAM_TOTAL=\"$(free -h | grep Mem | awk "{print \$2}")\""
        echo "RAM_AVAILABLE=\"$(free -h | grep Mem | awk "{print \$7}")\""
        if command -v nvidia-smi &> /dev/null; then
            echo "GPU_NAME=\"$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)\""
            echo "GPU_MEMORY=\"$(nvidia-smi --query-gpu=memory.total --format=csv,noheader | head -n1)\""
        else
            echo "GPU_NAME=none"
            echo "GPU_MEMORY=none"
        fi
        echo "DISK_AVAILABLE=\"$(df -h / | awk "NR==2 {print \$4}")\""
    ' 2>/dev/null || echo "SSH_FAILED=true")

    if [[ $hw_info == *"SSH_FAILED=true"* ]]; then
        echo -e "${RED}[✗]${NC} Failed to SSH to $node_name"
        VALIDATION_PASSED=false
        return 1
    fi

    # Parse hardware info
    eval "$hw_info"

    # Validate RAM
    if [[ -n "$expected_ram" ]]; then
        echo -e "  RAM: $RAM_TOTAL total, $RAM_AVAILABLE available"
    fi

    # Validate GPU
    if [[ "$expected_gpu" != "none" ]]; then
        if [[ "$GPU_NAME" == "none" ]]; then
            echo -e "${RED}[✗]${NC} Expected GPU not found on $node_name"
            VALIDATION_PASSED=false
        else
            echo -e "  GPU: $GPU_NAME with $GPU_MEMORY"
        fi
    fi

    echo -e "  CPU Cores: $CPU_CORES"
    echo -e "  Disk Available: $DISK_AVAILABLE"

    return 0
}

# Function to check Docker installation
check_docker() {
    local node_name=$1
    local node_ip=$2

    echo -e "${YELLOW}[CHECK]${NC} Validating Docker on $node_name..."

    local docker_version=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no $node_ip 'docker --version 2>/dev/null || echo "not_installed"' 2>/dev/null)

    if [[ $docker_version == *"not_installed"* ]]; then
        echo -e "${RED}[✗]${NC} Docker not installed on $node_name"
        VALIDATION_PASSED=false
        return 1
    else
        echo -e "${GREEN}[✓]${NC} Docker installed: $docker_version"

        # Check Docker Compose
        local compose_version=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no $node_ip 'docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || echo "not_installed"' 2>/dev/null)
        if [[ $compose_version == *"not_installed"* ]]; then
            echo -e "${YELLOW}[!]${NC} Docker Compose not found on $node_name"
        else
            echo -e "${GREEN}[✓]${NC} Docker Compose available"
        fi
    fi

    return 0
}

# Function to check existing services
check_existing_services() {
    local node_name=$1
    local node_ip=$2
    local expected_service=$3
    local service_port=$4

    echo -e "${YELLOW}[CHECK]${NC} Checking $expected_service on $node_name..."

    # Check if port is open
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no $node_ip "netstat -tuln | grep -q ':$service_port '" 2>/dev/null; then
        echo -e "${GREEN}[✓]${NC} $expected_service is running on port $service_port"

        # Special check for Qdrant
        if [[ "$expected_service" == "Qdrant" ]]; then
            # Simplified health check: curl -f succeeds on HTTP 200-299
            if curl -f -s --max-time 5 http://$node_ip:$service_port/health > /dev/null 2>&1; then
                echo -e "${GREEN}[✓]${NC} Qdrant health check passed (HTTP 200 OK)"
            else
                echo -e "${YELLOW}[!]${NC} Qdrant health check failed"
                VALIDATION_PASSED=false
            fi
        fi
    else
        echo -e "${YELLOW}[!]${NC} $expected_service not detected on port $service_port"
    fi
}

# Function to validate network mesh
validate_network_mesh() {
    echo -e "\n${BLUE}═══ Network Mesh Validation ═══${NC}\n"

    # Test inter-node connectivity
    echo -e "${YELLOW}[CHECK]${NC} Testing Tailscale mesh connectivity..."

    # From current node to others
    for node in "Oracle:$ORACLE_IP" "Thanos:$THANOS_IP"; do
        IFS=':' read -r name ip <<< "$node"
        if [[ "$(hostname)" != "$(echo $name | tr '[:upper:]' '[:lower:]')" ]]; then
            if ping -c 1 -W 2 $ip > /dev/null 2>&1; then
                echo -e "${GREEN}[✓]${NC} Can reach $name from $(hostname)"
            else
                echo -e "${RED}[✗]${NC} Cannot reach $name from $(hostname)"
                VALIDATION_PASSED=false
            fi
        fi
    done
}

# Main validation flow
main() {
    echo -e "\n${BLUE}═══ Phase 1: Node Connectivity ═══${NC}\n"

    check_node_connectivity "Oracle ARM" "$ORACLE_IP"
    check_node_connectivity "Starlord" "$STARLORD_IP"
    check_node_connectivity "Thanos" "$THANOS_IP"

    echo -e "\n${BLUE}═══ Phase 2: Hardware Validation ═══${NC}\n"

    # Oracle doesn't have GPU
    validate_node_hardware "Oracle" "$ORACLE_IP" "22GB" "none"

    # Starlord has RTX 4090
    validate_node_hardware "Starlord" "$STARLORD_IP" "20GB" "RTX 4090"

    # Thanos has RTX 3080
    validate_node_hardware "Thanos" "$THANOS_IP" "61GB" "RTX 3080"

    echo -e "\n${BLUE}═══ Phase 3: Docker Validation ═══${NC}\n"

    check_docker "Oracle" "$ORACLE_IP"
    check_docker "Starlord" "$STARLORD_IP"
    check_docker "Thanos" "$THANOS_IP"

    echo -e "\n${BLUE}═══ Phase 4: Existing Services ═══${NC}\n"

    # Check Qdrant on Starlord
    check_existing_services "Starlord" "$STARLORD_IP" "Qdrant" "6333"

    # Validate network mesh
    validate_network_mesh

    echo -e "\n${BLUE}═══ Validation Summary ═══${NC}\n"

    if [ "$VALIDATION_PASSED" = true ]; then
        echo -e "${GREEN}[✓] All validation checks passed!${NC}"
        echo -e "${GREEN}[✓] Infrastructure is ready for deployment${NC}"
        exit 0
    else
        echo -e "${RED}[✗] Some validation checks failed${NC}"
        echo -e "${RED}[✗] Please fix issues before deployment${NC}"
        exit 1
    fi
}

# Run main validation
main