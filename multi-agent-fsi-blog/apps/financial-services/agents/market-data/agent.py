"""Market Data Strands agent.

Capabilities:
- AgentCore Browser for live stock quotes from finance.yahoo.com
- MCP get_stock_price (fallback if Browser fails)
- MCP get_market_trends for sector analysis

Exposes a single POST / endpoint consumed by Agent Gateway /agents/market-data.
"""
from __future__ import annotations

import asyncio
import os
import re
from contextlib import suppress
from typing import Any

from rich.console import Console
from strands import Agent, tool

from _shared import mcp_client
from _shared.model import build_model

AWS_REGION = os.getenv("AWS_REGION", "us-west-2")
BROWSER_ID = os.getenv("BROWSER_ID", "")

console = Console()


async def _fetch_live_quote(symbol: str) -> str:
    """Use AgentCore Browser to scrape a real-time quote from yahoo finance."""
    from bedrock_agentcore.tools.browser_client import BrowserClient
    from browser_use import Agent as BrowserAgent
    from browser_use.browser import BrowserProfile
    from browser_use.browser.session import BrowserSession
    from langchain_aws import ChatBedrockConverse

    client = BrowserClient(AWS_REGION)
    client.start(identifier=BROWSER_ID)
    try:
        ws_url, headers = client.generate_ws_headers()
        profile = BrowserProfile(headers=headers, timeout=150000)
        session = BrowserSession(cdp_url=ws_url, browser_profile=profile, keep_alive=True)
        await session.start()
        try:
            llm = ChatBedrockConverse(
                model_id="us.anthropic.claude-3-7-sonnet-20250219-v1:0",
                region_name=AWS_REGION,
            )
            task = (
                f"Go to https://finance.yahoo.com/quote/{symbol.upper()} and read the "
                "current price displayed at the top of the page. Return just the numeric "
                "price in USD and nothing else."
            )
            browser_agent = BrowserAgent(task=task, llm=llm, browser=session)
            result = await browser_agent.run()
            last = result.last_action()
            if "done" in last and "text" in last["done"]:
                return last["done"]["text"]
            return str(result)
        finally:
            with suppress(Exception):
                await session.close()
    finally:
        with suppress(Exception):
            client.stop()


def _extract_price(text: str) -> float | None:
    match = re.search(r"\d+(?:\.\d+)?", text.replace(",", ""))
    return float(match.group(0)) if match else None


@tool
def get_live_quote(symbol: str) -> dict[str, Any]:
    """Get a live stock price via AgentCore Browser; fall back to MCP on failure."""
    if BROWSER_ID:
        try:
            console.print(f"[cyan]Browser: fetching live {symbol}[/cyan]")
            raw = asyncio.run(_fetch_live_quote(symbol))
            price = _extract_price(raw)
            if price:
                return {
                    "status": "success",
                    "source": "browser",
                    "symbol": symbol.upper(),
                    "price": price,
                }
            console.print(f"[yellow]Browser returned unparseable value: {raw!r}[/yellow]")
        except Exception as exc:
            console.print(f"[yellow]Browser failed ({exc}); falling back to MCP[/yellow]")

    result = mcp_client.call_tool("get_stock_price", {"symbol": symbol})
    return {"status": "success", "source": "mcp", **result}


@tool
def get_market_trends(sector: str = "technology") -> dict[str, Any]:
    """Get market trend summary for a sector via MCP."""
    result = mcp_client.call_tool("get_market_trends", {"sector": sector})
    return {"status": "success", **result}


SYSTEM_PROMPT = """You are a Market Data Specialist.

You provide current stock prices and sector trend summaries. When asked for a
stock price, call get_live_quote. When asked about a sector, call get_market_trends.
Always cite which source the quote came from (browser vs mcp) and include the
current price and timestamp when available. Keep responses short and factual.
"""


def build_agent() -> Agent:
    kwargs: dict[str, Any] = {
        "tools": [get_live_quote, get_market_trends],
        "system_prompt": SYSTEM_PROMPT,
        "name": "MarketDataSpecialist",
    }
    model = build_model()
    if model is not None:
        kwargs["model"] = model
    return Agent(**kwargs)
