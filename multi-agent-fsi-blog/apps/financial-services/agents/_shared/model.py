"""Model factory for Strands agents.

Resolution order:
  1. `strands.models.litellm.LiteLLMModel` — preferred because it lets us
     route every inference through the in-cluster LiteLLM proxy for spend
     tracking and fallback routing. Requires `pip install litellm` in the
     agent image; if absent, falls through.
  2. `strands.models.openai.OpenAIModel` — backup path against LiteLLM's
     OpenAI-compatible endpoint. Requires `pip install openai`.
  3. `strands.models.bedrock.BedrockModel` — final fallback that talks to
     Bedrock directly via boto3 (already in the agent image). Uses
     BEDROCK_MODEL_ID from env so we can hot-swap model ids in Helm without
     rebuilding images.

Environment contract (set via Helm for each agent pod):
  LITELLM_URL       e.g. http://litellm.litellm.svc.cluster.local:4000
  LITELLM_API_KEY   master key or per-team virtual key
  LITELLM_MODEL     logical model name registered in LiteLLM
                    (default: finops-primary)
  BEDROCK_MODEL_ID  model id used by the Bedrock fallback
                    (default: us.anthropic.claude-sonnet-4-6)
  AWS_REGION        Bedrock region (default: us-west-2)
"""
from __future__ import annotations

import logging
import os

LITELLM_URL = os.getenv("LITELLM_URL", "http://litellm.litellm.svc.cluster.local:4000")
LITELLM_API_KEY = os.getenv("LITELLM_API_KEY", "sk-finops-demo-master")
LITELLM_MODEL = os.getenv("LITELLM_MODEL", "finops-primary")
BEDROCK_MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "us.anthropic.claude-sonnet-4-6")
AWS_REGION = os.getenv("AWS_REGION", "us-west-2")

log = logging.getLogger(__name__)


def build_model():
    """Return a Strands-compatible model instance, or None to use the
    Strands default (which hardcodes a model id that may be Bedrock-legacy).
    """
    try:
        from strands.models.litellm import LiteLLMModel  # type: ignore

        log.info("Using LiteLLM provider → %s (model=%s)", LITELLM_URL, LITELLM_MODEL)
        return LiteLLMModel(
            model_id=LITELLM_MODEL,
            api_base=LITELLM_URL,
            api_key=LITELLM_API_KEY,
        )
    except Exception as exc:
        log.info("LiteLLM provider unavailable (%s), trying OpenAI provider", exc)

    try:
        from strands.models.openai import OpenAIModel  # type: ignore

        log.info("Using OpenAI provider → %s/v1", LITELLM_URL)
        return OpenAIModel(
            model_id=LITELLM_MODEL,
            base_url=f"{LITELLM_URL}/v1",
            api_key=LITELLM_API_KEY,
        )
    except Exception as exc:
        log.info("OpenAI provider unavailable (%s), falling back to Bedrock direct", exc)

    try:
        from strands.models.bedrock import BedrockModel  # type: ignore

        log.info(
            "Using Bedrock provider directly (model=%s, region=%s)",
            BEDROCK_MODEL_ID,
            AWS_REGION,
        )
        return BedrockModel(model_id=BEDROCK_MODEL_ID, region_name=AWS_REGION)
    except Exception as exc:
        log.warning(
            "No Strands provider could be constructed (%s). Falling back to "
            "Strands' implicit default — the hard-coded model id may be "
            "Bedrock-legacy and cause 'Model marked as Legacy' errors.",
            exc,
        )
        return None
