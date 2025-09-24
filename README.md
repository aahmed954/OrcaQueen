# AI-SWARM-MIAMI-2025 🚀

A bulletproof 3-node distributed AI swarm architecture featuring uncensored models, autonomous research capabilities, and 80% cost optimization.

## 🎯 Key Features

- **Uncensored AI Models**: LLaMA Dark Champion, Dolphin 3, Hermes 3
- **Distributed Architecture**: 3-node swarm with specialized roles
- **High Performance**: RTX 4090 + RTX 3080 GPU acceleration
- **Cost Optimized**: 80% reduction through intelligent routing
- **Research Capable**: GPT Researcher with web search integration
- **60TB Storage**: Google Drive automation for RAG pipeline

## 📊 Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                  Oracle ARM Node                     │
│              (100.96.197.84 - Cloud)                 │
│   • Open WebUI (Port 3000)                          │
│   • LiteLLM Gateway (Port 4000)                     │
│   • PostgreSQL + Redis                              │
│   • Cost Optimizer                                  │
└─────────────────────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        │                                  │
┌───────▼────────┐              ┌─────────▼────────┐
│ Starlord Node  │              │   Thanos Node    │
│  (100.72.73.3) │              │ (100.122.12.54)  │
│                │              │                  │
│ • RTX 4090 24GB│              │ • RTX 3080 10GB  │
│ • vLLM (8000)  │              │ • SillyTavern    │
│ • Qdrant (6333)│              │ • GPT Researcher │
│ • Model Cache  │              │ • RAG Pipeline   │
└────────────────┘              └──────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- Docker & Docker Compose installed on all nodes
- Tailscale network configured
- SSH access to all nodes
- API keys for OpenRouter, Gemini, Google Drive

### Deployment

1. **Clone the repository**:
```bash
git clone https://github.com/aahmed954/OrcaQueen.git
cd OrcaQueen
```

2. **Configure environment**:
```bash
cp .env.example .env
# Edit .env with your actual API keys and passwords
nano .env
```

3. **Run deployment**:
```bash
chmod +x deploy.sh
./deploy.sh production
```

4. **Access interfaces**:
- Open WebUI: http://100.96.197.84:3000
- SillyTavern: http://100.122.12.54:8080
- GPT Researcher: http://100.122.12.54:8001

## 🔧 Configuration

### Node Specifications

| Node | Hardware | Role | Services |
|------|----------|------|----------|
| Oracle | ARM A1, 22GB RAM | Orchestrator | Open WebUI, LiteLLM, PostgreSQL |
| Starlord | Ryzen 9 7950X3D, RTX 4090, 20GB RAM | Inference | vLLM, Qdrant, Model Cache |
| Thanos | Ryzen 9 5900X, RTX 3080, 61GB RAM | Worker | SillyTavern, GPT Researcher, RAG |

### Model Configuration

```yaml
Primary Models:
  - llama-3.2-dark-champion-abliterated-128k
  - dolphin-3-llama-3.1-70b
  - hermes-3-llama-3.1-405b

Free Tier:
  - deepseek-v3.1
  - grok-4-fast-free
  - gemini-2.5-flash-free
```

## 🛡️ Security

- Tailscale private mesh networking
- Vault for API key management and rotation (integrated in deployment)
- mTLS for internal services via HAProxy
- RBAC in LiteLLM for model access (admin/user roles)
- PostgreSQL with TLS encryption
- Redis with password protection
- Docker container isolation
- Non-root container execution
- Automated key rotation script (scripts/key_rotation.py)

## 📈 Performance

- **Target**: 110+ requests/second (optimized)
- **Latency**: <100ms first token
- **Context**: Up to 128K tokens
- **GPU Utilization**: 85% optimal (dedicated to primary vLLM)
- **Cost Reduction**: 80% through model cascading
- **Auto-scaling**: Dynamic batch size adjustment via main.py (8-32 range)
- **ARM Optimization**: ONNX Runtime for CPU inference (2x faster on ARM)

## 🔍 Monitoring

Access monitoring dashboards:
- Prometheus: http://100.96.197.84:9090
- AlertManager: http://100.96.197.84:9093 (GPU high, latency alerts)
- Grafana: http://100.96.197.84:3001
- Kibana: http://100.96.197.84:5601 (logs via ELK)
- GPU Metrics: http://100.72.73.3:9091
- Thermal Monitor: http://100.122.12.54:9092

## 🐛 Troubleshooting

### Common Issues

1. **vLLM not starting**: Check GPU memory, reduce batch size
2. **Network connectivity**: Verify Tailscale status with `tailscale status`
3. **Qdrant issues**: Ensure existing Qdrant on port 6333 is running
4. **Model loading slow**: Check network bandwidth, use model cache

### Logs

View service logs:
```bash
# Oracle node (ELK enabled)
ssh oracle1 "docker logs oracle-litellm"
# View in Kibana: http://100.96.197.84:5601

# Starlord node
docker logs starlord-vllm

# Thanos node
ssh thanos "docker logs thanos-sillytavern"
```

## 📚 Documentation

- [Architecture Design](docs/ARCHITECTURE.md)
- [Security Configuration](config/api-key-security.yml)
- [Deployment Scripts](deploy/)
- [CI/CD Workflow](.github/workflows/ci.yml)
- [Main Orchestrator](main.py)

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

## ⚠️ Disclaimer

This system includes uncensored AI models. Users are responsible for:
- Compliance with local regulations
- Ethical use of AI capabilities
- Content moderation as needed
- Data privacy and security

## 📄 License

MIT License - See LICENSE file for details

## 🔄 CI/CD & Automation

- GitHub Actions for multi-arch builds and tests
- Automated backups (daily Postgres/Qdrant)
- Auto-scaling for vLLM batch sizes

## 🙏 Acknowledgments

- SillyTavern team for the excellent interface
- vLLM team for high-performance inference
- Qdrant for vector database capabilities
- GPT Researcher for autonomous research

---

**Built with ❤️ in Miami, FL**

For issues or questions: [Open an Issue](https://github.com/aahmed954/OrcaQueen/issues)