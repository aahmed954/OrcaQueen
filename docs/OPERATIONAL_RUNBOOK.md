# 🔧 AI-SWARM-MIAMI-2025 Operational Runbook

**Version**: 1.0.0
**Critical Contacts**: DevOps Team
**Last Updated**: September 23, 2025

---

## 🚨 Emergency Procedures

### System-Wide Outage

**Symptoms**: All services unreachable, no API responses

**Immediate Actions**:
```bash
# 1. Check network connectivity
tailscale status
ping 100.96.197.84
ping 100.72.73.3
ping 100.122.12.54

# 2. Check Docker status on all nodes
ssh oracle1 "docker ps"
ssh starlord "docker ps"
ssh thanos "docker ps"

# 3. Emergency restart sequence
./scripts/emergency-restart.sh

# 4. Verify critical services
curl http://100.96.197.84:3000/health
curl http://100.72.73.3:8000/health
```

### GPU Memory Crisis

**Symptoms**: OOM errors, inference failures

**Resolution**:
```bash
# 1. Check GPU status
nvidia-smi

# 2. Clear GPU cache
docker exec starlord-vllm python -c "import torch; torch.cuda.empty_cache()"

# 3. Reduce batch size
docker exec starlord-vllm sed -i 's/batch_size=16/batch_size=8/' /config/vllm.yaml

# 4. Restart vLLM service
docker-compose -f deploy/02-starlord-OPTIMIZED.yml restart vllm
```

---

## 📋 Daily Operations

### Morning Health Check (9 AM EST)

```bash
#!/bin/bash
# Daily health check script

echo "=== AI-SWARM Daily Health Check ==="
echo "Date: $(date)"

# Check all services
for service in litellm vllm qdrant sillytavern gpt-researcher; do
    echo "Checking $service..."
    docker ps | grep $service || echo "WARNING: $service not running"
done

# Check GPU utilization
echo "GPU Status:"
nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total --format=csv

# Check disk space
echo "Disk Usage:"
df -h | grep -E "/$|/mnt"

# Check API responsiveness
echo "API Health:"
curl -s http://100.96.197.84:4000/health | jq .status
```

### Evening Maintenance (11 PM EST)

```bash
# Clean up logs
find /var/log -name "*.log" -mtime +7 -delete

# Vacuum PostgreSQL
docker exec oracle-postgres psql -U litellm -c "VACUUM ANALYZE;"

# Clear Redis cache (selective)
docker exec oracle-redis redis-cli --scan --pattern "cache:*" | xargs redis-cli DEL

# Backup critical data
./scripts/nightly-backup.sh
```

---

## 🔄 Service Management

### Starting Services

#### Correct Startup Sequence
```bash
# 1. Infrastructure services (Oracle)
docker-compose -f deploy/01-oracle-ARM.yml up -d postgres redis consul

# Wait for database
while ! docker exec oracle-postgres pg_isready; do
    sleep 2
done

# 2. Gateway services (Oracle)
docker-compose -f deploy/01-oracle-ARM.yml up -d haproxy litellm open-webui

# 3. Inference services (Starlord)
docker-compose -f deploy/02-starlord-OPTIMIZED.yml up -d vllm-primary vllm-secondary

# 4. User services (Thanos)
docker-compose -f deploy/03-thanos-SECURED.yml up -d sillytavern gpt-researcher

# 5. Monitoring stack
docker-compose -f deploy/01-oracle-ARM.yml up -d prometheus grafana
```

### Stopping Services

#### Graceful Shutdown Sequence
```bash
# 1. Stop user-facing services first
docker-compose -f deploy/03-thanos-SECURED.yml stop sillytavern

# 2. Stop inference engines
docker-compose -f deploy/02-starlord-OPTIMIZED.yml stop vllm-primary vllm-secondary

# 3. Stop gateway
docker-compose -f deploy/01-oracle-ARM.yml stop litellm open-webui

# 4. Stop infrastructure last
docker-compose -f deploy/01-oracle-ARM.yml stop postgres redis
```

### Service Restart Procedures

#### Individual Service Restart
```bash
# Restart with zero-downtime
docker-compose -f <compose-file> up -d --no-deps --build <service-name>

# Example: Restart LiteLLM
docker-compose -f deploy/01-oracle-ARM.yml up -d --no-deps --build litellm

# Verify service health
sleep 10
curl http://100.96.197.84:4000/health
```

---

## 🐛 Troubleshooting Guide

### Common Issues and Solutions

#### Issue: High Latency (>5s response time)

**Diagnosis**:
```bash
# Check model loading
docker logs starlord-vllm | grep "Model loaded"

# Check batch queue
curl http://100.72.73.3:8000/metrics | grep queue_size

# Check network latency
ping -c 10 100.96.197.84 | grep avg
```

**Solution**:
```bash
# Option 1: Adjust batch size
docker exec starlord-vllm python -c "
import yaml
config = yaml.safe_load(open('/config/vllm.yaml'))
config['batch_size'] = 8
yaml.dump(config, open('/config/vllm.yaml', 'w'))
"

# Option 2: Enable model caching
docker exec starlord-vllm mkdir -p /cache/models
docker exec starlord-vllm export HF_HOME=/cache/models

# Restart service
docker-compose -f deploy/02-starlord-OPTIMIZED.yml restart vllm-primary
```

#### Issue: Database Connection Errors

**Diagnosis**:
```bash
# Check PostgreSQL status
docker exec oracle-postgres pg_isready

# Check connections
docker exec oracle-postgres psql -U litellm -c "SELECT count(*) FROM pg_stat_activity;"

# Check logs
docker logs oracle-postgres --tail 50
```

**Solution**:
```bash
# Option 1: Increase connection pool
docker exec oracle-postgres psql -U postgres -c "ALTER SYSTEM SET max_connections = 200;"
docker-compose -f deploy/01-oracle-ARM.yml restart postgres

# Option 2: Clear stale connections
docker exec oracle-postgres psql -U postgres -c "
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle'
AND state_change < now() - interval '10 minutes';
"
```

#### Issue: Qdrant Performance Degradation

**Diagnosis**:
```bash
# Check collection stats
curl http://100.72.73.3:6333/collections

# Check memory usage
curl http://100.72.73.3:6333/telemetry | jq .memory

# Check index optimization
curl http://100.72.73.3:6333/collections/documents | jq .result.status
```

**Solution**:
```bash
# Optimize collection
curl -X POST http://100.72.73.3:6333/collections/documents/index/optimize

# Increase cache
docker exec starlord-qdrant sed -i 's/cache_size: 1000/cache_size: 5000/' /qdrant/config/config.yaml
docker restart starlord-qdrant
```

---

## 📊 Performance Tuning

### GPU Optimization

```bash
# Set GPU persistence mode
sudo nvidia-smi -pm 1

# Set power limit (watts)
sudo nvidia-smi -pl 350

# Set GPU clocks (MHz)
sudo nvidia-smi -ac 1593,1410

# Monitor GPU performance
watch -n 1 nvidia-smi
```

### Memory Management

```bash
# Configure swap for emergencies
sudo fallocate -l 32G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Set swappiness (prefer RAM)
sudo sysctl vm.swappiness=10

# Clear page cache
sudo sync && echo 1 > /proc/sys/vm/drop_caches
```

### Network Optimization

```bash
# Optimize TCP settings
sudo sysctl -w net.core.rmem_max=134217728
sudo sysctl -w net.core.wmem_max=134217728
sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728"
sudo sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728"

# Enable BBR congestion control
sudo sysctl -w net.core.default_qdisc=fq
sudo sysctl -w net.ipv4.tcp_congestion_control=bbr
```

---

## 🔐 Security Operations

### API Key Rotation

```bash
# 1. Generate new API keys
python scripts/key_rotation.py --generate

# 2. Update Vault
docker exec oracle-vault vault kv put secret/api-keys \
  openrouter="${NEW_OPENROUTER_KEY}" \
  gemini="${NEW_GEMINI_KEY}"

# 3. Restart affected services
docker-compose -f deploy/01-oracle-ARM.yml restart litellm

# 4. Verify new keys work
curl -X POST http://100.96.197.84:4000/v1/chat/completions \
  -H "Authorization: Bearer ${NEW_API_KEY}" \
  -d '{"model":"gemini-2.5-flash-free","messages":[{"role":"user","content":"test"}]}'
```

### Security Audit

```bash
# Check for exposed secrets
grep -r "sk-" . --exclude-dir=.git 2>/dev/null
grep -r "AIzaSy" . --exclude-dir=.git 2>/dev/null

# Check open ports
nmap -sT -O localhost

# Check Docker security
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image oracle-litellm:latest

# Review access logs
docker logs oracle-haproxy | grep -E "401|403" | tail -20
```

---

## 💾 Backup and Recovery

### Automated Backup Script

```bash
#!/bin/bash
# /scripts/automated-backup.sh

BACKUP_DIR="/backup/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Backup PostgreSQL
docker exec oracle-postgres pg_dumpall -U postgres > $BACKUP_DIR/postgres.sql

# Backup Qdrant
curl -X POST http://100.72.73.3:6333/snapshots > $BACKUP_DIR/qdrant-snapshot.json

# Backup configurations
tar -czf $BACKUP_DIR/configs.tar.gz /home/starlord/OrcaQueen/config/

# Backup Docker volumes
docker run --rm -v oracle_postgres_data:/data -v $BACKUP_DIR:/backup \
  alpine tar czf /backup/postgres-volume.tar.gz /data

# Upload to remote storage
rsync -avz $BACKUP_DIR/ backup-server:/ai-swarm-backups/

# Keep only last 7 days
find /backup -type d -mtime +7 -exec rm -rf {} \;
```

### Disaster Recovery

```bash
#!/bin/bash
# /scripts/disaster-recovery.sh

RESTORE_DATE=$1
BACKUP_DIR="/backup/$RESTORE_DATE"

# Stop all services
docker-compose down

# Restore PostgreSQL
docker-compose -f deploy/01-oracle-ARM.yml up -d postgres
sleep 10
docker exec -i oracle-postgres psql -U postgres < $BACKUP_DIR/postgres.sql

# Restore Qdrant
docker-compose -f deploy/02-starlord-OPTIMIZED.yml up -d qdrant
sleep 10
curl -X PUT http://100.72.73.3:6333/collections/restore \
  -d @$BACKUP_DIR/qdrant-snapshot.json

# Restore configurations
tar -xzf $BACKUP_DIR/configs.tar.gz -C /

# Start all services
./deploy.sh production

# Verify recovery
./scripts/health-check-all.sh
```

---

## 📈 Monitoring and Alerting

### Key Metrics to Monitor

```yaml
Critical_Metrics:
  GPU:
    utilization: "> 90% for 5 minutes"
    memory: "> 95% used"
    temperature: "> 85°C"

  API:
    latency_p99: "> 5 seconds"
    error_rate: "> 1%"
    throughput: "< 10 req/s for 10 minutes"

  System:
    cpu_usage: "> 90% for 10 minutes"
    memory_available: "< 2GB"
    disk_usage: "> 90%"

  Database:
    connections: "> 180"
    replication_lag: "> 10 seconds"
    transaction_time: "> 2 seconds"
```

### Alert Response Procedures

```bash
# GPU Temperature Alert
if [ $(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader) -gt 85 ]; then
    # Reduce power limit
    sudo nvidia-smi -pl 300

    # Reduce batch size
    docker exec starlord-vllm python -c "
    import yaml
    config = yaml.safe_load(open('/config/vllm.yaml'))
    config['batch_size'] = 4
    yaml.dump(config, open('/config/vllm.yaml', 'w'))
    "

    # Alert team
    curl -X POST https://hooks.slack.com/services/YOUR/WEBHOOK \
      -d '{"text":"⚠️ GPU Temperature Alert: Throttling initiated"}'
fi
```

---

## 📝 Maintenance Windows

### Scheduled Maintenance

**Weekly (Sunday 3-4 AM EST)**:
```bash
# 1. Announce maintenance
curl -X POST http://100.96.197.84:3000/api/v1/admin/announce \
  -d '{"message":"Scheduled maintenance in 5 minutes"}'

# 2. Enable maintenance mode
docker exec oracle-haproxy haproxy-cli "disable server backend/litellm"

# 3. Perform updates
docker-compose pull
docker-compose up -d --no-deps --build

# 4. Run health checks
./scripts/post-maintenance-validation.sh

# 5. Disable maintenance mode
docker exec oracle-haproxy haproxy-cli "enable server backend/litellm"
```

### Emergency Maintenance

```bash
# Immediate action required
./scripts/emergency-maintenance.sh --reason "Critical security patch"

# This script will:
# 1. Enable read-only mode
# 2. Queue all requests
# 3. Perform critical updates
# 4. Validate changes
# 5. Resume normal operations
```

---

## 🔄 Scaling Procedures

### Horizontal Scaling

```bash
# Add new inference node
docker-compose -f deploy/05-new-inference-node.yml up -d

# Register with load balancer
docker exec oracle-haproxy haproxy-cli \
  "add server backend/vllm-new 100.72.73.4:8000 check"

# Verify load distribution
watch -n 1 'docker exec oracle-haproxy haproxy-cli "show stat" | grep backend'
```

### Vertical Scaling

```bash
# Increase container resources
docker update --cpus="8" --memory="16g" starlord-vllm

# Adjust model parameters
docker exec starlord-vllm python -c "
config = {
    'max_batch_size': 32,
    'max_context_length': 256000,
    'gpu_memory_fraction': 0.95
}
import json
json.dump(config, open('/config/scaling.json', 'w'))
"
```

---

## 📞 Escalation Matrix

### Severity Levels

| Level | Description | Response Time | Escalation |
|-------|-------------|---------------|------------|
| **P1** | Complete outage | 15 minutes | Immediate page |
| **P2** | Degraded performance | 1 hour | Team notification |
| **P3** | Minor issues | 4 hours | Email alert |
| **P4** | Improvements | Next business day | Ticket |

### Contact Chain

```yaml
Primary_Oncall:
  name: "DevOps Engineer"
  phone: "+1-XXX-XXX-XXXX"
  email: "oncall@example.com"

Secondary_Oncall:
  name: "Senior SRE"
  phone: "+1-XXX-XXX-XXXX"
  email: "sre@example.com"

Management:
  name: "Engineering Manager"
  phone: "+1-XXX-XXX-XXXX"
  email: "manager@example.com"
```

---

## 🛡️ Compliance and Auditing

### Daily Compliance Check

```bash
#!/bin/bash
# Compliance verification script

echo "=== Daily Compliance Check ==="

# Check encryption
docker exec oracle-postgres psql -U postgres -c "SHOW ssl;" | grep on

# Check access logs
docker logs oracle-haproxy --since 24h | grep -c "200 OK"

# Check API key usage
docker exec oracle-vault vault audit list

# Generate compliance report
python scripts/generate_compliance_report.py > /reports/compliance_$(date +%Y%m%d).pdf
```

---

## 📚 Reference Documentation

- [Deployment Plan](../DEPLOYMENT_PLAN_FINAL.md)
- [Architecture Guide](ARCHITECTURE.md)
- [API Documentation](API_DOCUMENTATION.md)
- [Security Configuration](../config/security.yml)

---

**Document Version**: 1.0.0
**Last Review**: September 23, 2025
**Next Review**: October 23, 2025

---

*For urgent support, contact the on-call engineer via PagerDuty*