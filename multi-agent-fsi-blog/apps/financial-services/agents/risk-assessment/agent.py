"""Risk Assessment Strands agent.

Scores portfolio risk by asking the LLM to generate scoring Python and
executing it in AgentCore Code Interpreter. No MCP dependency.
"""
from __future__ import annotations

import json
import os
import re
from typing import Any

from rich.console import Console
from strands import Agent, tool

from _shared.model import build_model

AWS_REGION = os.getenv("AWS_REGION", "us-west-2")
CODE_INTERPRETER_ID = os.getenv("CODE_INTERPRETER_ID", "")

console = Console()


@tool
def score_risk_via_code(
    portfolio: dict[str, float], tolerance: str = "medium"
) -> dict[str, Any]:
    """Generate risk-scoring Python, execute it in Code Interpreter, and return
    the verdict against the client's tolerance.

    Args:
        portfolio: weights keyed by symbol, e.g. {"AAPL": 0.6, "TSLA": 0.4}
        tolerance: "low" | "medium" | "high"
    """
    if not CODE_INTERPRETER_ID:
        return {"status": "error", "error": "CODE_INTERPRETER_ID not set"}

    from bedrock_agentcore.tools.code_interpreter_client import CodeInterpreter

    inner_model = build_model()
    inner = Agent(model=inner_model) if inner_model is not None else Agent()
    query = (
        "Write short Python that scores portfolio risk. Use these per-symbol "
        "risk weights on a 0-1 scale (fall back to 0.5 for unknown symbols): "
        "AAPL=0.30, GOOGL=0.35, MSFT=0.25, AMZN=0.40, TSLA=0.80. Compute a "
        "portfolio_risk as the sum of weight*risk_weight across the portfolio "
        "dict, scaled to 0-100. Compare against tolerance thresholds "
        "(low=30, medium=60, high=90). Print a JSON object with keys: "
        "risk_score (float), risk_level ('low'|'medium'|'high'), "
        "within_tolerance (bool), recommendation (string). "
        f"portfolio = {json.dumps(portfolio)}\n"
        f"tolerance = {json.dumps(tolerance)}\n"
        "Return ONLY the Python code in a ```python fenced block."
    )
    llm_result = inner(query)
    raw = llm_result.message["content"][0]["text"]
    match = re.search(r"```(?:python)?\n(.*?)\n```", raw, re.DOTALL)
    code = match.group(1).strip() if match else raw

    client = CodeInterpreter(AWS_REGION)
    client.start(identifier=CODE_INTERPRETER_ID)
    try:
        response = client.invoke(
            "executeCode",
            {"code": code, "language": "python", "clearContext": True},
        )
        output = ""
        for event in response["stream"]:
            output = json.dumps(event["result"])
        return {"status": "success", "code_executed": code, "result": output}
    finally:
        try:
            client.stop()
        except Exception:
            pass


SYSTEM_PROMPT = """You are a Risk Assessment Specialist.

Given a portfolio and a client's risk tolerance, call score_risk_via_code to
run dynamic risk analysis. Always report:
- the numeric risk score
- whether it is within the client's stated tolerance
- a specific, actionable recommendation (rebalance toward lower-risk assets,
  hold, or increase diversification)

Prioritize client safety and regulatory compliance. Keep responses concise.
"""


def build_agent() -> Agent:
    kwargs: dict[str, Any] = {
        "tools": [score_risk_via_code],
        "system_prompt": SYSTEM_PROMPT,
        "name": "RiskAssessmentSpecialist",
    }
    model = build_model()
    if model is not None:
        kwargs["model"] = model
    return Agent(**kwargs)
