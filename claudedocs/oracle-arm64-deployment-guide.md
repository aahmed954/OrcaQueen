# Oracle Cloud ARM64 Deployment Guide: Open WebUI Pipelines

## Quick Start

Your existing Oracle ARM deployment is **already configured correctly** for Open WebUI Pipelines. This guide provides testing steps and troubleshooting for ARM64 compatibility.

## Deployment Status: ✅ READY

### Current Configuration Analysis
Your `/deploy/01-oracle-ARM.yml` includes proper ARM64 Pipelines configuration:

```yaml
pipelines:
  image: ghcr.io/open-webui/pipelines:main
  platform: linux/arm64                    # ✅ Explicit ARM64
  container_name: oracle-pipelines
  ports:
    - "100.96.197.84:9099:9099"            # ✅ Correct port mapping
  environment:
    PIPELINES_OPENAI_API_BASE_URL: http://litellm:4000/v1  # ✅ LiteLLM integration
    NODE_ENV: production                   # ✅ ARM64 optimization
    PIP_NO_CACHE_DIR: 1                    # ✅ Memory optimization
```

## Testing Instructions

### 1. Deploy Current Configuration
```bash
cd /path/to/OrcaQueen
docker-compose -f deploy/01-oracle-ARM.yml up -d pipelines
```

### 2. Test ARM64 Compatibility (Optional)
```bash
# Run comprehensive ARM64 test
./scripts/test-arm64-pipelines.sh

# Quick health check
curl -f http://100.96.197.84:9099/health
```

### 3. Configure Open WebUI Integration
Navigate to Admin Panel > Settings > Connections:
- **API URL**: `http://100.96.197.84:9099`
- **API Key**: Your `LITELLM_MASTER_KEY` value

## Known ARM64 Issues & Solutions

### Issue 1: Container Restart Loop
**Symptoms**: Container repeatedly restarts, never becomes healthy
**Solution**: Your config already includes fixes:
```yaml
environment:
  NODE_ENV: production      # Prevents dev-mode issues
  PIP_NO_CACHE_DIR: 1      # Reduces memory pressure
platform: linux/arm64     # Explicit architecture
```

### Issue 2: PyTorch/ML Library Failures
**Symptoms**: "Illegal instruction" or torch-related errors
**Solution**: Add CPU-only torch environment:
```yaml
environment:
  TORCH_DEVICE: cpu
  OMP_NUM_THREADS: 2
```

### Issue 3: Memory Issues on ARM64
**Symptoms**: OOM kills, slow performance
**Solution**: Resource limits (optional):
```yaml
deploy:
  resources:
    limits:
      memory: 1G
    reservations:
      memory: 256M
```

## Fallback Options

### Option 1: Stable Version (Recommended if issues occur)
If you encounter ARM64 compatibility issues:
```yaml
pipelines:
  image: ghcr.io/open-webui/pipelines:v0.5.8  # Stable ARM64 version
  # ... rest unchanged
```

### Option 2: Alternative Pipeline Solutions

#### AnythingLLM (Enterprise-grade ARM64)
```yaml
anythingllm:
  image: mintplexlabs/anythingllm:latest
  platform: linux/arm64
  ports:
    - "100.96.197.84:3001:3001"
  volumes:
    - anythingllm_data:/app/server/storage
```

#### Custom Lightweight Pipeline
```yaml
custom-pipeline:
  image: python:3.11-slim
  platform: linux/arm64
  ports:
    - "100.96.197.84:9099:9099"
  command: |
    sh -c "
      pip install flask openai requests &&
      python /app/pipeline-server.py
    "
```

## Performance Optimization for Oracle Cloud ARM

### 1. CPU Optimization
```yaml
environment:
  OMP_NUM_THREADS: 2           # Match ARM CPU cores
  TORCH_NUM_THREADS: 2         # PyTorch thread limit
  MKL_NUM_THREADS: 2          # Intel MKL threads
```

### 2. Memory Optimization
```yaml
environment:
  MALLOC_TRIM_THRESHOLD: 128000  # Aggressive memory trimming
  PYTHONHASHSEED: 0             # Consistent hashing
  PYTHONUNBUFFERED: 1           # Immediate stdout
```

### 3. Network Optimization
```yaml
ports:
  - "100.96.197.84:9099:9099"    # Direct IP binding
extra_hosts:
  - "host.docker.internal:host-gateway"  # Docker networking fix
```

## Monitoring & Troubleshooting

### Health Checks
```bash
# Service health
curl -f http://100.96.197.84:9099/health

# Pipeline list
curl -f http://100.96.197.84:9099/pipelines

# Container status
docker ps | grep pipelines

# Resource usage
docker stats oracle-pipelines
```

### Common Log Patterns
```bash
# Check for ARM64 issues
docker logs oracle-pipelines | grep -i "arch\|illegal\|qemu"

# Monitor startup
docker logs oracle-pipelines --tail 50 -f

# Memory warnings
docker logs oracle-pipelines | grep -i "memory\|oom"
```

## Integration Verification

### 1. LiteLLM Connection
```bash
# Test backend connection
curl -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
     http://100.96.197.84:4000/v1/models
```

### 2. Open WebUI Connection
```bash
# Test UI health
curl -f http://100.96.197.84:3000/health

# Check pipeline integration
curl -f http://100.96.197.84:3000/api/v1/pipelines
```

## Security Considerations

Your configuration includes proper ARM64 security:
```yaml
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
user: "1000:1000"  # Non-root execution
```

## Production Deployment Checklist

- [ ] Deploy with existing Oracle ARM configuration
- [ ] Verify health endpoints respond
- [ ] Test pipeline installation/upload
- [ ] Configure Open WebUI integration
- [ ] Monitor resource usage for 24 hours
- [ ] Set up log monitoring for ARM64 issues
- [ ] Document any custom pipelines installed
- [ ] Test failover to stable version if needed

## Support Resources

- **ARM64 Issues**: Use stable v0.5.8 image
- **Performance**: Monitor with `docker stats`
- **Integration**: Check LiteLLM backend connectivity
- **Alternatives**: AnythingLLM or LobeChat for ARM64
- **Testing**: Run provided test script before production

## Conclusion

Your Oracle Cloud ARM64 deployment is properly configured for Open WebUI Pipelines. The setup should work out-of-the-box with the optimizations already in place. If you encounter the known ARM64 stability issues, use the stable v0.5.8 image or one of the lightweight alternatives provided.