#!/bin/bash
# AI-SWARM-MIAMI-2025: Intelligent Monitoring & Alerting System
# Real-time monitoring with AI-powered anomaly detection

set -euo pipefail

# Configuration
MONITORING_INTERVAL=300  # 5 minutes
ALERT_EMAIL="admin@ai-swarm-miami-2025.com"
LOG_FILE="/var/log/ai-swarm-monitor.log"
METRICS_DB="/tmp/ai-swarm-metrics.db"

# Service endpoints
declare -A ENDPOINTS=(
    ["litellm_gateway"]="http://100.96.197.84:4000/health"
    ["litellm_health"]="http://100.96.197.84:4001/health"
    ["openwebui"]="http://100.96.197.84:3000/health"
    ["vllm_starlord"]="http://100.72.73.3:8000/health"
    ["vllm_thanos"]="http://100.122.12.54:8000/health"
    ["sillytavern"]="http://100.122.12.54:8080/health"
    ["qdrant"]="http://100.72.73.3:6333/health"
    ["postgres_exporter"]="http://100.96.197.84:9187/metrics"
    ["redis_exporter_oracle"]="http://100.96.197.84:9121/metrics"
    ["prometheus"]="http://railway-host:9090/-/healthy"
    ["grafana"]="http://railway-host:3001/api/health"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Initialize metrics database
init_metrics_db() {
    if [[ ! -f "$METRICS_DB" ]]; then
        sqlite3 "$METRICS_DB" << 'EOF'
CREATE TABLE service_health (
    timestamp INTEGER,
    service_name TEXT,
    status TEXT,
    response_time REAL,
    error_message TEXT
);

CREATE TABLE system_metrics (
    timestamp INTEGER,
    node TEXT,
    cpu_usage REAL,
    memory_usage REAL,
    disk_usage REAL,
    network_io REAL
);

CREATE TABLE alerts (
    timestamp INTEGER,
    alert_type TEXT,
    severity TEXT,
    message TEXT,
    resolved INTEGER DEFAULT 0
);
EOF
    fi
}

# Health check function
check_service_health() {
    local service_name="$1"
    local url="$2"
    local timestamp=$(date +%s)

    local start_time=$(date +%s.%3N)
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo "000")
    local end_time=$(date +%s.%3N)

    local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")

    local status="healthy"
    local error_msg=""

    if [[ "$http_code" != "200" ]]; then
        status="unhealthy"
        error_msg="HTTP $http_code"
    fi

    # Store in database
    sqlite3 "$METRICS_DB" << EOF
INSERT INTO service_health (timestamp, service_name, status, response_time, error_message)
VALUES ($timestamp, '$service_name', '$status', $response_time, '$error_msg');
EOF

    echo "$service_name:$status:$response_time:$error_msg"
}

# System metrics collection
collect_system_metrics() {
    local node="$1"
    local timestamp=$(date +%s)

    # CPU usage (percentage)
    local cpu_usage=$(ssh "$node" "top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{print 100 - $1}'" 2>/dev/null || echo "0")

    # Memory usage (percentage)
    local memory_usage=$(ssh "$node" "free | grep Mem | awk '{printf \"%.2f\", \$3/\$2 * 100.0}'" 2>/dev/null || echo "0")

    # Disk usage (percentage)
    local disk_usage=$(ssh "$node" "df / | tail -1 | awk '{print \$5}' | sed 's/%//'" 2>/dev/null || echo "0")

    # Network I/O (bytes)
    local network_io=$(ssh "$node" "cat /proc/net/dev | grep eth0 | awk '{print \$2+\$10}'" 2>/dev/null || echo "0")

    # Store in database
    sqlite3 "$METRICS_DB" << EOF
INSERT INTO system_metrics (timestamp, node, cpu_usage, memory_usage, disk_usage, network_io)
VALUES ($timestamp, '$node', $cpu_usage, $memory_usage, $disk_usage, $network_io);
EOF
}

# Anomaly detection
detect_anomalies() {
    local service_name="$1"

    # Get recent response times (last 10 measurements)
    local recent_times=$(sqlite3 "$METRICS_DB" << EOF
SELECT response_time FROM service_health
WHERE service_name = '$service_name'
ORDER BY timestamp DESC
LIMIT 10;
EOF
)

    # Calculate average and standard deviation
    local avg=$(echo "$recent_times" | awk '{sum+=$1} END {print sum/NR}')
    local stddev=$(echo "$recent_times" | awk -v avg="$avg" '{sum+=($1-avg)^2} END {print sqrt(sum/NR)}')

    # Get latest measurement
    local latest=$(echo "$recent_times" | head -1)

    # Check for anomalies (3 standard deviations from mean)
    if [[ -n "$avg" && -n "$stddev" && -n "$latest" ]]; then
        local threshold_high=$(echo "$avg + 3 * $stddev" | bc -l 2>/dev/null)
        local threshold_low=$(echo "$avg - 3 * $stddev" | bc -l 2>/dev/null)

        if (( $(echo "$latest > $threshold_high" | bc -l 2>/dev/null) )) || (( $(echo "$latest < $threshold_low" | bc -l 2>/dev/null) )); then
            echo "ANOMALY:$service_name:Response time $latest ms (normal range: $threshold_low - $threshold_high ms)"
            return 0
        fi
    fi

    return 1
}

# Alert function
send_alert() {
    local alert_type="$1"
    local severity="$2"
    local message="$3"
    local timestamp=$(date +%s)

    # Store alert in database
    sqlite3 "$METRICS_DB" << EOF
INSERT INTO alerts (timestamp, alert_type, severity, message)
VALUES ($timestamp, '$alert_type', '$severity', '$message');
EOF

    # Send email alert (if configured)
    if [[ -n "$ALERT_EMAIL" ]]; then
        echo "Subject: [$severity] AI-SWARM Alert: $alert_type

$message

Timestamp: $(date)
System: AI-SWARM-MIAMI-2025

This is an automated alert from the AI-SWARM monitoring system.
" | sendmail "$ALERT_EMAIL" 2>/dev/null || true
    fi

    # Log alert
    echo "$(date) [$severity] $alert_type: $message" >> "$LOG_FILE"
}

# Main monitoring loop
main() {
    echo "🤖 AI-SWARM Intelligent Monitoring System Started"
    echo "Monitoring interval: ${MONITORING_INTERVAL}s"
    echo "Log file: $LOG_FILE"
    echo ""

    init_metrics_db

    while true; do
        echo "$(date): Starting monitoring cycle..."

        # Check service health
        local unhealthy_services=()
        for service in "${!ENDPOINTS[@]}"; do
            local result=$(check_service_health "$service" "${ENDPOINTS[$service]}")
            IFS=':' read -r svc status response_time error <<< "$result"

            if [[ "$status" == "unhealthy" ]]; then
                unhealthy_services+=("$svc")
                send_alert "SERVICE_DOWN" "CRITICAL" "Service $svc is unhealthy: $error"
            fi

            # Check for performance anomalies
            if [[ "$status" == "healthy" ]]; then
                local anomaly=$(detect_anomalies "$svc")
                if [[ -n "$anomaly" ]]; then
                    send_alert "PERFORMANCE_ANOMALY" "WARNING" "$anomaly"
                fi
            fi
        done

        # Collect system metrics
        for node in "100.96.197.84" "100.72.73.3" "100.122.12.54"; do
            collect_system_metrics "$node"
        done

        # Check system resource alerts
        local high_cpu=$(sqlite3 "$METRICS_DB" "SELECT node FROM system_metrics WHERE cpu_usage > 90 ORDER BY timestamp DESC LIMIT 1;" 2>/dev/null)
        if [[ -n "$high_cpu" ]]; then
            send_alert "HIGH_CPU" "WARNING" "High CPU usage detected on node $high_cpu"
        fi

        local high_memory=$(sqlite3 "$METRICS_DB" "SELECT node FROM system_metrics WHERE memory_usage > 90 ORDER BY timestamp DESC LIMIT 1;" 2>/dev/null)
        if [[ -n "$high_memory" ]]; then
            send_alert "HIGH_MEMORY" "WARNING" "High memory usage detected on node $high_memory"
        fi

        local low_disk=$(sqlite3 "$METRICS_DB" "SELECT node FROM system_metrics WHERE disk_usage > 90 ORDER BY timestamp DESC LIMIT 1;" 2>/dev/null)
        if [[ -n "$low_disk" ]]; then
            send_alert "LOW_DISK_SPACE" "CRITICAL" "Low disk space detected on node $low_disk"
        fi

        # Summary
        local total_services=${#ENDPOINTS[@]}
        local unhealthy_count=${#unhealthy_services[@]}
        local healthy_count=$((total_services - unhealthy_count))

        echo "📊 Health Summary: $healthy_count/$total_services services healthy"
        if [[ ${#unhealthy_services[@]} -gt 0 ]]; then
            echo "⚠️  Unhealthy services: ${unhealthy_services[*]}"
        fi

        echo "⏱️  Next check in ${MONITORING_INTERVAL}s..."
        echo ""

        sleep "$MONITORING_INTERVAL"
    done
}

# Handle command line arguments
case "${1:-}" in
    "start")
        main
        ;;
    "status")
        echo "🤖 AI-SWARM Monitoring Status"
        echo "Active alerts:"
        sqlite3 -header -column "$METRICS_DB" "SELECT datetime(timestamp, 'unixepoch'), alert_type, severity, message FROM alerts WHERE resolved = 0 ORDER BY timestamp DESC LIMIT 5;"

        echo ""
        echo "Recent service health:"
        sqlite3 -header -column "$METRICS_DB" "SELECT datetime(timestamp, 'unixepoch'), service_name, status, printf('%.2f', response_time) || 'ms' as response_time FROM service_health ORDER BY timestamp DESC LIMIT 10;"
        ;;
    "alerts")
        echo "📋 All Alerts (last 24h):"
        sqlite3 -header -column "$METRICS_DB" "SELECT datetime(timestamp, 'unixepoch'), alert_type, severity, message FROM alerts WHERE timestamp > strftime('%s', 'now', '-1 day') ORDER BY timestamp DESC;"
        ;;
    *)
        echo "Usage: $0 {start|status|alerts}"
        echo "  start  - Start the monitoring system"
        echo "  status - Show current status and recent metrics"
        echo "  alerts - Show recent alerts"
        exit 1
        ;;
esac