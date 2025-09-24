# AI-SWARM-MIAMI-2025: Oracle ARM64 Deployment Checklist

**CRITICAL STATUS**: 🔴 **DO NOT DEPLOY** until ARM compatibility verified and security issues resolved

## Pre-Deployment Requirements

### 🚨 IMMEDIATE ACTIONS (Block Deployment)

#### 1. Security Crisis Resolution
- [ ] **CRITICAL**: Rotate exposed OpenRouter API key immediately
- [ ] **CRITICAL**: Rotate both Gemini API keys immediately  
- [ ] **CRITICAL**: Remove all API keys from repository
- [ ] **CRITICAL**: Implement HashiCorp Vault or AWS Secrets Manager
- [ ] **HIGH**: Enable HTTPS/TLS for all services
- [ ] **HIGH**: Configure network segmentation and firewall rules

#### 2. ARM64 Compatibility Validation
- [ ] **CRITICAL**: Run ARM compatibility test script: `./scripts/test-arm-compatibility.sh`
- [ ] **CRITICAL**: Test LiteLLM ARM64 compatibility: `docker pull --platform linux/arm64 ghcr.io/berriai/litellm:main-latest`
- [ ] **CRITICAL**: Test Open WebUI ARM64 compatibility: `docker pull --platform linux/arm64 ghcr.io/open-webui/open-webui:main`
- [ ] **HIGH**: Test Pipelines ARM64 compatibility: `docker pull --platform linux/arm64 ghcr.io/open-webui/pipelines:main`
- [ ] **MEDIUM**: Prepare CPU-only alternatives if GPU services fail on ARM64

#### 3. Infrastructure Validation
- [ ] **HIGH**: Run infrastructure validation: `./deploy/00-infrastructure-validation.sh`
- [ ] **HIGH**: Verify Oracle node (100.96.197.84) connectivity and specs
- [ ] **HIGH**: Confirm Docker and Docker Compose installed on Oracle
- [ ] **MEDIUM**: Test Tailscale mesh connectivity between nodes

## Deployment Strategy Options

### Option A: ARM-Compatible Deployment (Recommended if tests pass)
```bash
# After ARM compatibility confirmed
cp deploy/01-deploy-oracle-ARM-FIXED.yml deploy/01-deploy-oracle.yml
docker-compose -f deploy/01-deploy-oracle.yml up -d
```

### Option B: Oracle Node Alternative Services (If compatibility fails)
```bash
# Deploy minimal compatible services only
docker-compose -f deploy/arm64-deployment-ready.yml up -d
```

### Option C: Skip Oracle, Use Railway Only (Fallback)
```bash
# Deploy overflow capacity to Railway instead
docker-compose -f deploy/04-railway-services.yml up -d
```

## Testing Procedures

### ARM64 Compatibility Testing
```bash
# Make executable and run
chmod +x scripts/test-arm-compatibility.sh
./scripts/test-arm-compatibility.sh

# Review results in terminal output
# Check generated arm64-deployment-ready.yml
```

### Security Testing
```bash
# Check for exposed secrets
grep -r "sk-" . --exclude-dir=.git
grep -r "AIzaSy" . --exclude-dir=.git

# Test HTTPS enforcement
curl -k https://100.96.197.84:3000/health

# Verify firewall rules
nmap -p 3000,4000,8000 100.96.197.84
```

### Service Health Testing
```bash
# Test critical endpoints
curl http://100.96.197.84:3000/health    # Open WebUI
curl http://100.96.197.84:4000/health    # LiteLLM
curl http://100.96.197.84:9100/metrics   # Monitoring

# Test API functionality
curl -X POST http://100.96.197.84:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{"model":"hermes-3-8b","messages":[{"role":"user","content":"test"}]}'
```

## Monitoring Setup

### Required Monitoring Stack
```yaml
Monitoring_Components:
  Metrics: "Prometheus + Grafana"
  Logs: "Docker logs centralization" 
  Health: "Custom health check endpoints"
  Security: "API key usage monitoring"
  
Dashboards_Needed:
  - ARM CPU/Memory utilization
  - API gateway performance
  - Service availability
  - Security events
  - Cost tracking
```

### Implementation
```bash
# Deploy monitoring stack
docker-compose -f monitoring/prometheus-grafana.yml up -d

# Configure dashboards
cp config/grafana-dashboards/* /var/lib/grafana/dashboards/

# Set up alerts
cp config/alertmanager.yml /etc/alertmanager/
```

## Backup and Recovery

### Pre-Deployment Backup
```bash
# Backup current working configuration
tar -czf ai-swarm-backup-$(date +%Y%m%d).tar.gz \
  deploy/ config/ scripts/ .env

# Store securely offsite
rsync ai-swarm-backup-*.tar.gz backup-server:/backups/
```

### Recovery Procedures
```bash
# Rollback procedure
docker-compose down
docker-compose -f deploy/rollback-config.yml up -d

# Database recovery
docker exec oracle-postgres pg_restore -d litellm /backup/latest.dump

# Service restart sequence
docker-compose restart postgres redis litellm open-webui
```

## Performance Optimization

### ARM64 Specific Optimizations
```yaml
ARM_Optimizations:
  CPU_Affinity: "Pin services to specific cores"
  Memory_Limits: "Set appropriate limits for ARM64"
  Swap_Configuration: "Optimize for ARM architecture"
  Thermal_Management: "Monitor ARM CPU temperatures"
```

### Resource Allocation
```yaml
Oracle_ARM_Resources:
  PostgreSQL: "2GB RAM, 2 CPU cores"
  Redis: "1GB RAM, 1 CPU core" 
  LiteLLM: "4GB RAM, 4 CPU cores"
  WebUI: "2GB RAM, 2 CPU cores"
  Monitoring: "1GB RAM, 1 CPU core"
```

## CI/CD Pipeline Setup

### GitHub Actions Workflow
```yaml
name: AI-SWARM ARM64 Deployment
on: [push, pull_request]
jobs:
  arm64-compatibility:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v2
      - name: Test ARM64 compatibility
        run: ./scripts/test-arm-compatibility.sh
  
  security-scan:
    runs-on: ubuntu-latest  
    steps:
      - uses: actions/checkout@v3
      - name: Scan for secrets
        uses: trufflesecurity/trufflehog@main
      
  deploy:
    needs: [arm64-compatibility, security-scan]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to Oracle
        run: ./deploy.sh production
```

## Troubleshooting Guide

### Common ARM64 Issues
```yaml
Issue_Resolution:
  "exec format error":
    cause: "x86_64 image on ARM64"
    fix: "Add platform: linux/arm64 or find ARM-compatible image"
    
  "no matching manifest":
    cause: "No ARM64 build available"
    fix: "Build custom ARM64 image or find alternative"
    
  "qemu: uncaught target signal":
    cause: "Binary compatibility issue"
    fix: "Use native ARM64 compiled binary"
    
  Performance_Issues:
    cause: "x86_64 emulation overhead"  
    fix: "Ensure native ARM64 images only"
```

### Service Debugging
```bash
# Check service logs
docker-compose logs -f litellm
docker-compose logs -f open-webui

# Inspect container architecture
docker inspect oracle-litellm | grep Architecture

# Monitor resource usage
docker stats oracle-postgres oracle-redis oracle-litellm

# Test network connectivity
docker exec oracle-litellm ping postgres
docker exec oracle-litellm curl redis:6379
```

## Success Criteria

### Deployment Success Indicators
- [ ] All services start successfully on ARM64
- [ ] Health checks pass for all critical services
- [ ] API endpoints respond correctly
- [ ] No emulation overhead detected
- [ ] Security scans pass
- [ ] Performance within acceptable limits

### Performance Benchmarks
```yaml
Performance_Targets:
  API_Response_Time: "< 2 seconds"
  Service_Startup: "< 60 seconds" 
  CPU_Usage: "< 70% sustained"
  Memory_Usage: "< 80% allocated"
  Network_Latency: "< 50ms inter-node"
```

## Post-Deployment Tasks

### Immediate (First 24 Hours)
- [ ] Monitor service stability and performance
- [ ] Verify all health checks are passing
- [ ] Test end-to-end AI inference pipeline
- [ ] Configure monitoring alerts and dashboards
- [ ] Document any ARM64-specific configuration changes

### Short Term (First Week)
- [ ] Conduct load testing on ARM64 infrastructure
- [ ] Optimize resource allocation based on usage patterns
- [ ] Implement automated backup procedures
- [ ] Complete security audit and penetration testing
- [ ] Train team on ARM64-specific troubleshooting

### Long Term (First Month)
- [ ] Evaluate ARM64 performance vs x86_64 baseline
- [ ] Optimize costs and resource utilization  
- [ ] Implement advanced monitoring and analytics
- [ ] Document lessons learned and best practices
- [ ] Plan for scaling and additional ARM64 deployments

---

## Contact and Escalation

**Deployment Team**: DevOps Engineering  
**Escalation Path**: Infrastructure → Security → Management  
**Emergency Contact**: System Administrator  

**Decision Authority**: 
- Deploy/No-Deploy: Technical Lead
- Security Issues: Security Officer  
- Infrastructure Changes: DevOps Lead

---

*This checklist must be completed before Oracle ARM64 deployment proceeds.*