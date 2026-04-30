"""FastAPI A2A server hosting the market-data Strands agent.

Agent Gateway routes POST /agents/market-data → this service's POST /.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

from fastapi import FastAPI
from pydantic import BaseModel

# _shared lives one level up; add to path so `from _shared import ...` works.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from agent import build_agent  # noqa: E402

os.environ.setdefault("BYPASS_TOOL_CONSENT", "True")

app = FastAPI(title="market-data")
_agent = build_agent()


class TaskRequest(BaseModel):
    task: str


@app.get("/healthz")
def healthz():
    return {"status": "healthy"}


@app.post("/")
def handle(req: TaskRequest):
    try:
        result = _agent(req.task)
        text = result.message["content"][0]["text"]
        return {"result": text}
    except Exception as exc:  # surfaced to caller via Agent Gateway
        return {"error": str(exc)}
