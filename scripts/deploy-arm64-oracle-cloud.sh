#!/bin/bash

# ARM64 Deployment Script for Oracle Cloud Free Tier
# Optimized for Ampere A1 (4 cores, 24GB RAM)
# Version: 2.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="/opt/ai-swarm/logs/deployment"
CONFIG_DIR="/opt/ai-swarm/config"
DATA_DIR="/opt/ai-swarm/data"
BACKUP_DIR="/opt/ai-swarm/backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_DIR}/deployment.log"
}

log_error() {
    echo -e "${RED}[ERROR $(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_DIR}/deployment.log" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN $(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_DIR}/deployment.log"
}

log_success() {
    echo -e "${GREEN}[SUCCESS $(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_DIR}/deployment.log"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code: $exit_code"
    log "Starting cleanup process..."
    
    # Stop any running containers
    if command -v docker-compose &> /dev/null; then
        docker-compose -f "${PROJECT_DIR}/docker-compose-arm64.yml" down --remove-orphans || true
    fi
    
    # Restore from backup if available
    if [[ -d "${BACKUP_DIR}/$(date +%Y%m%d)" ]]; then
        log "Restoring from backup..."
        restore_from_backup "$(date +%Y%m%d)"
    fi
    
    exit $exit_code
}

trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running on ARM64
    if [[ "$(uname -m)" != "aarch64" ]]; then
        log_error "This script is designed for ARM64 architecture only. Current: $(uname -m)"
        exit 1
    fi
    
    # Check RAM
    total_ram=$(free -g | awk 'NR==2{print $2}')
    if [[ $total_ram -lt 20 ]]; then
        log_error "Insufficient RAM. Required: 24GB+, Available: ${total_ram}GB"
        exit 1
    fi
    
    # Check disk space
    available_disk=$(df /opt | awk 'NR==2 {print $4}')
    if [[ $available_disk -lt 20971520 ]]; then # 20GB in KB
        log_error "Insufficient disk space. Required: 20GB+, Available: $((available_disk/1024/1024))GB"
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    # Check for required environment file
    if [[ ! -f "${PROJECT_DIR}/.env" ]]; then
        log_error "Environment file (.env) not found. Copy .env.example and fill in the values."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# System optimization for Oracle Cloud
optimize_oracle_cloud() {
    log "Applying Oracle Cloud optimizations..."
    
    # Optimize kernel parameters for containers
    cat << EOF | sudo tee /etc/sysctl.d/99-ai-swarm.conf
# Network optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 16384 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq

# Container optimizations
vm.max_map_count = 262144
fs.file-max = 2097152
kernel.pid_max = 4194304

# Oracle Cloud specific
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
    
    sudo sysctl -p /etc/sysctl.d/99-ai-swarm.conf
    
    # Configure systemd limits
    sudo mkdir -p /etc/systemd/system/docker.service.d
    cat << EOF | sudo tee /etc/systemd/system/docker.service.d/override.conf
[Service]
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity
TasksMax=1048576
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    
    log_success "Oracle Cloud optimizations applied"
}

# Directory setup
setup_directories() {
    log "Setting up directory structure..."
    
    # Create required directories
    sudo mkdir -p "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${BACKUP_DIR}"
    sudo mkdir -p "${DATA_DIR}"/{postgres,redis,openwebui,grafana,prometheus}
    sudo mkdir -p "${LOG_DIR}"/{litellm,nginx}
    sudo mkdir -p "${CONFIG_DIR}"/{nginx,postgres,grafana,prometheus}
    
    # Set permissions
    sudo chown -R 1000:1000 "${DATA_DIR}" "${LOG_DIR}"
    sudo chown -R root:root "${CONFIG_DIR}"
    sudo chmod -R 755 "${DATA_DIR}" "${LOG_DIR}" "${CONFIG_DIR}"
    
    log_success "Directory structure created"
}

# Configuration generation
generate_configurations() {
    log "Generating configuration files..."
    
    # PostgreSQL configuration
    cat << EOF > "${CONFIG_DIR}/postgres/postgresql.conf"
# ARM64 optimized PostgreSQL configuration
max_connections = 100
shared_buffers = 512MB
effective_cache_size = 1536MB
maintenance_work_mem = 128MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 8MB
min_wal_size = 1GB
max_wal_size = 4GB
max_worker_processes = 4
max_parallel_workers_per_gather = 2
max_parallel_workers = 4
max_parallel_maintenance_workers = 2
EOF
    
    # LiteLLM configuration
    cat << EOF > "${CONFIG_DIR}/litellm-arm64.yaml"
model_list:
  - model_name: gemini-2.0-flash-exp
    litellm_params:
      model: gemini/gemini-2.0-flash-exp
      api_key: \${GEMINI_API_KEY}
      
  - model_name: deepseek-v3
    litellm_params:
      model: deepseek/deepseek-chat
      api_key: \${DEEPSEEK_API_KEY}
      
  - model_name: grok-beta
    litellm_params:
      model: groq/mixtral-8x7b-32768
      api_key: \${GROQ_API_KEY}

litellm_settings:
  cache: true
  cache_params:
    type: redis
    host: redis
    port: 6379
    password: \${REDIS_PASSWORD}
  success_callback: ["redis"]
  failure_callback: ["redis"]
  set_verbose: false
  json_logs: true
  
general_settings:
  master_key: \${LITELLM_MASTER_KEY}
  database_url: postgresql://litellm_user:\${POSTGRES_PASSWORD}@postgres:5432/litellm_db
  ui_access_mode: admin_only
  allow_user_auth: true
  max_budget: 100.0
  budget_duration: 30d
EOF
    
    # Nginx configuration
    cat << EOF > "${CONFIG_DIR}/nginx-arm64.conf"
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    
    # Performance optimizations
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    
    # Compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone \$binary_remote_addr zone=ui:10m rate=5r/s;
    
    upstream litellm {
        server litellm:4000 max_fails=3 fail_timeout=30s;
    }
    
    upstream openwebui {
        server open-webui:8080 max_fails=3 fail_timeout=30s;
    }
    
    server {
        listen 80;
        server_name _;
        
        # Health check endpoint
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
        
        # Open WebUI
        location / {
            limit_req zone=ui burst=10 nodelay;
            proxy_pass http://openwebui;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_buffering off;
            proxy_request_buffering off;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            client_max_body_size 100M;
        }
        
        # LiteLLM API
        location /v1/ {
            limit_req zone=api burst=20 nodelay;
            proxy_pass http://litellm/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_read_timeout 300s;
            proxy_send_timeout 300s;
            client_max_body_size 10M;
        }
    }
}
EOF
    
    # Prometheus configuration
    cat << EOF > "${CONFIG_DIR}/prometheus-arm64.yml"
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'oracle-cloud-arm64'
    region: 'us-phoenix-1'

rule_files:
  - "alert_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
      
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
      
  - job_name: 'litellm'
    static_configs:
      - targets: ['litellm:4000']
    metrics_path: '/metrics'
    
  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres:5432']
      
  - job_name: 'redis'
    static_configs:
      - targets: ['redis:6379']

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
EOF
    
    log_success "Configuration files generated"
}

# Create CPU requirements file
create_cpu_requirements() {
    cat << EOF > "${PROJECT_DIR}/requirements-cpu.txt"
flask==3.0.0
transformers==4.36.0
torch==2.1.0+cpu --index-url https://download.pytorch.org/whl/cpu
numpy==1.24.3
requests==2.31.0
gunicorn==21.2.0
EOF
}

# Create CPU inference server
create_cpu_inference_server() {
    cat << 'EOF' > "${PROJECT_DIR}/cpu_inference_server.py"
#!/usr/bin/env python3
"""
ARM64 optimized CPU inference server
Lightweight inference for Oracle Cloud free tier
"""

import os
import sys
import logging
from flask import Flask, request, jsonify
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
import threading
import time
from functools import lru_cache

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Global variables
model = None
tokenizer = None
model_lock = threading.Lock()

# Configuration
MODEL_NAME = os.getenv("MODEL_NAME", "microsoft/DialoGPT-small")
DEVICE = os.getenv("DEVICE", "cpu")
PORT = int(os.getenv("PORT", 8000))
WORKERS = int(os.getenv("WORKERS", 2))
MAX_REQUESTS = int(os.getenv("MAX_REQUESTS", 50))

class ModelManager:
    def __init__(self):
        self.model = None
        self.tokenizer = None
        self.loaded = False
        self.load_model()
    
    def load_model(self):
        """Load model with error handling and optimization for ARM64"""
        try:
            logger.info(f"Loading model: {MODEL_NAME} on {DEVICE}")
            
            # ARM64 specific optimizations
            torch.set_num_threads(2)  # Optimize for 4-core ARM64
            
            self.tokenizer = AutoTokenizer.from_pretrained(
                MODEL_NAME,
                cache_dir="/tmp/model_cache",
                local_files_only=False
            )
            
            self.model = AutoModelForCausalLM.from_pretrained(
                MODEL_NAME,
                cache_dir="/tmp/model_cache",
                torch_dtype=torch.float32,  # ARM64 optimization
                low_cpu_mem_usage=True,
                local_files_only=False
            )
            
            self.model.to(DEVICE)
            self.model.eval()  # Set to evaluation mode
            
            # Add padding token if not present
            if self.tokenizer.pad_token is None:
                self.tokenizer.pad_token = self.tokenizer.eos_token
            
            self.loaded = True
            logger.info("Model loaded successfully")
            
        except Exception as e:
            logger.error(f"Model loading failed: {e}")
            self.loaded = False
            raise

    @lru_cache(maxsize=100)
    def generate_cached(self, prompt_hash, max_length=100):
        """Cached generation for repeated prompts"""
        return self._generate(prompt_hash, max_length)
    
    def _generate(self, prompt, max_length=100):
        """Internal generation method"""
        if not self.loaded:
            raise RuntimeError("Model not loaded")
        
        with model_lock:
            try:
                # Tokenize input
                inputs = self.tokenizer(
                    prompt,
                    return_tensors="pt",
                    truncation=True,
                    padding=True,
                    max_length=512
                ).to(DEVICE)
                
                # Generate response
                with torch.no_grad():
                    outputs = self.model.generate(
                        **inputs,
                        max_length=min(max_length, 200),  # Conservative limit
                        num_return_sequences=1,
                        do_sample=True,
                        temperature=0.7,
                        pad_token_id=self.tokenizer.eos_token_id,
                        no_repeat_ngram_size=2,
                        early_stopping=True
                    )
                
                # Decode response
                response = self.tokenizer.decode(
                    outputs[0],
                    skip_special_tokens=True
                )
                
                # Extract only the new tokens
                if prompt in response:
                    response = response[len(prompt):].strip()
                
                return response
                
            except Exception as e:
                logger.error(f"Generation failed: {e}")
                return f"Error: {str(e)}"

# Initialize model manager
try:
    model_manager = ModelManager()
except Exception as e:
    logger.error(f"Failed to initialize model: {e}")
    model_manager = None

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    status = {
        "status": "healthy" if model_manager and model_manager.loaded else "unhealthy",
        "device": DEVICE,
        "model": MODEL_NAME,
        "loaded": model_manager.loaded if model_manager else False,
        "torch_version": torch.__version__,
        "cpu_count": torch.get_num_threads()
    }
    return jsonify(status), 200 if status["status"] == "healthy" else 503

@app.route('/generate', methods=['POST'])
def generate():
    """Generate text from prompt"""
    if not model_manager or not model_manager.loaded:
        return jsonify({"error": "Model not loaded"}), 503
    
    try:
        data = request.get_json()
        if not data or 'prompt' not in data:
            return jsonify({"error": "Missing 'prompt' in request"}), 400
        
        prompt = data.get('prompt', '').strip()
        max_length = min(data.get('max_length', 100), 200)  # Limit max length
        
        if not prompt:
            return jsonify({"error": "Empty prompt"}), 400
        
        # Generate response
        response = model_manager._generate(prompt, max_length)
        
        return jsonify({
            "response": response,
            "prompt": prompt,
            "model": MODEL_NAME,
            "device": DEVICE
        })
        
    except Exception as e:
        logger.error(f"Generation endpoint error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/models', methods=['GET'])
def models():
    """List available models"""
    return jsonify({
        "models": [MODEL_NAME],
        "current": MODEL_NAME,
        "device": DEVICE
    })

@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Endpoint not found"}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({"error": "Internal server error"}), 500

if __name__ == '__main__':
    logger.info(f"Starting CPU inference server on port {PORT}")
    logger.info(f"Model: {MODEL_NAME}, Device: {DEVICE}")
    logger.info(f"Workers: {WORKERS}, Max requests: {MAX_REQUESTS}")
    
    app.run(
        host='0.0.0.0',
        port=PORT,
        debug=False,
        threaded=True
    )
EOF
}

# Backup current state
create_backup() {
    local backup_name="${1:-$(date +%Y%m%d_%H%M%S)}"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    
    log "Creating backup: ${backup_name}"
    
    mkdir -p "${backup_path}"
    
    # Backup data
    if [[ -d "${DATA_DIR}" ]]; then
        cp -r "${DATA_DIR}" "${backup_path}/"
    fi
    
    # Backup configurations
    if [[ -d "${CONFIG_DIR}" ]]; then
        cp -r "${CONFIG_DIR}" "${backup_path}/"
    fi
    
    # Backup environment
    if [[ -f "${PROJECT_DIR}/.env" ]]; then
        cp "${PROJECT_DIR}/.env" "${backup_path}/"
    fi
    
    log_success "Backup created: ${backup_path}"
}

# Restore from backup
restore_from_backup() {
    local backup_name="$1"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    
    if [[ ! -d "${backup_path}" ]]; then
        log_error "Backup not found: ${backup_path}"
        return 1
    fi
    
    log "Restoring from backup: ${backup_name}"
    
    # Stop services
    docker-compose -f "${PROJECT_DIR}/docker-compose-arm64.yml" down --remove-orphans || true
    
    # Restore data
    if [[ -d "${backup_path}/data" ]]; then
        rm -rf "${DATA_DIR}"
        cp -r "${backup_path}/data" "${DATA_DIR}"
    fi
    
    # Restore configurations
    if [[ -d "${backup_path}/config" ]]; then
        rm -rf "${CONFIG_DIR}"
        cp -r "${backup_path}/config" "${CONFIG_DIR}"
    fi
    
    # Restore environment
    if [[ -f "${backup_path}/.env" ]]; then
        cp "${backup_path}/.env" "${PROJECT_DIR}/"
    fi
    
    log_success "Restore completed"
}

# Pre-deployment validation
validate_environment() {
    log "Validating environment configuration..."
    
    # Check required environment variables
    source "${PROJECT_DIR}/.env"
    
    required_vars=(
        "POSTGRES_PASSWORD"
        "REDIS_PASSWORD"
        "LITELLM_MASTER_KEY"
        "WEBUI_SECRET_KEY"
        "ADMIN_PASSWORD"
        "GRAFANA_ADMIN_PASSWORD"
        "GEMINI_API_KEY"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable not set: $var"
            exit 1
        fi
    done
    
    # Validate passwords strength
    if [[ ${#POSTGRES_PASSWORD} -lt 16 ]]; then
        log_warn "Postgres password is less than 16 characters"
    fi
    
    if [[ ${#REDIS_PASSWORD} -lt 16 ]]; then
        log_warn "Redis password is less than 16 characters"
    fi
    
    log_success "Environment validation passed"
}

# Deploy services
deploy_services() {
    log "Starting ARM64 deployment..."
    
    cd "${PROJECT_DIR}"
    
    # Pull images first
    log "Pulling ARM64 images..."
    docker-compose -f docker-compose-arm64.yml pull
    
    # Start core services first
    log "Starting core services (postgres, redis)..."
    docker-compose -f docker-compose-arm64.yml up -d postgres redis
    
    # Wait for core services
    log "Waiting for core services to be ready..."
    sleep 30
    
    # Check core services health
    for service in postgres redis; do
        if ! docker-compose -f docker-compose-arm64.yml exec -T $service sh -c "exit 0" &>/dev/null; then
            log_error "Core service $service failed to start"
            exit 1
        fi
    done
    
    # Start application services
    log "Starting application services..."
    docker-compose -f docker-compose-arm64.yml up -d litellm open-webui
    
    # Wait for application services
    sleep 60
    
    # Start monitoring services
    log "Starting monitoring services..."
    docker-compose -f docker-compose-arm64.yml up -d prometheus grafana node-exporter
    
    # Start remaining services
    log "Starting remaining services..."
    docker-compose -f docker-compose-arm64.yml up -d nginx cpu-inference watchtower
    
    log_success "All services started"
}

# Post-deployment validation
validate_deployment() {
    log "Validating deployment..."
    
    # Check container status
    failed_containers=()
    
    containers=$(docker-compose -f "${PROJECT_DIR}/docker-compose-arm64.yml" ps --services)
    
    for container in $containers; do
        if ! docker-compose -f "${PROJECT_DIR}/docker-compose-arm64.yml" ps "$container" | grep -q "Up"; then
            failed_containers+=("$container")
        fi
    done
    
    if [[ ${#failed_containers[@]} -gt 0 ]]; then
        log_error "Failed containers: ${failed_containers[*]}"
        
        for container in "${failed_containers[@]}"; do
            log "Logs for $container:"
            docker-compose -f "${PROJECT_DIR}/docker-compose-arm64.yml" logs --tail=20 "$container"
        done
        
        return 1
    fi
    
    # Test endpoints
    endpoints=(
        "http://localhost:3000"  # Open WebUI
        "http://localhost:4000/health"  # LiteLLM
        "http://localhost:9090"  # Prometheus
        "http://localhost:3001"  # Grafana
        "http://localhost:80/health"  # Nginx
    )
    
    for endpoint in "${endpoints[@]}"; do
        if ! curl -f -s --max-time 10 "$endpoint" > /dev/null; then
            log_warn "Endpoint not responding: $endpoint"
        else
            log_success "Endpoint healthy: $endpoint"
        fi
    done
    
    log_success "Deployment validation completed"
}

# Generate deployment report
generate_report() {
    local report_file="${LOG_DIR}/deployment-report-$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "=== ARM64 Oracle Cloud Deployment Report ==="
        echo "Date: $(date)"
        echo "Architecture: $(uname -m)"
        echo "Kernel: $(uname -r)"
        echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
        echo ""
        
        echo "=== System Resources ==="
        echo "CPU Cores: $(nproc)"
        echo "Total RAM: $(free -h | awk 'NR==2{print $2}')"
        echo "Available RAM: $(free -h | awk 'NR==2{print $7}')"
        echo "Disk Usage: $(df -h /opt | awk 'NR==2{print $3"/"$2" ("$5" used)"}')"
        echo ""
        
        echo "=== Docker Information ==="
        echo "Docker Version: $(docker --version)"
        echo "Docker Compose Version: $(docker-compose --version)"
        echo "Docker Info:"
        docker info | grep -E "(CPUs|Total Memory|Kernel Version|Operating System|Architecture)"
        echo ""
        
        echo "=== Container Status ==="
        docker-compose -f "${PROJECT_DIR}/docker-compose-arm64.yml" ps
        echo ""
        
        echo "=== Service Endpoints ==="
        echo "Open WebUI: http://$(curl -s ifconfig.me):3000"
        echo "LiteLLM API: http://$(curl -s ifconfig.me):4000/v1"
        echo "Prometheus: http://$(curl -s ifconfig.me):9090 (internal)"
        echo "Grafana: http://$(curl -s ifconfig.me):3001 (internal)"
        echo ""
        
        echo "=== Network Configuration ==="
        echo "Public IP: $(curl -s ifconfig.me)"
        echo "Docker Networks:"
        docker network ls | grep aiswarm
        echo ""
        
        echo "=== Resource Usage ==="
        echo "Container Resources:"
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
        
    } > "$report_file"
    
    log_success "Deployment report generated: $report_file"
    
    # Display summary
    echo ""
    echo "=========================================="
    echo "  ARM64 Oracle Cloud Deployment Complete"
    echo "=========================================="
    echo ""
    echo "🌐 Open WebUI: http://$(curl -s ifconfig.me):3000"
    echo "🤖 LiteLLM API: http://$(curl -s ifconfig.me):4000/v1"
    echo "📊 Monitoring: http://localhost:9090 (Prometheus)"
    echo "📈 Dashboard: http://localhost:3001 (Grafana)"
    echo ""
    echo "📁 Report: $report_file"
    echo "📁 Logs: ${LOG_DIR}/deployment.log"
    echo ""
    echo "Next steps:"
    echo "1. Configure firewall rules for ports 80, 443, 3000, 4000"
    echo "2. Set up SSL certificates"
    echo "3. Configure DNS records"
    echo "4. Test API endpoints"
    echo ""
}

# Main deployment function
main() {
    log "Starting ARM64 Oracle Cloud deployment..."
    
    # Initialize
    setup_directories
    create_backup "pre-deployment-$(date +%Y%m%d_%H%M%S)"
    
    # Prerequisites
    check_prerequisites
    validate_environment
    
    # System optimization
    optimize_oracle_cloud
    
    # Configuration
    generate_configurations
    create_cpu_requirements
    create_cpu_inference_server
    
    # Deploy
    deploy_services
    
    # Validation
    sleep 60  # Wait for all services to start
    validate_deployment
    
    # Report
    generate_report
    
    log_success "ARM64 Oracle Cloud deployment completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi