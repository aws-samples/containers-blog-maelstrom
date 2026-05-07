"""Shared A2A client for Strands agents calling other agents via Agent Gateway.

The advisor uses this to delegate tasks to the three specialists. Each request
goes to Agent Gateway's /agents/<name> route with the pod's projected SA token
so the gateway can enforce A2A authorization.
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import httpx

DEFAULT_TOKEN_PATH = Path(
    os.getenv("AGENT_GATEWAY_TOKEN_PATH", "/var/run/secrets/agent-gateway/token")
)
DEFAULT_GATEWAY_URL = os.getenv(
    "A2A_GATEWAY_URL",
    "http://agent-gateway-proxy.agentgateway-system.svc.cluster.local:8080",
)


def _read_token() -> str:
    try:
        return DEFAULT_TOKEN_PATH.read_text().strip()
    except FileNotFoundError:
        return ""


def call_agent(agent_name: str, task: str, *, timeout: float = 180.0) -> dict[str, Any]:
    """POST a task to the named agent through Agent Gateway.

    Returns the JSON body from the target agent's FastAPI server — shape:
    {"result": "<agent response text>"} on success or
    {"error": "..."} on failure.
    """
    token = _read_token()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    response = httpx.post(
        f"{DEFAULT_GATEWAY_URL}/agents/{agent_name}",
        headers=headers,
        json={"task": task},
        timeout=timeout,
    )
    response.raise_for_status()
    return response.json()
