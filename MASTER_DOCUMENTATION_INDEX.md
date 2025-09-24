# 📖 AI-SWARM-MIAMI-2025 Master Documentation Index

> **The Complete Knowledge Base and Navigation System**

---

## 🗺️ Documentation Map

### 🆕 Quick Start Resources
- **[🚀 README.md](README.md)** - Project overview and quick start guide
- **[📋 Quick Reference Cards](QUICK_REFERENCE_CARDS.md)** - Essential commands and troubleshooting
- **[🏗️ Project Index](PROJECT_INDEX.md)** - Complete file inventory and structure

### 📚 Core Documentation
- **[🏛️ Architecture Design](docs/ARCHITECTURE.md)** - System architecture and design decisions
- **[🌐 API Documentation](docs/API_DOCUMENTATION.md)** - API endpoints and integration guides
- **[📓 Operational Runbook](docs/OPERATIONAL_RUNBOOK.md)** - Operations and maintenance procedures

### 🕸️ Knowledge Graphs & Visualizations
- **[🕸️ Knowledge Graph](KNOWLEDGE_GRAPH.md)** - System relationships and data flows
- **[🌐 Network Topology](#network-topology)** - Network architecture diagrams
- **[📊 Performance Flows](#performance-flows)** - Request processing pipelines

### 🔧 Deployment & Configuration
- **[📦 Deployment Plan](DEPLOYMENT_PLAN_FINAL.md)** - Step-by-step deployment guide
- **[✅ Deployment Checklist](DEPLOYMENT_CHECKLIST.md)** - Pre-flight validation checklist
- **[🔐 Security Configuration](config/security.yml)** - Security policies and settings
- **[🎐 LiteLLM Config](config/litellm.yaml)** - Model routing configuration

### 📊 Analysis & Reports
- **[📊 Strategic Synthesis](claudedocs/AI-SWARM-MIAMI-2025_STRATEGIC_SYNTHESIS.md)** - Strategic analysis
- **[🏎️ Performance Analysis](claudedocs/ARCHITECTURE_PERFORMANCE_ANALYSIS.md)** - Performance optimization report
- **[🔒 Security Audit](SECURITY_AUDIT_REPORT.md)** - Security assessment and recommendations
- **[📊 Code Analysis](claudedocs/COMPREHENSIVE_CODE_ANALYSIS_REPORT.md)** - Codebase analysis

### 🔨 Scripts & Automation
- **[main.py](main.py)** - Main orchestrator with auto-scaling
- **[deploy.sh](deploy.sh)** - Automated deployment script
- **[key_rotation.py](scripts/key_rotation.py)** - API key rotation automation
- **[secure_keys.sh](scripts/secure_keys.sh)** - Key security script

---

## 📋 Index by Category

### 🏯 Infrastructure & Deployment

| Document | Purpose | Last Updated |
|----------|---------|-------------|
| [01-oracle-ARM.yml](deploy/01-oracle-ARM.yml) | Oracle node deployment (ARM optimized) | Active |
| [02-starlord-OPTIMIZED.yml](deploy/02-starlord-OPTIMIZED.yml) | Starlord GPU node deployment | Active |
| [03-thanos-SECURED.yml](deploy/03-thanos-SECURED.yml) | Thanos worker node deployment | Active |
| [docker-compose.railway.yml](docker-compose.railway.yml) | Railway cloud deployment | Active |
| [00-infrastructure-validation.sh](deploy/00-infrastructure-validation.sh) | Pre-deployment validation | Active |

### 🔐 Security & Secrets

| Document | Purpose | Classification |
|----------|---------|----------------|
| [security.yml](config/security.yml) | Main security configuration | CRITICAL |
| [api-key-security.yml](config/api-key-security.yml) | API key management | CRITICAL |
| [vault/config.hcl](config/vault/config.hcl) | Vault configuration | SENSITIVE |
| [secrets-management.sh](deploy/secrets-management.sh) | Secret deployment | SENSITIVE |

### 🎮 Model & AI Configuration

| Document | Purpose | Models |
|----------|---------|--------|
| [litellm.yaml](config/litellm.yaml) | LiteLLM routing | Gemini, OpenRouter |
| [vLLM Config](#vllm-configuration) | Local inference settings | Llama 3.2 Dark |
| [Model Routing](#model-routing) | Decision tree for model selection | All models |

### 📊 Monitoring & Observability

| Document | Purpose | Access |
|----------|---------|--------|
| [prometheus.yml](config/prometheus.yml) | Metrics collection | :9090 |
| [alert.rules.yml](config/alert.rules.yml) | Alert definitions | AlertManager |
| [Grafana Dashboards](#grafana) | Visualization | :3001 |
| [Health Checks](#health-checks) | Service monitoring | Various |

### 📝 Development & Testing

| Document | Purpose | Language |
|----------|---------|----------|
| [main.py](main.py) | Orchestrator | Python |
| [cpu_inference_server.py](scripts/cpu_inference_server.py) | CPU inference | Python |
| [test-arm-compatibility.sh](scripts/test-arm-compatibility.sh) | ARM testing | Bash |
| [ci.yml](.github/workflows/ci.yml) | CI/CD pipeline | GitHub Actions |

---

## 🔍 Search Index

### By Service

```yaml
Open_WebUI:
  - Files: [deploy/01-oracle-ARM.yml, docker-compose.railway.yml]
  - Port: 3000
  - Node: Oracle
  - Docs: [README.md, API_DOCUMENTATION.md]

LiteLLM:
  - Files: [config/litellm.yaml, deploy/01-oracle-ARM.yml]
  - Port: 4000
  - Node: Oracle
  - Docs: [API_DOCUMENTATION.md, litellm.yaml]

vLLM:
  - Files: [deploy/02-starlord-OPTIMIZED.yml]
  - Port: 8000
  - Node: Starlord
  - GPU: RTX 4090

Qdrant:
  - Files: [deploy/02-starlord-OPTIMIZED.yml]
  - Port: 6333
  - Node: Starlord
  - Type: Vector DB

SillyTavern:
  - Files: [deploy/03-thanos-SECURED.yml]
  - Port: 8080
  - Node: Thanos
  - Purpose: Chat UI

GPT_Researcher:
  - Files: [deploy/03-thanos-SECURED.yml]
  - Port: 8001
  - Node: Thanos
  - Purpose: Autonomous research
```

### By Node

```yaml
Oracle_Node:
  IP: 100.96.197.84
  Services: [Open WebUI, LiteLLM, PostgreSQL, Redis, Vault]
  Deploy: deploy/01-oracle-ARM.yml
  Hardware: ARM A1, 22GB RAM
  
Starlord_Node:
  IP: 100.72.73.3
  Services: [vLLM, Qdrant, Model Cache]
  Deploy: deploy/02-starlord-OPTIMIZED.yml
  Hardware: RTX 4090, Ryzen 9 7950X3D
  
Thanos_Node:
  IP: 100.122.12.54
  Services: [SillyTavern, GPT Researcher, RAG]
  Deploy: deploy/03-thanos-SECURED.yml
  Hardware: RTX 3080, Ryzen 9 5900X
```

### By Configuration Type

```yaml
API_Keys:
  - config/api-key-security.yml
  - config/vault/config.hcl
  - scripts/key_rotation.py
  - scripts/secure_keys.sh

Networking:
  - config/haproxy.cfg
  - Tailscale configuration
  - Firewall rules in security.yml

Monitoring:
  - config/prometheus.yml
  - config/alert.rules.yml
  - monitoring/ directory

Models:
  - config/litellm.yaml
  - vLLM configuration in deploy files
  - Model routing logic
```

---

## 🎯 Quick Navigation

### Essential Commands

```bash
# Deploy everything
./deploy.sh production

# Check status
docker-compose ps
tailscale status

# View logs
docker logs -f <service>

# Access UIs
open http://100.96.197.84:3000  # Open WebUI
open http://100.96.197.84:3001  # Grafana
open http://100.122.12.54:8080  # SillyTavern
```

### Troubleshooting Paths

1. **Service Issues** → [Quick Reference Cards](QUICK_REFERENCE_CARDS.md#troubleshooting-card)
2. **Network Problems** → [Knowledge Graph](KNOWLEDGE_GRAPH.md#network-topology)
3. **Performance** → [Project Index](PROJECT_INDEX.md#performance-card)
4. **Security** → [Security Config](config/security.yml)
5. **Deployment** → [Deployment Checklist](DEPLOYMENT_CHECKLIST.md)

### Configuration Quick Links

- **Change Models**: Edit [litellm.yaml](config/litellm.yaml)
- **Update Security**: Edit [security.yml](config/security.yml)
- **Modify Alerts**: Edit [alert.rules.yml](config/alert.rules.yml)
- **Scale Services**: Edit deployment YAMLs in [deploy/](deploy/)

---

## 📈 Documentation Standards

### File Naming Convention

```
Type_Purpose_Version.extension

Examples:
- deploy/01-oracle-ARM.yml
- config/security.yml
- scripts/key_rotation.py
- docs/ARCHITECTURE.md
```

### Documentation Structure

```markdown
# Title
> Brief description

## Overview
Context and purpose

## Configuration
Settings and parameters

## Usage
Examples and commands

## Troubleshooting
Common issues and solutions

## References
Related documents and links
```

### Version Control

```yaml
Versioning:
  Format: MAJOR.MINOR.PATCH
  Example: 1.0.0
  
Changelog:
  Location: CHANGELOG.md
  Format: Keep a Changelog
  
Tags:
  Format: v1.0.0
  Branch: main
```

---

## 📡 External Resources

### Official Documentation

- **[vLLM Docs](https://docs.vllm.ai/)** - High-performance inference
- **[LiteLLM Docs](https://docs.litellm.ai/)** - Universal LLM gateway
- **[Qdrant Docs](https://qdrant.tech/documentation/)** - Vector database
- **[Open WebUI Docs](https://github.com/open-webui/open-webui)** - Web interface
- **[SillyTavern Wiki](https://github.com/SillyTavern/SillyTavern/wiki)** - Chat interface

### Community Resources

- **GitHub Repository**: [OrcaQueen](https://github.com/aahmed954/OrcaQueen)
- **Issue Tracker**: [GitHub Issues](https://github.com/aahmed954/OrcaQueen/issues)
- **Discord**: [Project Discord](#)
- **Wiki**: [Project Wiki](#)

### Vendor Support

- **OpenRouter**: [OpenRouter AI](https://openrouter.ai/)
- **Google AI**: [Google AI Studio](https://makersuite.google.com/)
- **Tailscale**: [Tailscale Support](https://tailscale.com/contact/support)

---

## 📅 Maintenance Schedule

### Daily
- Monitor service health
- Check error logs
- Review resource usage

### Weekly
- Rotate API keys
- Update Docker images
- Review security logs
- Test backups

### Monthly
- Security audit
- Performance review
- Cost analysis
- Capacity planning

### Quarterly
- Architecture review
- Dependency updates
- Documentation review
- Disaster recovery test

---

## 🏁 Project Milestones

| Milestone | Status | Date | Description |
|-----------|--------|------|-------------|
| Initial Deploy | ✅ Complete | 2025-01 | 3-node architecture deployed |
| ARM Optimization | ✅ Complete | 2025-01 | Oracle ARM node optimized |
| Security Hardening | ✅ Complete | 2025-01 | mTLS, Vault integration |
| Auto-scaling | 🔄 In Progress | 2025-02 | Dynamic batch size adjustment |
| RAG Pipeline | 📅 Planned | 2025-02 | 60TB Google Drive integration |
| Multi-region | 📅 Planned | 2025-03 | Geographic distribution |

---

## 🎆 Success Metrics

```yaml
Performance:
  Throughput: 110+ req/sec
  Latency: <100ms first token
  Uptime: 99.9%
  
Cost:
  Reduction: 80% vs cloud
  Budget: $25/month API costs
  
Scale:
  Context: 128K tokens
  Models: 10+ supported
  Storage: 60TB available
  
Security:
  Encryption: 100% coverage
  Key Rotation: Monthly
  Audit: Full logging
```

---

## 📝 Notes & Best Practices

1. **Always check Tailscale status** before troubleshooting network issues
2. **Monitor GPU temperature** on Starlord and Thanos nodes
3. **Use Vault for all secrets** - never hardcode API keys
4. **Backup before updates** - especially database and vector store
5. **Test in staging** - Use docker-compose.dev.yml first
6. **Document changes** - Update relevant docs when modifying configs
7. **Follow security policies** - Review security.yml regularly
8. **Monitor costs** - Track API usage through LiteLLM budgets

---

*Master Documentation Index v1.0.0 - AI-SWARM-MIAMI-2025*
*Generated: 2025-01-23*
*Maintainer: AI Swarm Team*