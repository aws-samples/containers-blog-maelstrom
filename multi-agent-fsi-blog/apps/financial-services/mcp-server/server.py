"""
Financial Tools MCP Server

Deterministic financial tools exposed via JSON-RPC /mcp endpoint, consumed by
Strands specialist agents through Agent Gateway. Three tools are served:
calculate_portfolio_value, get_stock_price, get_market_trends. Risk scoring
lives in the risk-assessment agent's Code Interpreter flow instead.
"""
from datetime import datetime
import random

from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="Financial Tools MCP Server")


class PortfolioRequest(BaseModel):
    holdings: dict
    prices: dict


class StockPriceRequest(BaseModel):
    symbol: str


class MarketTrendsRequest(BaseModel):
    sector: str = "technology"


# Deterministic fallback prices for demo purposes. market-data agent uses the
# Browser capability to get live quotes and falls back here if scraping fails.
FALLBACK_PRICES = {
    "AAPL": 175.50,
    "GOOGL": 140.25,
    "MSFT": 380.75,
    "AMZN": 145.30,
    "TSLA": 245.60,
}

SECTOR_TRENDS = {
    "technology": {"trend": "bullish", "growth": 12.5, "volatility": "medium"},
    "finance": {"trend": "neutral", "growth": 3.2, "volatility": "low"},
    "healthcare": {"trend": "bullish", "growth": 8.7, "volatility": "low"},
    "energy": {"trend": "bearish", "growth": -2.1, "volatility": "high"},
}


async def _calculate_portfolio_value(req: PortfolioRequest) -> dict:
    total = sum(
        req.holdings.get(symbol, 0) * req.prices.get(symbol, 0)
        for symbol in req.holdings.keys()
    )
    return {
        "success": True,
        "total_value": round(total, 2),
        "holdings": req.holdings,
        "timestamp": datetime.utcnow().isoformat(),
    }


async def _get_stock_price(req: StockPriceRequest) -> dict:
    price = FALLBACK_PRICES.get(req.symbol.upper(), random.uniform(50, 500))
    return {
        "success": True,
        "symbol": req.symbol.upper(),
        "price": round(price, 2),
        "currency": "USD",
        "timestamp": datetime.utcnow().isoformat(),
    }


async def _get_market_trends(req: MarketTrendsRequest) -> dict:
    data = SECTOR_TRENDS.get(
        req.sector.lower(),
        {"trend": "neutral", "growth": 0, "volatility": "medium"},
    )
    return {
        "success": True,
        "sector": req.sector,
        "trend": data["trend"],
        "growth_rate": data["growth"],
        "volatility": data["volatility"],
        "timestamp": datetime.utcnow().isoformat(),
    }


@app.post("/tools/calculate_portfolio_value")
async def calculate_portfolio_value(req: PortfolioRequest):
    return await _calculate_portfolio_value(req)


@app.post("/tools/get_stock_price")
async def get_stock_price(req: StockPriceRequest):
    return await _get_stock_price(req)


@app.post("/tools/get_market_trends")
async def get_market_trends(req: MarketTrendsRequest):
    return await _get_market_trends(req)


@app.get("/health")
async def health():
    return {"status": "healthy"}


TOOL_DEFINITIONS = [
    {
        "name": "calculate_portfolio_value",
        "description": "Calculate total portfolio value from holdings and current prices",
        "inputSchema": {
            "type": "object",
            "properties": {
                "holdings": {"type": "object", "description": "Stock holdings keyed by symbol"},
                "prices": {"type": "object", "description": "Current prices keyed by symbol"},
            },
            "required": ["holdings", "prices"],
        },
    },
    {
        "name": "get_stock_price",
        "description": "Get current stock price for a symbol",
        "inputSchema": {
            "type": "object",
            "properties": {"symbol": {"type": "string"}},
            "required": ["symbol"],
        },
    },
    {
        "name": "get_market_trends",
        "description": "Get market trends for a sector",
        "inputSchema": {
            "type": "object",
            "properties": {"sector": {"type": "string"}},
        },
    },
]


@app.post("/mcp")
async def mcp_endpoint(request: dict):
    method = request.get("method")
    req_id = request.get("id")

    if method == "initialize":
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "financial-tools", "version": "1.0.0"},
            },
        }

    if method == "tools/list":
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {"tools": TOOL_DEFINITIONS},
        }

    if method == "tools/call":
        params = request.get("params", {})
        tool_name = params.get("name")
        arguments = params.get("arguments", {})

        dispatch = {
            "calculate_portfolio_value": (_calculate_portfolio_value, PortfolioRequest),
            "get_stock_price": (_get_stock_price, StockPriceRequest),
            "get_market_trends": (_get_market_trends, MarketTrendsRequest),
        }

        if tool_name not in dispatch:
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {"code": -32601, "message": f"Tool not found: {tool_name}"},
            }

        handler, model = dispatch[tool_name]
        result = await handler(model(**arguments))
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {"content": [{"type": "text", "text": str(result)}]},
        }

    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "error": {"code": -32601, "message": f"Method not found: {method}"},
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)
