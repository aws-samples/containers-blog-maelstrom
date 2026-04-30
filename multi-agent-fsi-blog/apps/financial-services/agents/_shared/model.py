"""Model factory for Strands agents.

Routes every LLM call through LiteLLM so the platform can track per-agent token
spend, apply fallback routing, and enforce budgets centrally. LiteLLM exposes
an OpenAI-compatible endpoint; Strands agents construct an OpenAI-style model
pointing at it.

Environment contract (populated via Helm for each agent pod):
  LITELLM_URL       - e.g. http://litellm.litellm.svc.cluster.local:4000
  LITELLM_API_KEY   - master key or per-team virtual key
  LITELLM_MODEL     - logical model name registered in LiteLLM
                      (default: finops-primary → Bedrock Claude 3.7 Sonnet)
"""
from __future__ import annotations

import os

LITELLM_URL = os.getenv("LITELLM_URL", "http://litellm.litellm.svc.cluster.local:4000")
LITELLM_API_KEY = os.getenv("LITELLM_API_KEY", "sk-finops-demo-master")
LITELLM_MODEL = os.getenv("LITELLM_MODEL", "finops-primary")


def build_model():
    """Return a Strands-compatible model backed by LiteLLM.

    Strands supports multiple providers; using the LiteLLM provider (or the
    OpenAI-compatible provider pointed at LiteLLM's /v1 endpoint) routes every
    inference through the proxy. If the Strands install does not have a
    dedicated litellm provider, we fall back to the openai provider which
    LiteLLM speaks natively.
    """
    try:
        from strands.models.litellm import LiteLLMModel  # type: ignore

        return LiteLLMModel(
            model_id=LITELLM_MODEL,
            api_base=LITELLM_URL,
            api_key=LITELLM_API_KEY,
        )
    except Exception:
        pass

    try:
        from strands.models.openai import OpenAIModel  # type: ignore

        return OpenAIModel(
            model_id=LITELLM_MODEL,
            base_url=f"{LITELLM_URL}/v1",
            api_key=LITELLM_API_KEY,
        )
    except Exception:
        # As a last resort return None — Strands will fall back to its default
        # provider (Bedrock via boto3). Logged so the operator notices.
        import logging

        logging.getLogger(__name__).warning(
            "LiteLLM/OpenAI providers not available in strands-agents; "
            "falling back to default provider."
        )
        return None
