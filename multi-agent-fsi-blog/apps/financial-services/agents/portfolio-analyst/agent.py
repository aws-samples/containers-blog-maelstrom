"""Portfolio Analyst Strands agent.

Capabilities:
- AgentCore Code Interpreter for dynamic portfolio valuation (LLM-generated Python)
- MCP get_stock_price for current prices

Exposed via POST / for Agent Gateway /agents/portfolio-analyst.
"""
from __future__ import annotations

import json
import os
import re
from typing import Any

from rich.console import Console
from strands import Agent, tool

from _shared import mcp_client
from _shared.model import build_model

AWS_REGION = os.getenv("AWS_REGION", "us-west-2")
CODE_INTERPRETER_ID = os.getenv("CODE_INTERPRETER_ID", "")

console = Console()


@tool
def get_stock_price(symbol: str) -> dict[str, Any]:
    """Fetch a stock price via the financial-tools MCP server."""
    return mcp_client.call_tool("get_stock_price", {"symbol": symbol})


@tool
def value_portfolio_via_code(holdings: dict[str, int], prices: dict[str, float]) -> dict[str, Any]:
    """Value a portfolio by asking the LLM to write Python and executing it in
    AgentCore Code Interpreter.
    """
    if not CODE_INTERPRETER_ID:
        return {"status": "error", "error": "CODE_INTERPRETER_ID not set"}

    from bedrock_agentcore.tools.code_interpreter_client import CodeInterpreter

    # Generate valuation code using the same LiteLLM-routed model as the agent.
    inner_model = build_model()
    inner = Agent(model=inner_model) if inner_model is not None else Agent()
    query = (
        "Write short Python that computes portfolio valuation and per-holding "
        "weights. Inputs are two dicts: holdings (symbol -> share count) and "
        "prices (symbol -> price). Print a JSON object with keys "
        "total_value (float, 2dp) and weights (symbol -> weight, 4dp). "
        f"holdings = {json.dumps(holdings)}\nprices = {json.dumps(prices)}\n"
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


SYSTEM_PROMPT = """You are a Portfolio Analyst.

Your job is to value client portfolios and explain composition. Workflow:
1. For each holding symbol, call get_stock_price to obtain the current price.
2. Build the holdings and prices dicts.
3. Call value_portfolio_via_code(holdings, prices) to generate and execute
   the valuation logic in the Code Interpreter.
4. Summarize total value, per-holding weights, and note which holdings
   dominate the portfolio.

Keep responses compact and numeric. Do not invent prices — always call
get_stock_price first.
"""


def build_agent() -> Agent:
    kwargs: dict[str, Any] = {
        "tools": [get_stock_price, value_portfolio_via_code],
        "system_prompt": SYSTEM_PROMPT,
        "name": "PortfolioAnalyst",
    }
    model = build_model()
    if model is not None:
        kwargs["model"] = model
    return Agent(**kwargs)
