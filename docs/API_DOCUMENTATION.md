# 🔌 AI-SWARM-MIAMI-2025 API Documentation

**Version**: 1.0.0
**Base URLs**:
- Oracle: `http://100.96.197.84`
- Starlord: `http://100.72.73.3`
- Thanos: `http://100.122.12.54`

---

## 📡 Service Endpoints

### 1. LiteLLM Gateway API

**Base URL**: `http://100.96.197.84:4000`
**Authentication**: Bearer Token

#### 1.1 Chat Completions

##### POST `/v1/chat/completions`

Create a chat completion using available models.

**Request Headers**:
```http
Content-Type: application/json
Authorization: Bearer YOUR_API_KEY
```

**Request Body**:
```json
{
  "model": "llama-3.2-dark-champion-abliterated-128k",
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful assistant."
    },
    {
      "role": "user",
      "content": "What is the capital of France?"
    }
  ],
  "temperature": 0.7,
  "max_tokens": 1000,
  "stream": false,
  "top_p": 0.9,
  "frequency_penalty": 0.0,
  "presence_penalty": 0.0
}
```

**Response** (200 OK):
```json
{
  "id": "chatcmpl-123",
  "object": "chat.completion",
  "created": 1677652288,
  "model": "llama-3.2-dark-champion-abliterated-128k",
  "system_fingerprint": "fp_123",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "The capital of France is Paris."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 20,
    "completion_tokens": 8,
    "total_tokens": 28
  }
}
```

**Error Responses**:
- `400 Bad Request`: Invalid request format
- `401 Unauthorized`: Invalid or missing API key
- `429 Too Many Requests`: Rate limit exceeded
- `500 Internal Server Error`: Server error

#### 1.2 Model Management

##### GET `/v1/models`

List available models.

**Response** (200 OK):
```json
{
  "object": "list",
  "data": [
    {
      "id": "llama-3.2-dark-champion-abliterated-128k",
      "object": "model",
      "created": 1677652288,
      "owned_by": "openrouter",
      "permission": [],
      "root": "llama-3.2-dark-champion",
      "parent": null
    },
    {
      "id": "dolphin-3-llama-3.1-70b",
      "object": "model",
      "created": 1677652288,
      "owned_by": "openrouter",
      "permission": [],
      "root": "dolphin-3",
      "parent": null
    }
  ]
}
```

##### GET `/v1/models/{model_id}`

Get details for a specific model.

**Response** (200 OK):
```json
{
  "id": "llama-3.2-dark-champion-abliterated-128k",
  "object": "model",
  "created": 1677652288,
  "owned_by": "openrouter",
  "context_window": 128000,
  "capabilities": {
    "vision": false,
    "function_calling": true,
    "streaming": true
  }
}
```

#### 1.3 Cost Tracking

##### GET `/cost/usage`

Get usage and cost information.

**Query Parameters**:
- `start_date`: ISO 8601 date string
- `end_date`: ISO 8601 date string
- `model`: Optional model filter

**Response** (200 OK):
```json
{
  "total_cost": 15.67,
  "total_tokens": 1567890,
  "by_model": {
    "llama-3.2-dark-champion-abliterated-128k": {
      "cost": 10.45,
      "tokens": 890123,
      "requests": 234
    },
    "gemini-2.5-flash-free": {
      "cost": 0,
      "tokens": 456789,
      "requests": 567
    }
  },
  "daily_breakdown": [
    {
      "date": "2025-09-23",
      "cost": 5.23,
      "tokens": 234567
    }
  ]
}
```

---

### 2. vLLM Inference API

**Base URL**: `http://100.72.73.3:8000`
**Authentication**: API Key

#### 2.1 Generate

##### POST `/generate`

Generate text completion.

**Request Body**:
```json
{
  "prompt": "The quick brown fox",
  "max_tokens": 100,
  "temperature": 0.8,
  "top_p": 0.95,
  "top_k": 40,
  "stop": ["\n"],
  "stream": false
}
```

**Response** (200 OK):
```json
{
  "text": " jumps over the lazy dog",
  "tokens": 7,
  "finish_reason": "stop",
  "model": "mixtral-8x7b-gptq"
}
```

#### 2.2 Health Check

##### GET `/health`

Check vLLM server health.

**Response** (200 OK):
```json
{
  "status": "healthy",
  "model_loaded": true,
  "gpu_memory_used": 18432,
  "gpu_memory_total": 24576,
  "batch_size": 16,
  "active_requests": 3
}
```

#### 2.3 Metrics

##### GET `/metrics`

Get Prometheus metrics.

**Response** (200 OK):
```text
# HELP vllm_request_latency Request latency in seconds
# TYPE vllm_request_latency histogram
vllm_request_latency_bucket{le="0.05"} 234
vllm_request_latency_bucket{le="0.1"} 456
vllm_request_latency_count 567
vllm_request_latency_sum 34.5

# HELP vllm_gpu_utilization GPU utilization percentage
# TYPE vllm_gpu_utilization gauge
vllm_gpu_utilization 85.3
```

---

### 3. Qdrant Vector Database API

**Base URL**: `http://100.72.73.3:6333`
**Authentication**: API Key (if configured)

#### 3.1 Collections

##### GET `/collections`

List all collections.

**Response** (200 OK):
```json
{
  "result": {
    "collections": [
      {
        "name": "documents",
        "vectors_count": 45678,
        "points_count": 12345,
        "config": {
          "vector_size": 1536,
          "distance": "Cosine"
        }
      }
    ]
  },
  "status": "ok",
  "time": 0.0023
}
```

##### PUT `/collections/{collection_name}`

Create a new collection.

**Request Body**:
```json
{
  "vectors": {
    "size": 1536,
    "distance": "Cosine"
  },
  "optimizers_config": {
    "default_segment_number": 5
  }
}
```

#### 3.2 Points (Vectors)

##### PUT `/collections/{collection_name}/points`

Upsert vectors into collection.

**Request Body**:
```json
{
  "points": [
    {
      "id": 1,
      "vector": [0.1, 0.2, 0.3, ...],
      "payload": {
        "text": "Sample document",
        "metadata": {
          "source": "file.pdf",
          "page": 1
        }
      }
    }
  ]
}
```

##### POST `/collections/{collection_name}/points/search`

Search for similar vectors.

**Request Body**:
```json
{
  "vector": [0.1, 0.2, 0.3, ...],
  "limit": 10,
  "with_payload": true,
  "filter": {
    "must": [
      {
        "key": "metadata.source",
        "match": {
          "value": "file.pdf"
        }
      }
    ]
  }
}
```

**Response** (200 OK):
```json
{
  "result": [
    {
      "id": 1,
      "score": 0.95,
      "payload": {
        "text": "Sample document",
        "metadata": {
          "source": "file.pdf",
          "page": 1
        }
      }
    }
  ],
  "status": "ok",
  "time": 0.012
}
```

---

### 4. Open WebUI API

**Base URL**: `http://100.96.197.84:3000`
**Authentication**: JWT Token

#### 4.1 Authentication

##### POST `/api/v1/auth/login`

Authenticate user and get JWT token.

**Request Body**:
```json
{
  "email": "user@example.com",
  "password": "secure_password"
}
```

**Response** (200 OK):
```json
{
  "token": "eyJhbGciOiJIUzI1NiIs...",
  "user": {
    "id": "user123",
    "email": "user@example.com",
    "role": "user"
  }
}
```

#### 4.2 Chat Sessions

##### GET `/api/v1/chats`

Get user's chat sessions.

**Request Headers**:
```http
Authorization: Bearer YOUR_JWT_TOKEN
```

**Response** (200 OK):
```json
{
  "chats": [
    {
      "id": "chat123",
      "title": "Project Discussion",
      "created_at": "2025-09-23T10:00:00Z",
      "updated_at": "2025-09-23T11:30:00Z",
      "model": "llama-3.2-dark-champion-abliterated-128k",
      "messages_count": 25
    }
  ]
}
```

##### POST `/api/v1/chats/{chat_id}/messages`

Send a message to a chat.

**Request Body**:
```json
{
  "content": "What is quantum computing?",
  "model": "llama-3.2-dark-champion-abliterated-128k"
}
```

---

### 5. GPT Researcher API

**Base URL**: `http://100.122.12.54:8001`
**Authentication**: API Key

#### 5.1 Research Tasks

##### POST `/api/research`

Create a new research task.

**Request Body**:
```json
{
  "query": "Latest developments in quantum computing",
  "report_type": "research_report",
  "max_iterations": 3,
  "agent": "researcher",
  "sources": ["academic", "news", "technical"]
}
```

**Response** (200 OK):
```json
{
  "task_id": "research123",
  "status": "processing",
  "estimated_time": 180
}
```

##### GET `/api/research/{task_id}`

Get research task status and results.

**Response** (200 OK):
```json
{
  "task_id": "research123",
  "status": "completed",
  "query": "Latest developments in quantum computing",
  "report": "# Research Report\n\n## Executive Summary\n...",
  "sources": [
    {
      "title": "Quantum Supremacy Achieved",
      "url": "https://example.com/article",
      "relevance": 0.95
    }
  ],
  "metadata": {
    "duration": 156,
    "sources_analyzed": 45,
    "tokens_used": 12345
  }
}
```

---

### 6. SillyTavern API

**Base URL**: `http://100.122.12.54:8080`
**Authentication**: Session-based

#### 6.1 Characters

##### GET `/api/characters`

Get available characters.

**Response** (200 OK):
```json
{
  "characters": [
    {
      "name": "Assistant",
      "avatar": "/avatars/assistant.png",
      "description": "Helpful AI assistant",
      "personality": "Professional and knowledgeable",
      "scenario": "General assistance"
    }
  ]
}
```

##### POST `/api/chat`

Send message to character.

**Request Body**:
```json
{
  "character": "Assistant",
  "message": "Hello, how are you?",
  "context": {
    "temperature": 0.8,
    "max_tokens": 500
  }
}
```

---

## 🔐 Authentication Methods

### 1. API Key Authentication

Used by: LiteLLM, vLLM, GPT Researcher

**Headers**:
```http
Authorization: Bearer YOUR_API_KEY
```

or

```http
X-API-Key: YOUR_API_KEY
```

### 2. JWT Authentication

Used by: Open WebUI

**Headers**:
```http
Authorization: Bearer YOUR_JWT_TOKEN
```

**Token Refresh**:
```http
POST /api/v1/auth/refresh
Authorization: Bearer YOUR_REFRESH_TOKEN
```

### 3. Session Authentication

Used by: SillyTavern

**Cookie**:
```http
Cookie: session_id=abc123def456
```

---

## 🔄 WebSocket Connections

### 1. Streaming Chat Responses

**Endpoint**: `ws://100.96.197.84:4000/v1/chat/stream`

**Connection**:
```javascript
const ws = new WebSocket('ws://100.96.197.84:4000/v1/chat/stream');

ws.send(JSON.stringify({
  type: 'auth',
  token: 'YOUR_API_KEY'
}));

ws.send(JSON.stringify({
  type: 'message',
  model: 'llama-3.2-dark-champion-abliterated-128k',
  messages: [{role: 'user', content: 'Hello'}]
}));

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  if (data.type === 'chunk') {
    console.log('Received chunk:', data.content);
  }
};
```

### 2. Real-time Metrics

**Endpoint**: `ws://100.96.197.84:9090/metrics/stream`

**Data Format**:
```json
{
  "timestamp": 1695457200,
  "metrics": {
    "gpu_utilization": 85.3,
    "requests_per_second": 45,
    "active_connections": 12,
    "latency_ms": 89
  }
}
```

---

## 📊 Rate Limiting

### Default Limits

| Service | Rate Limit | Window | Burst |
|---------|------------|--------|-------|
| LiteLLM | 100 req/min | 60s | 20 |
| vLLM | 50 req/min | 60s | 10 |
| Qdrant | 200 req/min | 60s | 50 |
| GPT Researcher | 10 req/hour | 3600s | 2 |

### Rate Limit Headers

**Response Headers**:
```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1695457260
```

---

## 🛠️ Error Handling

### Standard Error Response

```json
{
  "error": {
    "message": "Invalid request format",
    "type": "invalid_request_error",
    "param": "temperature",
    "code": "invalid_parameter"
  }
}
```

### Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `invalid_request_error` | 400 | Invalid request parameters |
| `authentication_error` | 401 | Invalid or missing authentication |
| `permission_error` | 403 | Insufficient permissions |
| `not_found_error` | 404 | Resource not found |
| `rate_limit_error` | 429 | Rate limit exceeded |
| `model_error` | 500 | Model inference error |
| `server_error` | 500 | Internal server error |
| `timeout_error` | 504 | Request timeout |

---

## 🔍 API Testing

### cURL Examples

#### Chat Completion
```bash
curl -X POST http://100.96.197.84:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{
    "model": "llama-3.2-dark-champion-abliterated-128k",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

#### Vector Search
```bash
curl -X POST http://100.72.73.3:6333/collections/documents/points/search \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.1, 0.2, 0.3],
    "limit": 5
  }'
```

#### Research Task
```bash
curl -X POST http://100.122.12.54:8001/api/research \
  -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_API_KEY" \
  -d '{
    "query": "AI safety research",
    "report_type": "research_report"
  }'
```

### Postman Collection

Import the following collection for API testing:

```json
{
  "info": {
    "name": "AI-SWARM-MIAMI-2025",
    "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
  },
  "item": [
    {
      "name": "LiteLLM",
      "item": [
        {
          "name": "Chat Completion",
          "request": {
            "method": "POST",
            "header": [
              {
                "key": "Authorization",
                "value": "Bearer {{api_key}}"
              }
            ],
            "url": "{{base_url}}/v1/chat/completions"
          }
        }
      ]
    }
  ],
  "variable": [
    {
      "key": "base_url",
      "value": "http://100.96.197.84:4000"
    },
    {
      "key": "api_key",
      "value": "YOUR_API_KEY"
    }
  ]
}
```

---

## 📚 SDKs and Client Libraries

### Python Client

```python
import requests

class AISwarmClient:
    def __init__(self, api_key, base_url="http://100.96.197.84:4000"):
        self.api_key = api_key
        self.base_url = base_url
        self.headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }

    def chat_completion(self, messages, model="llama-3.2-dark-champion-abliterated-128k"):
        response = requests.post(
            f"{self.base_url}/v1/chat/completions",
            headers=self.headers,
            json={
                "model": model,
                "messages": messages
            }
        )
        return response.json()

# Usage
client = AISwarmClient("YOUR_API_KEY")
response = client.chat_completion([
    {"role": "user", "content": "Hello!"}
])
print(response["choices"][0]["message"]["content"])
```

### JavaScript/TypeScript Client

```typescript
class AISwarmClient {
  private apiKey: string;
  private baseUrl: string;

  constructor(apiKey: string, baseUrl = "http://100.96.197.84:4000") {
    this.apiKey = apiKey;
    this.baseUrl = baseUrl;
  }

  async chatCompletion(messages: Message[], model = "llama-3.2-dark-champion-abliterated-128k") {
    const response = await fetch(`${this.baseUrl}/v1/chat/completions`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${this.apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ model, messages })
    });
    return response.json();
  }
}

// Usage
const client = new AISwarmClient("YOUR_API_KEY");
const response = await client.chatCompletion([
  { role: "user", content: "Hello!" }
]);
```

---

## 📖 API Versioning

### Current Version
- **v1**: Current stable version
- **v2**: Beta (not yet available)

### Version Headers
```http
X-API-Version: 1.0
```

### Deprecation Policy
- Minimum 3 months notice before deprecation
- Deprecated endpoints return `Deprecation` header
- Migration guides provided

---

## 🔗 Related Documentation

- [Architecture Documentation](ARCHITECTURE.md)
- [Deployment Guide](../DEPLOYMENT_PLAN_FINAL.md)
- [Security Configuration](../config/security.yml)
- [Monitoring Setup](../config/prometheus.yml)

---

*Last Updated: September 23, 2025*