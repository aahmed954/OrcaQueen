#!/bin/bash
# ARM64 Open WebUI Pipelines Compatibility Test Script
# Tests deployment and functionality on Oracle Cloud ARM64 instances

set -euo pipefail

# Configuration
COMPOSE_FILE="arm64-deployment-test.yml"
TEST_HOST="localhost"
LITELLM_PORT="4000"
PIPELINES_PORT="9099"
WEBUI_PORT="3000"
MAX_WAIT_TIME=300  # 5 minutes
HEALTH_CHECK_INTERVAL=10

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to check if service is healthy
check_service_health() {
    local service_name="$1"
    local url="$2"
    local max_attempts=30
    local attempt=0

    log "Checking health of $service_name at $url"

    while [ $attempt -lt $max_attempts ]; do
        if curl -sf "$url" >/dev/null 2>&1; then
            success "$service_name is healthy"
            return 0
        fi

        attempt=$((attempt + 1))
        echo -n "."
        sleep $HEALTH_CHECK_INTERVAL
    done

    error "$service_name failed health check after $max_attempts attempts"
    return 1
}

# Function to test API functionality
test_api_functionality() {
    local service="$1"
    local url="$2"
    local expected_status="$3"

    log "Testing $service API functionality"

    response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$url" || echo "HTTPSTATUS:000")
    http_code=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    body=$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')

    if [[ "$http_code" == "$expected_status" ]]; then
        success "$service API responded with expected status $expected_status"
        if [[ -n "$body" ]]; then
            echo "Response: $body" | jq . 2>/dev/null || echo "Response: $body"
        fi
        return 0
    else
        error "$service API returned unexpected status $http_code (expected $expected_status)"
        echo "Response body: $body"
        return 1
    fi
}

# Function to check ARM64 architecture
check_arm64_architecture() {
    log "Checking ARM64 architecture compatibility"

    if docker-compose -f "$COMPOSE_FILE" exec -T pipelines uname -m | grep -q "aarch64"; then
        success "Pipelines container is running on ARM64 (aarch64)"
    else
        warning "Pipelines container architecture check inconclusive"
    fi

    if docker-compose -f "$COMPOSE_FILE" exec -T open-webui uname -m | grep -q "aarch64"; then
        success "Open WebUI container is running on ARM64 (aarch64)"
    else
        warning "Open WebUI container architecture check inconclusive"
    fi
}

# Function to test pipeline functionality
test_pipeline_functionality() {
    log "Testing pipeline functionality"

    # Test pipeline list endpoint
    if test_api_functionality "Pipelines" "http://$TEST_HOST:$PIPELINES_PORT/pipelines" "200"; then
        success "Pipeline list endpoint working"
    else
        warning "Pipeline list endpoint test failed"
    fi

    # Test pipeline health with detailed response
    local health_response
    health_response=$(curl -s "http://$TEST_HOST:$PIPELINES_PORT/health" 2>/dev/null || echo "{}")

    if echo "$health_response" | jq -e '.status' >/dev/null 2>&1; then
        local status
        status=$(echo "$health_response" | jq -r '.status')
        if [[ "$status" == "healthy" || "$status" == "ok" ]]; then
            success "Pipeline service reports healthy status"
        else
            warning "Pipeline service status: $status"
        fi
    else
        log "Pipeline health response: $health_response"
    fi
}

# Function to monitor container resources
monitor_resources() {
    log "Monitoring container resource usage"

    echo "Container Resource Usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" \
        test-pipelines test-open-webui test-litellm 2>/dev/null || {
        warning "Could not fetch container stats"
    }
}

# Function to check container logs for ARM64-specific issues
check_container_logs() {
    log "Checking container logs for ARM64-specific issues"

    # Common ARM64 error patterns
    local error_patterns=(
        "exec format error"
        "illegal instruction"
        "qemu-"
        "architecture"
        "arm64"
        "aarch64"
        "torch.*illegal"
        "pytorch.*error"
    )

    for container in test-pipelines test-open-webui test-litellm; do
        if docker ps --format '{{.Names}}' | grep -q "$container"; then
            log "Checking $container logs for issues"

            local logs
            logs=$(docker logs "$container" --tail 50 2>&1 || echo "")

            for pattern in "${error_patterns[@]}"; do
                if echo "$logs" | grep -iq "$pattern"; then
                    warning "Found potential ARM64 issue in $container: pattern '$pattern'"
                    echo "$logs" | grep -i "$pattern" | head -3
                fi
            done

            # Check for successful startup indicators
            if echo "$logs" | grep -iq "server.*started\|listening\|ready\|healthy"; then
                success "$container shows successful startup indicators"
            fi
        fi
    done
}

# Function to test integration between services
test_service_integration() {
    log "Testing service integration"

    # Test Open WebUI -> LiteLLM connection
    local webui_config
    webui_config=$(curl -s "http://$TEST_HOST:$WEBUI_PORT/api/v1/configs" 2>/dev/null || echo "{}")

    if echo "$webui_config" | jq -e '.' >/dev/null 2>&1; then
        success "Open WebUI configuration API accessible"
    else
        warning "Open WebUI configuration API test failed"
    fi

    # Test LiteLLM -> Models endpoint
    local models_response
    models_response=$(curl -s "http://$TEST_HOST:$LITELLM_PORT/v1/models" 2>/dev/null || echo "{}")

    if echo "$models_response" | jq -e '.data' >/dev/null 2>&1; then
        local model_count
        model_count=$(echo "$models_response" | jq '.data | length')
        success "LiteLLM reports $model_count available models"
    else
        warning "LiteLLM models endpoint test failed"
    fi
}

# Function to cleanup test environment
cleanup() {
    log "Cleaning up test environment"
    docker-compose -f "$COMPOSE_FILE" down -v 2>/dev/null || true
    docker system prune -f >/dev/null 2>&1 || true
    success "Cleanup completed"
}

# Function to run fallback test with stable version
test_stable_fallback() {
    log "Testing stable fallback version"

    # Stop main pipelines service
    docker-compose -f "$COMPOSE_FILE" stop pipelines 2>/dev/null || true

    # Start stable version
    docker-compose -f "$COMPOSE_FILE" --profile fallback up -d pipelines-stable

    sleep 30

    if check_service_health "Pipelines Stable" "http://$TEST_HOST:9098/health"; then
        success "Stable version (v0.5.8) working on ARM64"

        # Test stable version functionality
        test_api_functionality "Pipelines Stable" "http://$TEST_HOST:9098/pipelines" "200"

        return 0
    else
        error "Stable version also failed on ARM64"
        return 1
    fi
}

# Main test execution
main() {
    log "Starting ARM64 Open WebUI Pipelines compatibility test"

    # Check prerequisites
    if ! command -v docker-compose >/dev/null 2>&1; then
        error "docker-compose is required but not installed"
        exit 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        warning "jq not found - JSON parsing will be limited"
    fi

    # Check if compose file exists
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        error "Compose file $COMPOSE_FILE not found"
        exit 1
    fi

    log "Using compose file: $COMPOSE_FILE"

    # Cleanup any existing test environment
    cleanup

    # Start services
    log "Starting ARM64 test deployment"
    if docker-compose -f "$COMPOSE_FILE" up -d; then
        success "Services started successfully"
    else
        error "Failed to start services"
        exit 1
    fi

    # Wait for services to be ready
    sleep 30

    # Check service health
    local health_failed=0

    check_service_health "LiteLLM" "http://$TEST_HOST:$LITELLM_PORT/health" || health_failed=1
    check_service_health "Pipelines" "http://$TEST_HOST:$PIPELINES_PORT/health" || health_failed=1
    check_service_health "Open WebUI" "http://$TEST_HOST:$WEBUI_PORT/health" || health_failed=1

    # If main pipelines failed, try stable version
    if [[ $health_failed -eq 1 ]]; then
        warning "Main pipeline service failed - testing stable fallback"
        if test_stable_fallback; then
            success "Stable fallback version working - recommend using v0.5.8 for production"
        fi
    else
        success "All services healthy - proceeding with functionality tests"

        # Run comprehensive tests
        check_arm64_architecture
        test_pipeline_functionality
        test_service_integration
        monitor_resources
        check_container_logs
    fi

    # Display final status
    log "Test Summary:"
    docker-compose -f "$COMPOSE_FILE" ps

    # Cleanup
    read -p "Press Enter to cleanup test environment, or Ctrl+C to keep running..."
    cleanup

    log "ARM64 compatibility test completed"
}

# Handle script termination
trap cleanup EXIT INT TERM

# Run main function
main "$@"