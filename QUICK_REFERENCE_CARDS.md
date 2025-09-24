# 📋 AI-SWARM-MIAMI-2025 Quick Reference Cards

> **Fast access to critical operational information**

---

## 🚀 Deployment Card

```bash
# QUICK DEPLOY (All Nodes)
./deploy.sh production

# INDIVIDUAL NODE DEPLOY
ssh oracle1 "cd /opt/ai-swarm && docker-compose -f deploy/01-oracle-ARM.yml up -d"
docker-compose -f deploy/02-starlord-OPTIMIZED.yml up -d
ssh thanos "cd /opt/ai-swarm && docker-compose -f deploy/03-thanos-SECURED.yml up -d"

# EMERGENCY RESTART
docker-compose restart
docker-compose down && docker-compose up -d

# CLEAN DEPLOY
docker-compose down -v
docker system prune -af
./deploy.sh production
```

---

## 🌐 Network Card

```bash
# TAILSCALE NODES
Oracle:   100.96.197.84  (Cloud ARM)
Starlord: 100.72.73.3    (Local GPU)
Thanos:   100.122.12.54  (Local Worker)

# SERVICE PORTS
Open WebUI:      :3000   # Main interface
LiteLLM:         :4000   # API gateway
vLLM:            :8000   # Inference
Qdrant:          :6333   # Vector DB
SillyTavern:     :8080   # Chat UI
GPT Researcher:  :8001   # Research

# MONITORING PORTS
Prometheus:      :9090   # Metrics
Grafana:         :3001   # Dashboards
AlertManager:    :9093   # Alerts
```

---

## 🔧 Troubleshooting Card

```bash
# CHECK SERVICE HEALTH
curl http://100.96.197.84:3000/health   # Open WebUI
curl http://100.96.197.84:4000/health   # LiteLLM
curl http://100.72.73.3:8000/health     # vLLM

# VIEW LOGS
docker logs -f oracle-litellm --tail 100
docker logs -f starlord-vllm --tail 100
docker logs -f thanos-sillytavern --tail 100

# GPU STATUS
nvidia-smi                              # GPU info
watch -n 1 nvidia-smi                   # Monitor GPU

# NETWORK DEBUG
tailscale status                        # VPN status
ping 100.96.197.84                      # Test Oracle
netstat -tulpn | grep LISTEN            # Open ports

# CONTAINER STATUS
docker ps -a                            # All containers
docker stats                            # Resource usage
```

---

## 🎮 Model Configuration Card

```yaml
# PRIMARY MODELS (vLLM)
llama-3.2-dark-champion-abliterated-128k
  Context: 128K tokens
  Type: Uncensored
  Location: Starlord GPU

# FALLBACK MODELS (API)
google/gemini-2.5-pro
  Budget: $10/month
  Context: 2M tokens
  
google/gemini-2.5-flash
  Budget: $12/month
  Context: 1M tokens

# FREE TIER
deepseek-v3.1
grok-4-fast-free
gemini-2.5-flash-free

# ROUTING STRATEGY
Primary → vLLM (local)
Fallback → Gemini (on context overflow)
Emergency → Free tier models
```

---

## 🔑 API Keys Card

```bash
# KEY LOCATIONS
Vault: http://100.96.197.84:8200
Config: /config/api-key-security.yml

# KEY ROTATION
python scripts/key_rotation.py

# CHECK KEY STATUS
vault kv get secret/api-keys

# UPDATE KEYS
vault kv put secret/api-keys \
  openrouter=sk-or-v1-xxx \
  gemini=AIza-xxx

# ENVIRONMENT VARS
export OPENROUTER_API_KEY=sk-or-v1-xxx
export GOOGLE_API_KEY_1=AIza-xxx
export GOOGLE_API_KEY_2=AIza-xxx
```

---

## 📊 Performance Card

```bash
# vLLM OPTIMIZATION
Batch Size: 16 (auto-scale 8-32)
GPU Memory: 85% utilization
Max Tokens: 128K
Quantization: FP8 when available

# MONITORING URLS
Grafana: http://100.96.197.84:3001
Prometheus: http://100.96.197.84:9090
GPU Metrics: http://100.72.73.3:9091

# PERFORMANCE TUNING
# Increase batch size
docker exec starlord-vllm \
  vllm serve --max-batch-size 32

# Adjust GPU memory
docker exec starlord-vllm \
  vllm serve --gpu-memory-utilization 0.90

# Cache optimization
redis-cli CONFIG SET maxmemory 4gb
redis-cli CONFIG SET maxmemory-policy allkeys-lru
```

---

## 🛡️ Security Card

```bash
# FIREWALL STATUS
ufw status verbose

# SSL/TLS CHECK
openssl s_client -connect 100.96.197.84:5432

# API KEY AUDIT
grep -r "sk-" /config/ 2>/dev/null  # Should return nothing!

# CONTAINER SECURITY
docker exec oracle-litellm whoami    # Should not be root

# ACCESS LOGS
tail -f /var/log/auth.log
tail -f /logs/audit.log

# EMERGENCY LOCKDOWN
ufw --force enable
docker-compose stop
```

---

## 💾 Backup Card

```bash
# QUICK BACKUP
# PostgreSQL
docker exec oracle-postgres \
  pg_dump -U postgres > backup_$(date +%Y%m%d).sql

# Qdrant
curl -X POST http://100.72.73.3:6333/snapshots

# Redis
docker exec oracle-redis redis-cli BGSAVE

# RESTORE
# PostgreSQL
cat backup.sql | docker exec -i oracle-postgres \
  psql -U postgres

# Qdrant
curl -X PUT http://100.72.73.3:6333/collections/restore \
  -H "Content-Type: application/json" \
  -d @snapshot.json

# AUTOMATED BACKUP
crontab -e
0 3 * * * /opt/ai-swarm/scripts/backup.sh
```

---

## 🎯 Common Commands Card

```bash
# SERVICE CONTROL
docker-compose up -d              # Start all
docker-compose down               # Stop all
docker-compose restart <service>  # Restart one
docker-compose logs -f <service>  # View logs
docker-compose ps                 # Status

# TESTING
curl -X POST http://100.96.197.84:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-local-only" \
  -H "Content-Type: application/json" \
  -d '{"model":"google/gemini-2.5-flash","messages":[{"role":"user","content":"test"}]}'

# MONITORING
watch docker stats                # Resource usage
htop                             # System resources
iotop                            # Disk I/O
iftop                            # Network traffic

# CLEANUP
docker system prune -af          # Remove unused
docker volume prune -f           # Clean volumes
journalctl --vacuum-time=7d      # Clean logs
```

---

## 🆘 Emergency Contacts Card

```yaml
Services:
  GitHub Issues: https://github.com/aahmed954/OrcaQueen/issues
  Discord: [Project Discord]
  
Vendor Support:
  OpenRouter: support@openrouter.ai
  Tailscale: support@tailscale.com
  
Monitoring Alerts:
  Email: admin@example.com
  Webhook: Discord/Slack webhook URL

Key Paths:
  Logs: /var/log/ai-swarm/
  Configs: /opt/ai-swarm/config/
  Data: /var/lib/ai-swarm/
  Backups: /backups/ai-swarm/
```

---

## 📈 Scaling Card

```bash
# HORIZONTAL SCALING
# Add new vLLM instance
docker run -d \
  --gpus all \
  --name vllm-2 \
  -p 8001:8000 \
  vllm/vllm-openai:latest \
  --model llama-3.2-dark-champion \
  --tensor-parallel-size 1

# Update LiteLLM routing
model_list:
  - model_name: llama-local
    litellm_params:
      api_base:
        - http://100.72.73.3:8000
        - http://100.72.73.3:8001

# VERTICAL SCALING
# Increase container resources
docker update \
  --memory 32g \
  --cpus 8 \
  oracle-litellm

# AUTO-SCALING TRIGGERS
CPU > 80% for 5 minutes
Memory > 85% sustained
Queue depth > 100 requests
Latency > 500ms p95
```

---

## 📋 Maintenance Card

```bash
# WEEKLY MAINTENANCE
1. Check disk space: df -h
2. Review logs: journalctl -p err -S "7 days ago"
3. Update containers: docker-compose pull
4. Rotate keys: python scripts/key_rotation.py
5. Test backups: ./scripts/test-restore.sh

# MONTHLY MAINTENANCE
1. Security updates: apt update && apt upgrade
2. Docker cleanup: docker system prune -af
3. Performance review: Check Grafana trends
4. Cost analysis: Review API usage
5. Capacity planning: Check growth metrics

# UPDATE PROCEDURE
git pull origin main
docker-compose down
docker-compose pull
docker-compose up -d
docker-compose ps
```

---

*Quick Reference Cards - Keep accessible during operations*