#!/bin/bash

# ARM64 Health Check and Validation Script
# Comprehensive monitoring for Oracle Cloud ARM64 deployment
# Version: 2.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="/opt/ai-swarm/logs/health-checks"
COMPOSE_FILE="${PROJECT_DIR}/docker-compose-arm64.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Health check results
declare -A health_results
declare -A health_details
declare -A performance_metrics

# Logging
log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_info() {
    echo -e "${PURPLE}[INFO]${NC} $1"
}

# Initialize logging
mkdir -p "${LOG_DIR}"
exec > >(tee -a "${LOG_DIR}/health-check-$(date +%Y%m%d_%H%M%S).log")
exec 2>&1

# System health checks
check_system_health() {
    log "Checking system health..."
    
    # CPU usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    performance_metrics["cpu_usage"]=$cpu_usage
    
    if (( $(echo "$cpu_usage > 80" | bc -l) )); then
        health_results["system_cpu"]="CRITICAL"
        health_details["system_cpu"]="High CPU usage: ${cpu_usage}%"
    elif (( $(echo "$cpu_usage > 60" | bc -l) )); then
        health_results["system_cpu"]="WARNING"
        health_details["system_cpu"]="Moderate CPU usage: ${cpu_usage}%"
    else
        health_results["system_cpu"]="HEALTHY"
        health_details["system_cpu"]="CPU usage: ${cpu_usage}%"
    fi
    
    # Memory usage
    memory_info=$(free -m)
    total_mem=$(echo "$memory_info" | awk 'NR==2{print $2}')
    used_mem=$(echo "$memory_info" | awk 'NR==2{print $3}')
    mem_percent=$(( used_mem * 100 / total_mem ))
    
    performance_metrics["memory_usage_percent"]=$mem_percent
    performance_metrics["memory_used_mb"]=$used_mem
    performance_metrics["memory_total_mb"]=$total_mem
    
    if [[ $mem_percent -gt 90 ]]; then
        health_results["system_memory"]="CRITICAL"
        health_details["system_memory"]="High memory usage: ${mem_percent}% (${used_mem}MB/${total_mem}MB)"
    elif [[ $mem_percent -gt 75 ]]; then
        health_results["system_memory"]="WARNING"
        health_details["system_memory"]="Moderate memory usage: ${mem_percent}% (${used_mem}MB/${total_mem}MB)"
    else
        health_results["system_memory"]="HEALTHY"
        health_details["system_memory"]="Memory usage: ${mem_percent}% (${used_mem}MB/${total_mem}MB)"
    fi
    
    # Disk usage
    disk_usage=$(df -h /opt | awk 'NR==2 {print $5}' | sed 's/%//')
    available_gb=$(df -h /opt | awk 'NR==2 {print $4}')
    
    performance_metrics["disk_usage_percent"]=$disk_usage
    performance_metrics["disk_available"]=$available_gb
    
    if [[ $disk_usage -gt 90 ]]; then
        health_results["system_disk"]="CRITICAL"
        health_details["system_disk"]="High disk usage: ${disk_usage}% (${available_gb} available)"
    elif [[ $disk_usage -gt 80 ]]; then
        health_results["system_disk"]="WARNING"
        health_details["system_disk"]="Moderate disk usage: ${disk_usage}% (${available_gb} available)"
    else
        health_results["system_disk"]="HEALTHY"
        health_details["system_disk"]="Disk usage: ${disk_usage}% (${available_gb} available)"
    fi
    
    # Load average
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | xargs)
    num_cores=$(nproc)
    load_percent=$(echo "scale=2; $load_avg * 100 / $num_cores" | bc)
    
    performance_metrics["load_average"]=$load_avg
    performance_metrics["load_percent"]=$load_percent
    
    if (( $(echo "$load_percent > 80" | bc -l) )); then
        health_results["system_load"]="CRITICAL"
        health_details["system_load"]="High load average: $load_avg (${load_percent}% of ${num_cores} cores)"
    elif (( $(echo "$load_percent > 60" | bc -l) )); then
        health_results["system_load"]="WARNING"
        health_details["system_load"]="Moderate load average: $load_avg (${load_percent}% of ${num_cores} cores)"
    else
        health_results["system_load"]="HEALTHY"
        health_details["system_load"]="Load average: $load_avg (${load_percent}% of ${num_cores} cores)"
    fi
}

# Docker health checks
check_docker_health() {
    log "Checking Docker health..."
    
    # Docker daemon
    if ! docker info &>/dev/null; then
        health_results["docker_daemon"]="CRITICAL"
        health_details["docker_daemon"]="Docker daemon not accessible"
        return 1
    else
        health_results["docker_daemon"]="HEALTHY"
        health_details["docker_daemon"]="Docker daemon running"
    fi
    
    # Docker system resources
    docker_info=$(docker system df --format "table {{.Type}}\t{{.Total}}\t{{.Active}}\t{{.Size}}\t{{.Reclaimable}}")
    
    # Check for excessive docker resource usage
    images_count=$(docker images -q | wc -l)
    containers_count=$(docker ps -a -q | wc -l)
    volumes_count=$(docker volume ls -q | wc -l)
    
    performance_metrics["docker_images"]=$images_count
    performance_metrics["docker_containers"]=$containers_count
    performance_metrics["docker_volumes"]=$volumes_count
    
    if [[ $images_count -gt 100 ]] || [[ $containers_count -gt 50 ]]; then
        health_results["docker_resources"]="WARNING"
        health_details["docker_resources"]="High resource count: ${images_count} images, ${containers_count} containers, ${volumes_count} volumes"
    else
        health_results["docker_resources"]="HEALTHY"
        health_details["docker_resources"]="Docker resources: ${images_count} images, ${containers_count} containers, ${volumes_count} volumes"
    fi
}

# Container health checks
check_container_health() {
    log "Checking container health..."
    
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        health_results["containers"]="CRITICAL"
        health_details["containers"]="Docker compose file not found: $COMPOSE_FILE"
        return 1
    fi
    
    # Get all services from compose file
    services=$(docker-compose -f "$COMPOSE_FILE" config --services)
    
    healthy_count=0
    unhealthy_count=0
    total_count=0
    
    for service in $services; do
        total_count=$((total_count + 1))
        
        # Check if container is running
        if docker-compose -f "$COMPOSE_FILE" ps "$service" | grep -q "Up"; then
            # Check health status
            container_name=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service")
            if [[ -n "$container_name" ]]; then
                health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "no-healthcheck")
                
                case "$health_status" in
                    "healthy")
                        health_results["container_$service"]="HEALTHY"
                        health_details["container_$service"]="Container running and healthy"
                        healthy_count=$((healthy_count + 1))
                        ;;
                    "unhealthy")
                        health_results["container_$service"]="CRITICAL"
                        health_details["container_$service"]="Container running but unhealthy"
                        unhealthy_count=$((unhealthy_count + 1))
                        ;;
                    "starting")
                        health_results["container_$service"]="WARNING"
                        health_details["container_$service"]="Container starting"
                        ;;
                    "no-healthcheck")
                        health_results["container_$service"]="HEALTHY"
                        health_details["container_$service"]="Container running (no health check configured)"
                        healthy_count=$((healthy_count + 1))
                        ;;
                    *)
                        health_results["container_$service"]="WARNING"
                        health_details["container_$service"]="Unknown health status: $health_status"
                        ;;
                esac
            else
                health_results["container_$service"]="CRITICAL"
                health_details["container_$service"]="Container not found"
                unhealthy_count=$((unhealthy_count + 1))
            fi
        else
            health_results["container_$service"]="CRITICAL"
            health_details["container_$service"]="Container not running"
            unhealthy_count=$((unhealthy_count + 1))
        fi
    done
    
    performance_metrics["containers_total"]=$total_count
    performance_metrics["containers_healthy"]=$healthy_count
    performance_metrics["containers_unhealthy"]=$unhealthy_count
    
    # Overall container health
    if [[ $unhealthy_count -eq 0 ]]; then
        health_results["containers_overall"]="HEALTHY"
        health_details["containers_overall"]="All containers healthy (${healthy_count}/${total_count})"
    elif [[ $healthy_count -gt $unhealthy_count ]]; then
        health_results["containers_overall"]="WARNING"
        health_details["containers_overall"]="Some containers unhealthy (${healthy_count}/${total_count} healthy)"
    else
        health_results["containers_overall"]="CRITICAL"
        health_details["containers_overall"]="Many containers unhealthy (${healthy_count}/${total_count} healthy)"
    fi
}

# Service endpoint checks
check_service_endpoints() {
    log "Checking service endpoints..."
    
    # Define endpoints to check
    declare -A endpoints=(
        ["open-webui"]="http://localhost:3000"
        ["litellm"]="http://localhost:4000/health"
        ["nginx"]="http://localhost:80/health"
        ["prometheus"]="http://localhost:9090/-/healthy"
        ["grafana"]="http://localhost:3001/api/health"
        ["cpu-inference"]="http://localhost:8001/health"
    )
    
    healthy_endpoints=0
    total_endpoints=${#endpoints[@]}
    
    for service in "${!endpoints[@]}"; do
        endpoint="${endpoints[$service]}"
        
        if curl -f -s --max-time 10 "$endpoint" > /dev/null 2>&1; then
            health_results["endpoint_$service"]="HEALTHY"
            health_details["endpoint_$service"]="Endpoint responding: $endpoint"
            healthy_endpoints=$((healthy_endpoints + 1))
        else
            health_results["endpoint_$service"]="CRITICAL"
            health_details["endpoint_$service"]="Endpoint not responding: $endpoint"
        fi
    done
    
    performance_metrics["endpoints_total"]=$total_endpoints
    performance_metrics["endpoints_healthy"]=$healthy_endpoints
    
    # Overall endpoint health
    if [[ $healthy_endpoints -eq $total_endpoints ]]; then
        health_results["endpoints_overall"]="HEALTHY"
        health_details["endpoints_overall"]="All endpoints responding (${healthy_endpoints}/${total_endpoints})"
    elif [[ $healthy_endpoints -gt $((total_endpoints / 2)) ]]; then
        health_results["endpoints_overall"]="WARNING"
        health_details["endpoints_overall"]="Some endpoints not responding (${healthy_endpoints}/${total_endpoints} healthy)"
    else
        health_results["endpoints_overall"]="CRITICAL"
        health_details["endpoints_overall"]="Many endpoints not responding (${healthy_endpoints}/${total_endpoints} healthy)"
    fi
}

# Database connectivity checks
check_database_connectivity() {
    log "Checking database connectivity..."
    
    # PostgreSQL check
    if docker-compose -f "$COMPOSE_FILE" exec -T postgres pg_isready -U litellm_user -d litellm_db &>/dev/null; then
        health_results["database_postgres"]="HEALTHY"
        health_details["database_postgres"]="PostgreSQL responding"
        
        # Check connection count
        conn_count=$(docker-compose -f "$COMPOSE_FILE" exec -T postgres psql -U litellm_user -d litellm_db -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | xargs || echo "0")
        performance_metrics["postgres_connections"]=$conn_count
        
        if [[ $conn_count -gt 80 ]]; then
            health_results["database_postgres_connections"]="WARNING"
            health_details["database_postgres_connections"]="High connection count: $conn_count"
        else
            health_results["database_postgres_connections"]="HEALTHY"
            health_details["database_postgres_connections"]="Connection count: $conn_count"
        fi
    else
        health_results["database_postgres"]="CRITICAL"
        health_details["database_postgres"]="PostgreSQL not responding"
        health_results["database_postgres_connections"]="CRITICAL"
        health_details["database_postgres_connections"]="Cannot check connections"
    fi
    
    # Redis check
    if docker-compose -f "$COMPOSE_FILE" exec -T redis redis-cli -a "${REDIS_PASSWORD:-default}" ping 2>/dev/null | grep -q "PONG"; then
        health_results["database_redis"]="HEALTHY"
        health_details["database_redis"]="Redis responding"
        
        # Check Redis memory usage
        redis_memory=$(docker-compose -f "$COMPOSE_FILE" exec -T redis redis-cli -a "${REDIS_PASSWORD:-default}" info memory 2>/dev/null | grep used_memory_human | cut -d: -f2 | tr -d '\r' || echo "unknown")
        performance_metrics["redis_memory"]=$redis_memory
        
        health_results["database_redis_memory"]="HEALTHY"
        health_details["database_redis_memory"]="Memory usage: $redis_memory"
    else
        health_results["database_redis"]="CRITICAL"
        health_details["database_redis"]="Redis not responding"
        health_results["database_redis_memory"]="CRITICAL"
        health_details["database_redis_memory"]="Cannot check memory usage"
    fi
}

# Performance metrics collection
collect_performance_metrics() {
    log "Collecting performance metrics..."
    
    # Container resource usage
    if command -v docker &>/dev/null; then
        while IFS= read -r line; do
            if [[ $line =~ ^([^[:space:]]+)[[:space:]]+([0-9.]+)%[[:space:]]+([^[:space:]]+)[[:space:]]+/[[:space:]]+([^[:space:]]+)[[:space:]]+([0-9.]+)% ]]; then
                container="${BASH_REMATCH[1]}"
                cpu="${BASH_REMATCH[2]}"
                memory="${BASH_REMATCH[3]}"
                mem_percent="${BASH_REMATCH[5]}"
                
                performance_metrics["${container}_cpu"]=$cpu
                performance_metrics["${container}_memory"]=$memory
                performance_metrics["${container}_memory_percent"]=$mem_percent
            fi
        done < <(docker stats --no-stream --format "{{.Name}} {{.CPUPerc}} {{.MemUsage}} {{.MemPerc}}" 2>/dev/null || echo "")
    fi
    
    # Network statistics
    if command -v ss &>/dev/null; then
        tcp_connections=$(ss -t -a | wc -l)
        listening_ports=$(ss -t -l | wc -l)
        performance_metrics["network_tcp_connections"]=$tcp_connections
        performance_metrics["network_listening_ports"]=$listening_ports
    fi
    
    # File system statistics
    performance_metrics["filesystem_inodes_used"]=$(df -i /opt | awk 'NR==2 {print $5}' | sed 's/%//')
    performance_metrics["filesystem_inodes_total"]=$(df -i /opt | awk 'NR==2 {print $2}')
}

# Generate recommendations
generate_recommendations() {
    local recommendations=()
    
    # System recommendations
    if [[ "${health_results[system_memory]:-}" == "CRITICAL" ]] || [[ "${health_results[system_memory]:-}" == "WARNING" ]]; then
        recommendations+=("🔧 Consider upgrading to Oracle Cloud Standard shape with more RAM")
        recommendations+=("💾 Implement memory optimization for containers")
        recommendations+=("🗑️ Clean up unused Docker images and containers")
    fi
    
    if [[ "${health_results[system_disk]:-}" == "CRITICAL" ]] || [[ "${health_results[system_disk]:-}" == "WARNING" ]]; then
        recommendations+=("💿 Increase block storage or add additional volumes")
        recommendations+=("🧹 Implement log rotation and cleanup policies")
        recommendations+=("📦 Move large data to Oracle Object Storage")
    fi
    
    if [[ "${health_results[system_cpu]:-}" == "CRITICAL" ]]; then
        recommendations+=("⚡ Scale to more CPU cores or optimize container resource limits")
        recommendations+=("📊 Analyze CPU-intensive processes and optimize")
    fi
    
    # Container recommendations
    if [[ "${health_results[containers_overall]:-}" == "CRITICAL" ]] || [[ "${health_results[containers_overall]:-}" == "WARNING" ]]; then
        recommendations+=("🔄 Restart failed containers: docker-compose -f ${COMPOSE_FILE} restart")
        recommendations+=("📋 Check container logs for specific error messages")
        recommendations+=("🔧 Adjust container resource limits and health check timeouts")
    fi
    
    # Endpoint recommendations
    if [[ "${health_results[endpoints_overall]:-}" == "CRITICAL" ]] || [[ "${health_results[endpoints_overall]:-}" == "WARNING" ]]; then
        recommendations+=("🌐 Check firewall rules for ports 80, 443, 3000, 4000")
        recommendations+=("🔍 Verify Nginx configuration and upstream services")
        recommendations+=("⏰ Increase service startup and health check timeouts")
    fi
    
    # Database recommendations
    if [[ "${health_results[database_postgres]:-}" == "CRITICAL" ]]; then
        recommendations+=("🐘 Check PostgreSQL logs and configuration")
        recommendations+=("💾 Verify PostgreSQL data volume integrity")
        recommendations+=("🔐 Validate PostgreSQL credentials and permissions")
    fi
    
    if [[ "${health_results[database_redis]:-}" == "CRITICAL" ]]; then
        recommendations+=("🔴 Check Redis logs and memory configuration")
        recommendations+=("🔑 Verify Redis password and authentication")
        recommendations+=("💭 Consider Redis persistence configuration")
    fi
    
    # Performance recommendations
    if [[ "${performance_metrics[memory_usage_percent]:-0}" -gt 85 ]]; then
        recommendations+=("🧠 Optimize memory usage: reduce container memory limits")
        recommendations+=("🗂️ Enable swap if not already configured")
    fi
    
    if [[ "${performance_metrics[disk_usage_percent]:-0}" -gt 85 ]]; then
        recommendations+=("🧽 Clean up Docker: docker system prune -a")
        recommendations+=("📁 Archive or compress old log files")
    fi
    
    # Oracle Cloud specific recommendations
    recommendations+=("☁️ Consider Oracle Cloud monitoring for advanced metrics")
    recommendations+=("🔒 Implement Oracle Cloud WAF for web protection")
    recommendations+=("📈 Set up Oracle Cloud autoscaling if needed")
    recommendations+=("💰 Monitor Oracle Cloud free tier limits and usage")
    
    # Output recommendations
    if [[ ${#recommendations[@]} -gt 0 ]]; then
        echo ""
        log_info "RECOMMENDATIONS:"
        for rec in "${recommendations[@]}"; do
            echo "  $rec"
        done
    fi
}

# Display results
display_results() {
    echo ""
    echo "=============================================="
    echo "       ARM64 ORACLE CLOUD HEALTH REPORT"
    echo "=============================================="
    echo "Timestamp: $(date)"
    echo "Architecture: $(uname -m)"
    echo "Hostname: $(hostname)"
    echo "Public IP: $(curl -s --max-time 5 ifconfig.me || echo "Unable to determine")"
    echo ""
    
    # System Health
    echo "=== SYSTEM HEALTH ==="
    for key in system_cpu system_memory system_disk system_load; do
        status="${health_results[$key]:-UNKNOWN}"
        detail="${health_details[$key]:-No details}"
        
        case "$status" in
            "HEALTHY") echo -e "${GREEN}✓${NC} $detail" ;;
            "WARNING") echo -e "${YELLOW}⚠${NC} $detail" ;;
            "CRITICAL") echo -e "${RED}✗${NC} $detail" ;;
            *) echo -e "${BLUE}?${NC} $detail" ;;
        esac
    done
    echo ""
    
    # Docker Health
    echo "=== DOCKER HEALTH ==="
    for key in docker_daemon docker_resources; do
        status="${health_results[$key]:-UNKNOWN}"
        detail="${health_details[$key]:-No details}"
        
        case "$status" in
            "HEALTHY") echo -e "${GREEN}✓${NC} $detail" ;;
            "WARNING") echo -e "${YELLOW}⚠${NC} $detail" ;;
            "CRITICAL") echo -e "${RED}✗${NC} $detail" ;;
            *) echo -e "${BLUE}?${NC} $detail" ;;
        esac
    done
    echo ""
    
    # Container Health
    echo "=== CONTAINER HEALTH ==="
    status="${health_results[containers_overall]:-UNKNOWN}"
    detail="${health_details[containers_overall]:-No details}"
    
    case "$status" in
        "HEALTHY") echo -e "${GREEN}✓${NC} $detail" ;;
        "WARNING") echo -e "${YELLOW}⚠${NC} $detail" ;;
        "CRITICAL") echo -e "${RED}✗${NC} $detail" ;;
        *) echo -e "${BLUE}?${NC} $detail" ;;
    esac
    
    # Individual container details
    for key in "${!health_results[@]}"; do
        if [[ $key =~ ^container_ ]] && [[ $key != "containers_overall" ]]; then
            service="${key#container_}"
            status="${health_results[$key]}"
            detail="${health_details[$key]}"
            
            case "$status" in
                "HEALTHY") echo -e "  ${GREEN}✓${NC} $service: $detail" ;;
                "WARNING") echo -e "  ${YELLOW}⚠${NC} $service: $detail" ;;
                "CRITICAL") echo -e "  ${RED}✗${NC} $service: $detail" ;;
                *) echo -e "  ${BLUE}?${NC} $service: $detail" ;;
            esac
        fi
    done
    echo ""
    
    # Service Endpoints
    echo "=== SERVICE ENDPOINTS ==="
    status="${health_results[endpoints_overall]:-UNKNOWN}"
    detail="${health_details[endpoints_overall]:-No details}"
    
    case "$status" in
        "HEALTHY") echo -e "${GREEN}✓${NC} $detail" ;;
        "WARNING") echo -e "${YELLOW}⚠${NC} $detail" ;;
        "CRITICAL") echo -e "${RED}✗${NC} $detail" ;;
        *) echo -e "${BLUE}?${NC} $detail" ;;
    esac
    
    # Individual endpoint details
    for key in "${!health_results[@]}"; do
        if [[ $key =~ ^endpoint_ ]] && [[ $key != "endpoints_overall" ]]; then
            service="${key#endpoint_}"
            status="${health_results[$key]}"
            detail="${health_details[$key]}"
            
            case "$status" in
                "HEALTHY") echo -e "  ${GREEN}✓${NC} $service: $detail" ;;
                "WARNING") echo -e "  ${YELLOW}⚠${NC} $service: $detail" ;;
                "CRITICAL") echo -e "  ${RED}✗${NC} $service: $detail" ;;
                *) echo -e "  ${BLUE}?${NC} $service: $detail" ;;
            esac
        fi
    done
    echo ""
    
    # Database Health
    echo "=== DATABASE HEALTH ==="
    for key in database_postgres database_redis database_postgres_connections database_redis_memory; do
        if [[ -n "${health_results[$key]:-}" ]]; then
            status="${health_results[$key]}"
            detail="${health_details[$key]}"
            
            case "$status" in
                "HEALTHY") echo -e "${GREEN}✓${NC} $detail" ;;
                "WARNING") echo -e "${YELLOW}⚠${NC} $detail" ;;
                "CRITICAL") echo -e "${RED}✗${NC} $detail" ;;
                *) echo -e "${BLUE}?${NC} $detail" ;;
            esac
        fi
    done
    echo ""
    
    # Performance Metrics Summary
    echo "=== PERFORMANCE METRICS ==="
    echo "CPU Usage: ${performance_metrics[cpu_usage]:-unknown}%"
    echo "Memory Usage: ${performance_metrics[memory_used_mb]:-unknown}MB/${performance_metrics[memory_total_mb]:-unknown}MB (${performance_metrics[memory_usage_percent]:-unknown}%)"
    echo "Disk Usage: ${performance_metrics[disk_usage_percent]:-unknown}% (${performance_metrics[disk_available]:-unknown} available)"
    echo "Load Average: ${performance_metrics[load_average]:-unknown} (${performance_metrics[load_percent]:-unknown}%)"
    echo "Docker Containers: ${performance_metrics[containers_healthy]:-0}/${performance_metrics[containers_total]:-0} healthy"
    echo "Service Endpoints: ${performance_metrics[endpoints_healthy]:-0}/${performance_metrics[endpoints_total]:-0} responding"
    echo ""
    
    # Overall Status
    critical_count=0
    warning_count=0
    
    for status in "${health_results[@]}"; do
        case "$status" in
            "CRITICAL") critical_count=$((critical_count + 1)) ;;
            "WARNING") warning_count=$((warning_count + 1)) ;;
        esac
    done
    
    echo "=== OVERALL STATUS ==="
    if [[ $critical_count -eq 0 ]] && [[ $warning_count -eq 0 ]]; then
        echo -e "${GREEN}🟢 ALL SYSTEMS HEALTHY${NC}"
        echo "Your ARM64 Oracle Cloud deployment is running optimally!"
    elif [[ $critical_count -eq 0 ]]; then
        echo -e "${YELLOW}🟡 MINOR ISSUES DETECTED${NC}"
        echo "Your system is mostly healthy with $warning_count warning(s)."
    else
        echo -e "${RED}🔴 CRITICAL ISSUES DETECTED${NC}"
        echo "Your system has $critical_count critical issue(s) and $warning_count warning(s)."
        echo "Immediate attention required!"
    fi
    
    # Generate recommendations
    generate_recommendations
    
    echo ""
    echo "=============================================="
    echo "Health check completed at $(date)"
    echo "Log saved to: ${LOG_DIR}/health-check-$(date +%Y%m%d_%H%M%S).log"
    echo "=============================================="
}

# Main execution
main() {
    log "Starting comprehensive ARM64 health check..."
    
    check_system_health
    check_docker_health
    check_container_health
    check_service_endpoints
    check_database_connectivity
    collect_performance_metrics
    
    display_results
}

# Handle command line arguments
case "${1:-check}" in
    "check"|"")
        main
        ;;
    "monitor")
        while true; do
            clear
            main
            echo ""
            echo "Press Ctrl+C to stop monitoring..."
            sleep 30
        done
        ;;
    "json")
        main > /dev/null 2>&1
        echo "{"
        echo "  \"timestamp\": \"$(date -Iseconds)\","
        echo "  \"hostname\": \"$(hostname)\","
        echo "  \"architecture\": \"$(uname -m)\","
        echo "  \"health_results\": {"
        first=true
        for key in "${!health_results[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            echo -n "    \"$key\": \"${health_results[$key]}\""
        done
        echo ""
        echo "  },"
        echo "  \"performance_metrics\": {"
        first=true
        for key in "${!performance_metrics[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            echo -n "    \"$key\": \"${performance_metrics[$key]}\""
        done
        echo ""
        echo "  }"
        echo "}"
        ;;
    "help")
        echo "ARM64 Oracle Cloud Health Check Script"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  check    - Run health check once (default)"
        echo "  monitor  - Run health check continuously every 30 seconds"
        echo "  json     - Output results in JSON format"
        echo "  help     - Show this help message"
        echo ""
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run '$0 help' for usage information"
        exit 1
        ;;
esac