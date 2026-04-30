"""Shared MCP client for Strands specialist agents.

Sends JSON-RPC 2.0 `tools/call` requests through Agent Gateway's /mcp route,
injecting the pod's projected ServiceAccount token as the bearer so the
gateway's JWT authn + MCP authz policies can identify the caller.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

import httpx

DEFAULT_TOKEN_PATH = Path(
    os.getenv("AGENT_GATEWAY_TOKEN_PATH", "/var/run/secrets/agent-gateway/token")
)
DEFAULT_GATEWAY_URL = os.getenv(
    "MCP_GATEWAY_URL",
    "http://agent-gateway-proxy.agentgateway-system.svc.cluster.local:8080",
)


def _read_token() -> str:
    try:
        return DEFAULT_TOKEN_PATH.read_text().strip()
    except FileNotFoundError:
        return ""


def call_tool(tool_name: str, arguments: dict[str, Any], *, timeout: float = 60.0) -> dict[str, Any]:
    """Invoke an MCP tool through Agent Gateway and return the parsed result."""
    token = _read_token()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {"name": tool_name, "arguments": arguments},
    }

    response = httpx.post(
        f"{DEFAULT_GATEWAY_URL}/mcp",
        headers=headers,
        json=payload,
        timeout=timeout,
    )
    response.raise_for_status()
    body = response.json()

    if "error" in body:
        raise RuntimeError(f"MCP error for {tool_name}: {body['error']}")

    content = body.get("result", {}).get("content", [])
    if content and isinstance(content, list) and "text" in content[0]:
        text = content[0]["text"]
        # MCP tool results are dict-stringified server-side; try to recover.
        try:
            return json.loads(text.replace("'", '"'))
        except json.JSONDecodeError:
            return {"raw": text}
    return body.get("result", {})
