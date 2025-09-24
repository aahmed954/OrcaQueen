#!/bin/bash

# ARM64 Deployment Rollback Script
# Comprehensive rollback mechanisms for Oracle Cloud ARM64 deployment
# Version: 2.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="/opt/ai-swarm/logs/rollback"
BACKUP_DIR="/opt/ai-swarm/backups"
CONFIG_DIR="/opt/ai-swarm/config"
DATA_DIR="/opt/ai-swarm/data"
COMPOSE_FILE="${PROJECT_DIR}/docker-compose-arm64.yml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Rollback state tracking
ROLLBACK_LOG="${LOG_DIR}/rollback-$(date +%Y%m%d_%H%M%S).log"
ROLLBACK_STATE_FILE="${LOG_DIR}/rollback-state.json"
EMERGENCY_MODE=false

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1" | tee -a "$ROLLBACK_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$ROLLBACK_LOG"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$ROLLBACK_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$ROLLBACK_LOG" >&2
}

log_info() {
    echo -e "${PURPLE}[INFO]${NC} $1" | tee -a "$ROLLBACK_LOG"
}

# Initialize rollback logging
mkdir -p "$LOG_DIR" "$BACKUP_DIR"
exec 2> >(tee -a "$ROLLBACK_LOG" >&2)

# Error handler for script failures
emergency_rollback() {
    local exit_code=$?
    log_error "Emergency rollback triggered with exit code: $exit_code"
    EMERGENCY_MODE=true
    
    # Stop all containers immediately
    log "Stopping all containers..."
    docker-compose -f "$COMPOSE_FILE" down --remove-orphans --timeout 30 2>/dev/null || {
        log_warn "Graceful shutdown failed, forcing container stop..."
        docker stop $(docker ps -q) 2>/dev/null || true
    }
    
    # Find and restore latest backup
    latest_backup=$(find "$BACKUP_DIR" -name "pre-deployment-*" -type d | sort -r | head -n1)
    if [[ -n "$latest_backup" && -d "$latest_backup" ]]; then
        log "Found emergency backup: $latest_backup"
        restore_from_backup "$(basename "$latest_backup")" "emergency"
    else
        log_error "No emergency backup found! Manual intervention required."
    fi
    
    exit $exit_code
}

trap emergency_rollback ERR

# List available backups
list_backups() {
    log "Available backups:"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_warn "Backup directory does not exist: $BACKUP_DIR"
        return 1
    fi
    
    backups=($(find "$BACKUP_DIR" -maxdepth 1 -type d -name "*" | sort -r))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log_warn "No backups found in $BACKUP_DIR"
        return 1
    fi
    
    local index=1
    for backup in "${backups[@]}"; do
        if [[ "$backup" == "$BACKUP_DIR" ]]; then
            continue
        fi
        
        backup_name=$(basename "$backup")
        backup_date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1 || echo "Unknown")
        backup_size=$(du -sh "$backup" 2>/dev/null | cut -f1 || echo "Unknown")
        
        # Determine backup type
        backup_type="manual"
        if [[ "$backup_name" =~ pre-deployment ]]; then
            backup_type="pre-deployment"
        elif [[ "$backup_name" =~ emergency ]]; then
            backup_type="emergency"
        elif [[ "$backup_name" =~ auto ]]; then
            backup_type="automatic"
        fi
        
        printf "  %2d) %-30s | %-20s | %-10s | %s\n" "$index" "$backup_name" "$backup_date" "$backup_size" "$backup_type"
        index=$((index + 1))
    done
    
    return 0
}

# Validate backup integrity
validate_backup() {
    local backup_path="$1"
    local validation_errors=()
    
    log "Validating backup integrity: $(basename "$backup_path")"
    
    # Check if backup directory exists
    if [[ ! -d "$backup_path" ]]; then
        validation_errors+=("Backup directory does not exist")
        return 1
    fi
    
    # Check essential directories
    essential_dirs=("data" "config")
    for dir in "${essential_dirs[@]}"; do
        if [[ ! -d "$backup_path/$dir" ]]; then
            validation_errors+=("Missing essential directory: $dir")
        fi
    done
    
    # Check environment file
    if [[ ! -f "$backup_path/.env" ]]; then
        validation_errors+=("Missing environment file (.env)")
    fi
    
    # Check data integrity
    if [[ -d "$backup_path/data/postgres" ]]; then
        if [[ ! -f "$backup_path/data/postgres/PG_VERSION" ]]; then
            validation_errors+=("PostgreSQL data appears corrupted (missing PG_VERSION)")
        fi
    else
        validation_errors+=("Missing PostgreSQL data directory")
    fi
    
    if [[ -d "$backup_path/data/redis" ]]; then
        if [[ ! -f "$backup_path/data/redis/dump.rdb" ]] && [[ ! -f "$backup_path/data/redis/appendonly.aof" ]]; then
            log_warn "Redis persistence files not found (may be normal if no data was saved)"
        fi
    fi
    
    # Check configuration files
    essential_configs=("postgres/postgresql.conf" "litellm-arm64.yaml" "nginx-arm64.conf")
    for config in "${essential_configs[@]}"; do
        if [[ ! -f "$backup_path/config/$config" ]]; then
            validation_errors+=("Missing configuration file: $config")
        fi
    done
    
    # Report validation results
    if [[ ${#validation_errors[@]} -eq 0 ]]; then
        log_success "Backup validation passed"
        return 0
    else
        log_error "Backup validation failed with ${#validation_errors[@]} error(s):"
        for error in "${validation_errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi
}

# Create rollback state checkpoint
create_rollback_checkpoint() {
    local checkpoint_name="${1:-pre-rollback-$(date +%Y%m%d_%H%M%S)}"
    local checkpoint_path="$BACKUP_DIR/$checkpoint_name"
    
    log "Creating rollback checkpoint: $checkpoint_name"
    
    mkdir -p "$checkpoint_path"
    
    # Capture current state
    {
        echo "{"
        echo "  \"timestamp\": \"$(date -Iseconds)\","
        echo "  \"hostname\": \"$(hostname)\","
        echo "  \"checkpoint_name\": \"$checkpoint_name\","
        echo "  \"docker_compose_file\": \"$COMPOSE_FILE\","
        echo "  \"services\": ["
        
        if [[ -f "$COMPOSE_FILE" ]]; then
            docker-compose -f "$COMPOSE_FILE" config --services 2>/dev/null | \
            while IFS= read -r service; do
                echo "    \"$service\","
            done | sed '$s/,$//'
        fi
        
        echo "  ],"
        echo "  \"containers\": ["
        
        docker ps --format "{{.Names}}" | \
        while IFS= read -r container; do
            echo "    {"
            echo "      \"name\": \"$container\","
            echo "      \"image\": \"$(docker inspect --format='{{.Config.Image}}' "$container" 2>/dev/null || echo "unknown")\","
            echo "      \"status\": \"$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")\""
            echo "    },"
        done | sed '$s/,$//'
        
        echo "  ],"
        echo "  \"volumes\": ["
        
        docker volume ls --format "{{.Name}}" | \
        while IFS= read -r volume; do
            echo "    \"$volume\","
        done | sed '$s/,$//'
        
        echo "  ]"
        echo "}"
    } > "$checkpoint_path/state.json"
    
    # Backup current data and config
    if [[ -d "$DATA_DIR" ]]; then
        cp -r "$DATA_DIR" "$checkpoint_path/"
    fi
    
    if [[ -d "$CONFIG_DIR" ]]; then
        cp -r "$CONFIG_DIR" "$checkpoint_path/"
    fi
    
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        cp "$PROJECT_DIR/.env" "$checkpoint_path/"
    fi
    
    # Capture Docker state
    docker-compose -f "$COMPOSE_FILE" config > "$checkpoint_path/docker-compose-state.yml" 2>/dev/null || true
    docker images > "$checkpoint_path/docker-images.txt" 2>/dev/null || true
    docker ps -a > "$checkpoint_path/docker-containers.txt" 2>/dev/null || true
    docker volume ls > "$checkpoint_path/docker-volumes.txt" 2>/dev/null || true
    
    log_success "Rollback checkpoint created: $checkpoint_path"
}

# Graceful service shutdown
graceful_shutdown() {
    local timeout="${1:-60}"
    
    log "Initiating graceful shutdown (timeout: ${timeout}s)..."
    
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_warn "Docker compose file not found, attempting direct container shutdown"
        
        # Stop AI Swarm containers directly
        containers=$(docker ps --format "{{.Names}}" | grep -E "(oracle|litellm|openwebui|postgres|redis)" || echo "")
        if [[ -n "$containers" ]]; then
            echo "$containers" | xargs -r docker stop --time="$timeout"
        fi
        return 0
    fi
    
    # Shutdown in reverse dependency order
    shutdown_order=(
        "watchtower"
        "nginx"
        "grafana"
        "prometheus"
        "node-exporter"
        "cpu-inference"
        "open-webui"
        "litellm"
        "redis"
        "postgres"
    )
    
    for service in "${shutdown_order[@]}"; do
        if docker-compose -f "$COMPOSE_FILE" ps "$service" 2>/dev/null | grep -q "Up"; then
            log "Stopping service: $service"
            docker-compose -f "$COMPOSE_FILE" stop -t "$timeout" "$service" 2>/dev/null || {
                log_warn "Graceful stop failed for $service, forcing stop..."
                docker-compose -f "$COMPOSE_FILE" kill "$service" 2>/dev/null || true
            }
        fi
    done
    
    # Final cleanup
    docker-compose -f "$COMPOSE_FILE" down --remove-orphans --timeout "$timeout" 2>/dev/null || {
        log_warn "Docker compose down failed, forcing container removal..."
        containers=$(docker-compose -f "$COMPOSE_FILE" ps -q 2>/dev/null || echo "")
        if [[ -n "$containers" ]]; then
            echo "$containers" | xargs -r docker rm -f
        fi
    }
    
    log_success "Graceful shutdown completed"
}

# Restore from backup
restore_from_backup() {
    local backup_name="$1"
    local restore_mode="${2:-normal}"  # normal, emergency, partial
    local backup_path="$BACKUP_DIR/$backup_name"
    
    log "Starting restore from backup: $backup_name (mode: $restore_mode)"
    
    # Validate backup
    if ! validate_backup "$backup_path"; then
        if [[ "$restore_mode" != "emergency" ]]; then
            log_error "Backup validation failed. Use --force to proceed anyway."
            return 1
        else
            log_warn "Emergency mode: proceeding with potentially corrupted backup"
        fi
    fi
    
    # Create checkpoint before restore
    if [[ "$restore_mode" != "emergency" ]]; then
        create_rollback_checkpoint "pre-restore-$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Graceful shutdown
    if [[ "$restore_mode" == "emergency" ]]; then
        # In emergency mode, force stop everything quickly
        log "Emergency mode: Force stopping all services..."
        docker stop $(docker ps -q) 2>/dev/null || true
        docker rm -f $(docker ps -aq) 2>/dev/null || true
    else
        graceful_shutdown 30
    fi
    
    # Restore data
    if [[ -d "$backup_path/data" ]]; then
        log "Restoring data from backup..."
        
        # Backup current data if it exists
        if [[ -d "$DATA_DIR" ]] && [[ "$restore_mode" != "emergency" ]]; then
            mv "$DATA_DIR" "${DATA_DIR}.rollback-$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        else
            rm -rf "$DATA_DIR" 2>/dev/null || true
        fi
        
        cp -r "$backup_path/data" "$DATA_DIR"
        log_success "Data restored"
    else
        log_warn "No data directory in backup"
    fi
    
    # Restore configuration
    if [[ -d "$backup_path/config" ]]; then
        log "Restoring configuration from backup..."
        
        # Backup current config if it exists
        if [[ -d "$CONFIG_DIR" ]] && [[ "$restore_mode" != "emergency" ]]; then
            mv "$CONFIG_DIR" "${CONFIG_DIR}.rollback-$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        else
            rm -rf "$CONFIG_DIR" 2>/dev/null || true
        fi
        
        cp -r "$backup_path/config" "$CONFIG_DIR"
        log_success "Configuration restored"
    else
        log_warn "No config directory in backup"
    fi
    
    # Restore environment
    if [[ -f "$backup_path/.env" ]]; then
        log "Restoring environment configuration..."
        
        # Backup current .env if it exists
        if [[ -f "$PROJECT_DIR/.env" ]] && [[ "$restore_mode" != "emergency" ]]; then
            cp "$PROJECT_DIR/.env" "$PROJECT_DIR/.env.rollback-$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        fi
        
        cp "$backup_path/.env" "$PROJECT_DIR/"
        log_success "Environment configuration restored"
    else
        log_warn "No environment file in backup"
    fi
    
    # Set proper permissions
    chown -R 1000:1000 "$DATA_DIR" 2>/dev/null || true
    chmod -R 755 "$DATA_DIR" 2>/dev/null || true
    chown -R root:root "$CONFIG_DIR" 2>/dev/null || true
    chmod -R 644 "$CONFIG_DIR"/* 2>/dev/null || true
    
    # Clean Docker state
    log "Cleaning Docker state..."
    docker system prune -f >/dev/null 2>&1 || true
    
    # Record restore operation
    {
        echo "{"
        echo "  \"restore_timestamp\": \"$(date -Iseconds)\","
        echo "  \"backup_name\": \"$backup_name\","
        echo "  \"restore_mode\": \"$restore_mode\","
        echo "  \"emergency_mode\": $EMERGENCY_MODE,"
        echo "  \"restored_by\": \"$(whoami)\","
        echo "  \"hostname\": \"$(hostname)\""
        echo "}"
    } > "$ROLLBACK_STATE_FILE"
    
    log_success "Restore from backup completed: $backup_name"
}

# Start services after restore
start_after_restore() {
    log "Starting services after restore..."
    
    cd "$PROJECT_DIR"
    
    # Wait a moment for file system changes to propagate
    sleep 5
    
    # Pull any missing images
    log "Pulling required images..."
    if ! docker-compose -f "$COMPOSE_FILE" pull --quiet; then
        log_warn "Some images failed to pull, continuing with available images"
    fi
    
    # Start core services first
    log "Starting core services..."
    if ! docker-compose -f "$COMPOSE_FILE" up -d postgres redis; then
        log_error "Failed to start core services"
        return 1
    fi
    
    # Wait for core services
    log "Waiting for core services..."
    sleep 30
    
    # Check core services
    for service in postgres redis; do
        if ! docker-compose -f "$COMPOSE_FILE" ps "$service" | grep -q "Up"; then
            log_error "Core service $service failed to start after restore"
            return 1
        fi
    done
    
    # Start application services
    log "Starting application services..."
    if ! docker-compose -f "$COMPOSE_FILE" up -d litellm open-webui; then
        log_error "Failed to start application services"
        return 1
    fi
    
    # Wait for application services
    sleep 60
    
    # Start remaining services
    log "Starting remaining services..."
    docker-compose -f "$COMPOSE_FILE" up -d 2>/dev/null || {
        log_warn "Some services failed to start, checking individual service status"
    }
    
    log_success "Services started after restore"
}

# Validation after restore
validate_restore() {
    log "Validating restore operation..."
    
    # Run health check
    if [[ -x "$SCRIPT_DIR/health-check-arm64.sh" ]]; then
        log "Running health check..."
        "$SCRIPT_DIR/health-check-arm64.sh" >/dev/null 2>&1
        
        # Simple endpoint checks
        endpoints=(
            "http://localhost:3000"
            "http://localhost:4000/health"
            "http://localhost:80/health"
        )
        
        healthy_count=0
        for endpoint in "${endpoints[@]}"; do
            if curl -f -s --max-time 10 "$endpoint" >/dev/null 2>&1; then
                healthy_count=$((healthy_count + 1))
            fi
        done
        
        if [[ $healthy_count -eq ${#endpoints[@]} ]]; then
            log_success "All critical endpoints responding"
        elif [[ $healthy_count -gt 0 ]]; then
            log_warn "Some endpoints responding ($healthy_count/${#endpoints[@]})"
        else
            log_error "No endpoints responding - restore may have failed"
            return 1
        fi
    else
        log_warn "Health check script not found, skipping automated validation"
    fi
    
    # Check container status
    failed_services=()
    if [[ -f "$COMPOSE_FILE" ]]; then
        services=$(docker-compose -f "$COMPOSE_FILE" config --services 2>/dev/null || echo "")
        for service in $services; do
            if ! docker-compose -f "$COMPOSE_FILE" ps "$service" | grep -q "Up"; then
                failed_services+=("$service")
            fi
        done
    fi
    
    if [[ ${#failed_services[@]} -eq 0 ]]; then
        log_success "All services running after restore"
    else
        log_warn "Some services not running: ${failed_services[*]}"
    fi
    
    log_success "Restore validation completed"
}

# Interactive rollback selection
interactive_rollback() {
    echo "=============================================="
    echo "       ARM64 ORACLE CLOUD ROLLBACK"
    echo "=============================================="
    echo ""
    
    # List backups
    if ! list_backups; then
        log_error "No backups available for rollback"
        exit 1
    fi
    
    echo ""
    read -p "Select backup number to restore (or 'q' to quit): " selection
    
    if [[ "$selection" == "q" ]] || [[ "$selection" == "Q" ]]; then
        log "Rollback cancelled by user"
        exit 0
    fi
    
    # Validate selection
    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        log_error "Invalid selection: $selection"
        exit 1
    fi
    
    # Get selected backup
    backups=($(find "$BACKUP_DIR" -maxdepth 1 -type d -name "*" | sort -r))
    backup_index=0
    selected_backup=""
    
    for backup in "${backups[@]}"; do
        if [[ "$backup" == "$BACKUP_DIR" ]]; then
            continue
        fi
        backup_index=$((backup_index + 1))
        if [[ $backup_index -eq $selection ]]; then
            selected_backup=$(basename "$backup")
            break
        fi
    done
    
    if [[ -z "$selected_backup" ]]; then
        log_error "Invalid backup selection: $selection"
        exit 1
    fi
    
    echo ""
    echo "Selected backup: $selected_backup"
    echo "This will:"
    echo "  1. Stop all running services"
    echo "  2. Create a checkpoint of current state"
    echo "  3. Restore data and configuration from backup"
    echo "  4. Restart services"
    echo "  5. Validate the restore"
    echo ""
    
    read -p "Continue with rollback? (y/N): " confirm
    if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
        log "Rollback cancelled by user"
        exit 0
    fi
    
    # Perform rollback
    log "Starting rollback to: $selected_backup"
    
    restore_from_backup "$selected_backup" "normal"
    start_after_restore
    validate_restore
    
    echo ""
    echo "=============================================="
    echo "         ROLLBACK COMPLETED"
    echo "=============================================="
    echo "Backup restored: $selected_backup"
    echo "Services restarted: $(date)"
    echo "Log file: $ROLLBACK_LOG"
    echo ""
    echo "Next steps:"
    echo "1. Verify all services are working correctly"
    echo "2. Run health check: ./scripts/health-check-arm64.sh"
    echo "3. Test API endpoints"
    echo "4. Check application functionality"
    echo ""
}

# Quick rollback to latest backup
quick_rollback() {
    log "Starting quick rollback to latest backup..."
    
    latest_backup=$(find "$BACKUP_DIR" -name "pre-deployment-*" -type d | sort -r | head -n1)
    if [[ -z "$latest_backup" ]]; then
        log_error "No pre-deployment backup found for quick rollback"
        exit 1
    fi
    
    backup_name=$(basename "$latest_backup")
    log "Quick rollback to: $backup_name"
    
    restore_from_backup "$backup_name" "normal"
    start_after_restore
    validate_restore
    
    log_success "Quick rollback completed to: $backup_name"
}

# Show rollback help
show_help() {
    cat << EOF
ARM64 Oracle Cloud Rollback Script

USAGE:
    $0 [command] [options]

COMMANDS:
    interactive     - Interactive rollback with backup selection (default)
    quick          - Quick rollback to latest pre-deployment backup
    restore <name> - Restore specific backup by name
    emergency      - Emergency rollback (faster, less validation)
    list           - List available backups
    validate <name>- Validate backup integrity
    checkpoint     - Create rollback checkpoint of current state

OPTIONS:
    --force        - Force restore even if validation fails
    --no-validate  - Skip post-restore validation
    --help         - Show this help message

EXAMPLES:
    $0                                    # Interactive rollback
    $0 quick                             # Quick rollback to latest backup
    $0 restore pre-deployment-20241201   # Restore specific backup
    $0 emergency                         # Emergency rollback
    $0 list                              # List all backups
    $0 checkpoint                        # Create checkpoint

FILES:
    Backups:       $BACKUP_DIR
    Logs:          $LOG_DIR
    Compose File:  $COMPOSE_FILE

For more information, see the deployment documentation.
EOF
}

# Main execution
main() {
    local command="${1:-interactive}"
    local backup_name="${2:-}"
    local force_flag=false
    local validate_flag=true
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force_flag=true
                shift
                ;;
            --no-validate)
                validate_flag=false
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done
    
    case "$command" in
        "interactive"|"")
            interactive_rollback
            ;;
        "quick")
            quick_rollback
            ;;
        "restore")
            if [[ -z "$backup_name" ]]; then
                log_error "Backup name required for restore command"
                echo "Usage: $0 restore <backup_name>"
                exit 1
            fi
            restore_from_backup "$backup_name" "normal"
            if [[ "$validate_flag" == "true" ]]; then
                start_after_restore
                validate_restore
            fi
            ;;
        "emergency")
            latest_backup=$(find "$BACKUP_DIR" -name "*" -type d | sort -r | head -n1)
            if [[ -z "$latest_backup" ]]; then
                log_error "No backups available for emergency rollback"
                exit 1
            fi
            backup_name=$(basename "$latest_backup")
            EMERGENCY_MODE=true
            restore_from_backup "$backup_name" "emergency"
            start_after_restore
            ;;
        "list")
            list_backups
            ;;
        "validate")
            if [[ -z "$backup_name" ]]; then
                log_error "Backup name required for validate command"
                echo "Usage: $0 validate <backup_name>"
                exit 1
            fi
            validate_backup "$BACKUP_DIR/$backup_name"
            ;;
        "checkpoint")
            create_rollback_checkpoint
            ;;
        "help")
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Run '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi