"""FastAPI A2A server hosting the portfolio-analyst Strands agent."""
from __future__ import annotations

import os
import sys
from pathlib import Path

from fastapi import FastAPI
from pydantic import BaseModel

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from agent import build_agent  # noqa: E402

os.environ.setdefault("BYPASS_TOOL_CONSENT", "True")

app = FastAPI(title="portfolio-analyst")
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
        return {"result": result.message["content"][0]["text"]}
    except Exception as exc:
        return {"error": str(exc)}
