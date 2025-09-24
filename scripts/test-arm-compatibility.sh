#!/bin/bash
# ARM64 Compatibility Testing Script
# Tests all Docker images for ARM64 support before Oracle deployment

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'  
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              ARM64 COMPATIBILITY TESTING                 ║${NC}"
echo -e "${BLUE}║              Oracle Node Deployment Validation           ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Test results tracking
COMPATIBLE_IMAGES=()
INCOMPATIBLE_IMAGES=()
UNKNOWN_IMAGES=()

# Function to test image ARM64 compatibility
test_image_arm64() {
    local image=$1
    local service_name=$2
    
    echo -e "${YELLOW}[TESTING]${NC} $service_name: $image"
    
    # Try to pull ARM64 image
    if docker pull --platform linux/arm64 "$image" >/dev/null 2>&1; then
        echo -e "${GREEN}[✓ COMPATIBLE]${NC} $image supports ARM64"
        COMPATIBLE_IMAGES+=("$service_name:$image")
        
        # Test if image can start (quick test)
        if timeout 30s docker run --platform linux/arm64 --rm "$image" --help >/dev/null 2>&1 || \
           timeout 30s docker run --platform linux/arm64 --rm "$image" -v >/dev/null 2>&1 || \
           timeout 30s docker run --platform linux/arm64 --rm "$image" version >/dev/null 2>&1; then
            echo -e "${GREEN}[✓ STARTABLE]${NC} $image starts successfully on ARM64"
        else
            echo -e "${YELLOW}[⚠ PARTIAL]${NC} $image pulls but may have runtime issues"
        fi
        
        return 0
    else
        echo -e "${RED}[✗ INCOMPATIBLE]${NC} $image does not support ARM64"
        INCOMPATIBLE_IMAGES+=("$service_name:$image")
        return 1
    fi
}

# Function to check Docker buildx support
check_buildx() {
    echo -e "${YELLOW}[CHECK]${NC} Docker buildx multi-platform support..."
    
    if docker buildx version >/dev/null 2>&1; then
        echo -e "${GREEN}[✓]${NC} Docker buildx available"
        
        # Check for ARM64 builder
        if docker buildx inspect default | grep -q "linux/arm64"; then
            echo -e "${GREEN}[✓]${NC} ARM64 builder available"
        else
            echo -e "${YELLOW}[!]${NC} Setting up ARM64 builder..."
            docker buildx create --name arm64-builder --platform linux/arm64 >/dev/null 2>&1 || true
            docker buildx use arm64-builder >/dev/null 2>&1 || true
        fi
    else
        echo -e "${RED}[✗]${NC} Docker buildx not available - ARM64 testing limited"
    fi
}

# Function to test critical Oracle services
test_oracle_services() {
    echo -e "\n${BLUE}═══ Testing Oracle Node Services ═══${NC}\n"
    
    # Core infrastructure (should be compatible)
    test_image_arm64 "postgres:15-alpine" "PostgreSQL"
    test_image_arm64 "redis:7-alpine" "Redis"
    test_image_arm64 "prom/node-exporter:latest" "Node Exporter"
    
    # Critical services (compatibility unknown)
    test_image_arm64 "ghcr.io/berriai/litellm:main-latest" "LiteLLM Gateway"
    test_image_arm64 "ghcr.io/open-webui/open-webui:main" "Open WebUI"
    test_image_arm64 "ghcr.io/open-webui/pipelines:main" "Pipelines"
    
    # Alternative CPU-only images
    test_image_arm64 "python:3.11-slim" "Python Base (CPU Server)"
    test_image_arm64 "node:18-alpine" "Node.js Base (WebUI Alt)"
}

# Function to test GPU-dependent services  
test_gpu_alternatives() {
    echo -e "\n${BLUE}═══ Testing GPU Alternative Services ═══${NC}\n"
    
    echo -e "${YELLOW}[INFO]${NC} vLLM requires CUDA - testing CPU alternatives..."
    
    # CPU-only inference alternatives
    test_image_arm64 "python:3.11-slim" "CPU Inference Base"
    test_image_arm64 "tensorflow/tensorflow:latest" "TensorFlow CPU"
    test_image_arm64 "pytorch/pytorch:latest" "PyTorch CPU"
    
    echo -e "${YELLOW}[NOTE]${NC} GPU services will run on Starlord/Thanos nodes only"
}

# Function to test Railway cloud services
test_railway_services() {
    echo -e "\n${BLUE}═══ Testing Railway Cloud Services ═══${NC}\n"
    
    test_image_arm64 "grafana/grafana:latest" "Grafana"
    test_image_arm64 "redis:7-alpine" "Railway Redis"
    test_image_arm64 "python:3.11-slim" "Research Worker Base"
}

# Function to suggest fixes
suggest_fixes() {
    echo -e "\n${BLUE}═══ ARM64 Compatibility Report ═══${NC}\n"
    
    echo -e "${GREEN}✅ COMPATIBLE SERVICES (${#COMPATIBLE_IMAGES[@]}):"
    for img in "${COMPATIBLE_IMAGES[@]}"; do
        echo -e "  ${GREEN}✓${NC} $img"
    done
    
    if [ ${#INCOMPATIBLE_IMAGES[@]} -gt 0 ]; then
        echo -e "\n${RED}❌ INCOMPATIBLE SERVICES (${#INCOMPATIBLE_IMAGES[@]}):"
        for img in "${INCOMPATIBLE_IMAGES[@]}"; do
            echo -e "  ${RED}✗${NC} $img"
        done
        
        echo -e "\n${YELLOW}🔧 SUGGESTED FIXES:${NC}"
        
        for img in "${INCOMPATIBLE_IMAGES[@]}"; do
            service=$(echo "$img" | cut -d: -f1)
            image=$(echo "$img" | cut -d: -f2-)
            
            case "$service" in
                "LiteLLM Gateway")
                    echo -e "  • LiteLLM: Build custom ARM64 image or find alternative API gateway"
                    echo -e "    Alternative: nginx with API routing or Traefik"
                    ;;
                "Open WebUI")
                    echo -e "  • Open WebUI: Build from source on ARM64 or use alternative"
                    echo -e "    Alternative: Custom React/Next.js interface"
                    ;;
                "Pipelines")
                    echo -e "  • Pipelines: Disable if not critical or build ARM64 version"
                    ;;
            esac
        done
    fi
    
    echo -e "\n${BLUE}📋 DEPLOYMENT RECOMMENDATIONS:${NC}"
    
    if [ ${#INCOMPATIBLE_IMAGES[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✅ Oracle ARM64 deployment should work!${NC}"
        echo -e "  ${GREEN}✅ All critical services are ARM64 compatible${NC}"
    elif [ ${#INCOMPATIBLE_IMAGES[@]} -le 2 ]; then
        echo -e "  ${YELLOW}⚠️  Minor compatibility issues found${NC}"
        echo -e "  ${YELLOW}⚠️  Consider alternatives for incompatible services${NC}"
    else
        echo -e "  ${RED}❌ Major compatibility issues found${NC}"
        echo -e "  ${RED}❌ Oracle deployment not recommended without fixes${NC}"
    fi
}

# Function to generate ARM64 Docker Compose
generate_arm64_compose() {
    echo -e "\n${YELLOW}[GENERATING]${NC} ARM64-compatible Docker Compose..."
    
    cat > arm64-deployment-ready.yml << 'EOF'
# ARM64 DEPLOYMENT READY - AI SWARM ORACLE NODE
version: '3.8'

services:
  # VERIFIED ARM64 COMPATIBLE SERVICES
  postgres:
    image: postgres:15-alpine
    platform: linux/arm64
    container_name: oracle-postgres-arm64
    restart: always
    environment:
      POSTGRES_DB: litellm
      POSTGRES_USER: litellm
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - aiswarm

  redis:
    image: redis:7-alpine  
    platform: linux/arm64
    container_name: oracle-redis-arm64
    restart: always
    volumes:
      - redis_data:/data
    networks:
      - aiswarm

  # CPU-ONLY INFERENCE (ARM64 COMPATIBLE)
  cpu-inference:
    build:
      context: ../scripts
      dockerfile_inline: |
        FROM python:3.11-slim
        WORKDIR /app
        COPY cpu_inference_server.py .
        RUN pip install flask transformers torch
        EXPOSE 8000
        CMD ["python", "cpu_inference_server.py"]
    platform: linux/arm64
    container_name: oracle-inference-arm64
    restart: always
    ports:
      - "8000:8000"
    environment:
      - MODEL_NAME=microsoft/DialoGPT-small
      - DEVICE=cpu
    networks:
      - aiswarm

  # MONITORING (ARM64 COMPATIBLE)
  monitoring:
    image: prom/node-exporter:latest
    platform: linux/arm64
    container_name: oracle-monitor-arm64
    restart: always
    ports:
      - "9100:9100"
    networks:
      - aiswarm

volumes:
  postgres_data:
  redis_data:

networks:
  aiswarm:
    driver: bridge
EOF

    echo -e "${GREEN}[✓]${NC} Generated arm64-deployment-ready.yml"
}

# Main execution
main() {
    echo -e "Starting ARM64 compatibility testing...\n"
    
    # Check Docker setup
    check_buildx
    
    # Test services
    test_oracle_services
    test_gpu_alternatives  
    test_railway_services
    
    # Generate report
    suggest_fixes
    
    # Generate ARM64-ready compose file
    generate_arm64_compose
    
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Testing complete! Check arm64-deployment-ready.yml for deployment${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
}

# Run tests
main "$@"