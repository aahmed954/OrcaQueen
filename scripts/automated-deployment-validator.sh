#!/bin/bash
# AI-SWARM-MIAMI-2025: Automated Deployment Validator
# Validates deployment readiness and runs comprehensive tests

# Configuration
DEPLOYMENT_ROOT="/home/starlord/OrcaQueen"
LOG_FILE="/tmp/deployment_validation_$(date +%Y%m%d_%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

# Test functions
test_infrastructure() {
    log "${BLUE}Testing Infrastructure...${NC}"
    cd "$DEPLOYMENT_ROOT"

    # Run infrastructure validation
    if timeout 120 ./deploy/00-infrastructure-validation.sh >> "$LOG_FILE" 2>&1; then
        log "${GREEN}✅ Infrastructure validation passed${NC}"
        return 0
    else
        log "${RED}❌ Infrastructure validation failed${NC}"
        return 1
    fi
}

test_arm_compatibility() {
    log "${BLUE}Testing ARM64 Compatibility...${NC}"
    cd "$DEPLOYMENT_ROOT"

    # Run ARM compatibility test with timeout
    if timeout 180 ./scripts/test-arm-compatibility.sh >> "$LOG_FILE" 2>&1; then
        log "${GREEN}✅ ARM64 compatibility test passed${NC}"
        return 0
    else
        log "${RED}❌ ARM64 compatibility test failed${NC}"
        return 1
    fi
}

test_secrets_configuration() {
    log "${BLUE}Testing Secrets Configuration...${NC}"

    # Check for required environment files
    if [[ -f ".env.production" ]]; then
        log "${GREEN}✅ Production environment file exists${NC}"

        # Check for critical secrets
        if grep -q "LITELLM_MASTER_KEY=" .env.production; then
            log "${GREEN}✅ LiteLLM master key configured${NC}"
        else
            log "${RED}❌ LiteLLM master key missing${NC}"
            return 1
        fi

        if grep -q "HUGGINGFACE_TOKEN=" .env.production; then
            log "${GREEN}✅ HuggingFace token configured${NC}"
        else
            log "${YELLOW}⚠️  HuggingFace token missing (optional)${NC}"
        fi
    else
        log "${RED}❌ Production environment file missing${NC}"
        return 1
    fi

    return 0
}

test_docker_compose_files() {
    log "${BLUE}Testing Docker Compose Configurations...${NC}"

    local compose_files=(
        "deploy/01-oracle-ARM64-FIXED.yml"
        "deploy/02-starlord-OPTIMIZED.yml"
        "deploy/03-thanos-SECURED.yml"
        "deploy/04-railway-services.yml"
    )

    for file in "${compose_files[@]}"; do
        if [[ -f "$file" ]]; then
            log "Validating $file..."
            if docker-compose -f "$file" config -q >> "$LOG_FILE" 2>&1; then
                log "${GREEN}✅ $file is valid${NC}"
            else
                log "${RED}❌ $file has configuration errors${NC}"
                return 1
            fi
        else
            log "${RED}❌ $file not found${NC}"
            return 1
        fi
    done

    return 0
}

test_network_connectivity() {
    log "${BLUE}Testing Network Connectivity...${NC}"

    local nodes=(
        "100.96.197.84:Oracle"
        "100.72.73.3:Starlord"
        "100.122.12.54:Thanos"
    )

    for node_info in "${nodes[@]}"; do
        IFS=':' read -r ip name <<< "$node_info"
        if ping -c 2 -W 5 "$ip" >> "$LOG_FILE" 2>&1; then
            log "${GREEN}✅ $name ($ip) is reachable${NC}"
        else
            log "${RED}❌ $name ($ip) is unreachable${NC}"
            return 1
        fi
    done

    return 0
}

# Main validation function
main() {
    log "${BLUE}🚀 Starting AI-SWARM-MIAMI-2025 Deployment Validation${NC}"
    log "Log file: $LOG_FILE"
    echo ""

    local tests_passed=0
    local total_tests=0

    # Run all tests
    local test_functions=(
        test_infrastructure
        test_arm_compatibility
        test_secrets_configuration
        test_docker_compose_files
        test_network_connectivity
    )

    for test_func in "${test_functions[@]}"; do
        ((total_tests++))
        echo ""
        if $test_func; then
            ((tests_passed++))
        fi
    done

    echo ""
    log "${BLUE}📊 Validation Summary${NC}"
    log "Tests passed: $tests_passed/$total_tests"

    if [[ $tests_passed -eq $total_tests ]]; then
        log "${GREEN}🎉 All validation tests passed! Ready for deployment.${NC}"
        echo ""
        log "${BLUE}Next steps:${NC}"
        log "1. Review validation log: $LOG_FILE"
        log "2. Run deployment: ./deploy.sh"
        log "3. Monitor deployment progress"
        log "4. Run post-deployment health checks"
        exit 0
    else
        log "${RED}❌ Some validation tests failed. Please review the log: $LOG_FILE${NC}"
        exit 1
    fi
}

# Run main function
main "$@"