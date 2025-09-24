import os
import statistics
from typing import Dict, List, Optional

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="AI-SWARM Cost Optimizer", version="1.0.0")


class ProviderMetrics(BaseModel):
    provider: str = Field(..., description="Provider identifier e.g. openrouter")
    cost_per_1k_tokens: float = Field(..., gt=0)
    latency_ms: Optional[float] = Field(default=None, gt=0)
    reliability_percent: Optional[float] = Field(default=None, ge=0, le=100)


class OptimizationRequest(BaseModel):
    workload_tokens: int = Field(..., gt=0)
    providers: List[ProviderMetrics]
    max_latency_ms: Optional[float] = Field(default=None, gt=0)
    min_reliability_percent: Optional[float] = Field(default=None, ge=0, le=100)


class OptimizationResponse(BaseModel):
    best_provider: str
    estimated_cost: float
    rationale: str
    ranked_providers: List[Dict[str, float]]


class ConfigStatus(BaseModel):
    openrouter_configured: bool
    gemini_configured: bool
    openai_configured: bool
    anthropic_configured: bool
    huggingface_configured: bool


API_KEYS = {
    "OPENROUTER_API_KEY": os.getenv("OPENROUTER_API_KEY"),
    "GEMINI_API_KEY": os.getenv("GEMINI_API_KEY"),
    "OPENAI_API_KEY": os.getenv("OPENAI_API_KEY"),
    "ANTHROPIC_API_KEY": os.getenv("ANTHROPIC_API_KEY"),
    "HUGGINGFACE_TOKEN": os.getenv("HUGGINGFACE_TOKEN") or os.getenv("HF_TOKEN"),
}

REDIS_URL = os.getenv("REDIS_URL")
HTTP_TIMEOUT = float(os.getenv("OPTIMIZER_HTTP_TIMEOUT", "5"))


@app.get("/health")
async def health_check() -> Dict[str, bool]:
    configured = {key: value is not None and value != "" for key, value in API_KEYS.items()}
    return {
        "status": "ok",
        "providers_configured": configured,
        "redis_enabled": bool(REDIS_URL),
    }


@app.get("/config", response_model=ConfigStatus)
async def config_status() -> ConfigStatus:
    return ConfigStatus(
        openrouter_configured=bool(API_KEYS["OPENROUTER_API_KEY"]),
        gemini_configured=bool(API_KEYS["GEMINI_API_KEY"]),
        openai_configured=bool(API_KEYS["OPENAI_API_KEY"]),
        anthropic_configured=bool(API_KEYS["ANTHROPIC_API_KEY"]),
        huggingface_configured=bool(API_KEYS["HUGGINGFACE_TOKEN"]),
    )


@app.post("/optimize", response_model=OptimizationResponse)
async def optimize_workload(payload: OptimizationRequest) -> OptimizationResponse:
    if not payload.providers:
        raise HTTPException(status_code=400, detail="At least one provider must be supplied")

    # Apply filters based on latency and reliability constraints
    filtered_providers: List[ProviderMetrics] = []
    for option in payload.providers:
        if payload.max_latency_ms and option.latency_ms and option.latency_ms > payload.max_latency_ms:
            continue
        if (
            payload.min_reliability_percent
            and option.reliability_percent
            and option.reliability_percent < payload.min_reliability_percent
        ):
            continue
        filtered_providers.append(option)

    if not filtered_providers:
        raise HTTPException(status_code=422, detail="No providers meet the supplied constraints")

    ranked = sorted(filtered_providers, key=lambda opt: (opt.cost_per_1k_tokens, opt.latency_ms or 0))
    best = ranked[0]
    estimated_cost = round((payload.workload_tokens / 1000) * best.cost_per_1k_tokens, 4)

    rationale_parts = [
        f"Selected provider '{best.provider}' with ${best.cost_per_1k_tokens}/1K tokens",
        f"Estimated workload cost: ${estimated_cost}",
    ]
    if best.latency_ms:
        rationale_parts.append(f"Latency: {best.latency_ms}ms")
    if best.reliability_percent:
        rationale_parts.append(f"Reliability: {best.reliability_percent}%")

    ranked_summary = [
        {
            "provider": option.provider,
            "cost_per_1k_tokens": option.cost_per_1k_tokens,
            "latency_ms": option.latency_ms or 0,
        }
        for option in ranked
    ]

    return OptimizationResponse(
        best_provider=best.provider,
        estimated_cost=estimated_cost,
        rationale=" | ".join(rationale_parts),
        ranked_providers=ranked_summary,
    )


@app.get("/providers/latency")
async def provider_latency_sample(providers: Optional[str] = None) -> Dict[str, float]:
    """Run simple latency probes against configured providers when health endpoints exist."""

    provider_urls = {
        "openrouter": "https://openrouter.ai/api/v1/models",
        "openai": "https://api.openai.com/v1/models",
        "anthropic": "https://api.anthropic.com/v1/models",
        "gemini": "https://generativelanguage.googleapis.com/v1beta/models",
        "huggingface": "https://huggingface.co/api/models",
    }

    if providers:
        requested = {name.strip().lower() for name in providers.split(",")}
        provider_urls = {name: url for name, url in provider_urls.items() if name in requested}

    latencies: Dict[str, float] = {}
    async with httpx.AsyncClient(timeout=HTTP_TIMEOUT) as client:
        for name, url in provider_urls.items():
            try:
                response = await client.get(url)
                latencies[name] = response.elapsed.total_seconds() * 1000
            except httpx.HTTPError:
                latencies[name] = float("inf")
    return latencies


@app.get("/providers/summary")
async def provider_summary() -> Dict[str, Optional[float]]:
    configured_counts = [1 if key else 0 for key in API_KEYS.values()]
    total_configured = sum(configured_counts)
    avg_configured = statistics.mean(configured_counts) if configured_counts else 0
    return {
        "total_providers": len(API_KEYS),
        "configured": total_configured,
        "configuration_score": avg_configured,
    }
