#!/usr/bin/env python3
"""
LangGraph Travel Agent with OpenTelemetry Session Tracking
Interactive travel planning agent with web search capabilities.
"""

import os
import uuid
from typing import Annotated

# LangChain imports
from langchain.chat_models import init_chat_model
from langchain_core.tools import tool

# LangGraph imports  
from typing_extensions import TypedDict
from langgraph.graph import StateGraph, START
from langgraph.graph.message import add_messages
from langgraph.prebuilt import ToolNode, tools_condition

# External tools
from ddgs import DDGS

# OpenTelemetry imports
from opentelemetry import baggage
from opentelemetry.context import attach, detach

# Configure environment
os.environ["LANGSMITH_OTEL_ENABLED"] = "true"


@tool("web_search")
def web_search(query: str) -> str:
    """Search the web for current information about destinations, attractions, events, and general topics."""
    try:
        ddgs = DDGS()
        results = ddgs.text(query, max_results=5)
        
        formatted_results = []
        for i, result in enumerate(results, 1):
            formatted_results.append(
                f"{i}. {result.get('title', 'No title')}\n"
                f"   {result.get('body', 'No summary')}\n"
                f"   Source: {result.get('href', 'No URL')}\n"
            )
        
        return "\n".join(formatted_results)
    except Exception as e:
        return f"Search failed: {str(e)}"


class State(TypedDict):
    """State definition for the LangGraph agent."""
    messages: Annotated[list, add_messages]


# Initialize the language model
llm = init_chat_model(
    "anthropic.claude-3-5-sonnet-20241022-v2:0", 
    model_provider="bedrock", 
    temperature=0
)


def chatbot(state: State):
    """Main chatbot function that processes messages."""
    return {"messages": [llm.invoke(state["messages"])]}


# Configure tools and graph
tools = [web_search]
llm_with_tools = llm.bind_tools(tools)

graph_builder = StateGraph(State)
graph_builder.add_node("chatbot", chatbot)
graph_builder.add_node("tools", ToolNode(tools))
graph_builder.add_edge(START, "chatbot")
graph_builder.add_conditional_edges("chatbot", tools_condition)
graph_builder.add_edge("tools", "chatbot")

graph = graph_builder.compile()


def agent_invocation(query: str) -> dict:
    """
    Invoke the travel agent with session tracking.
    
    Args:
        query: User's travel-related question
        
    Returns:
        Dictionary with result, status, and session_id
    """
    session_id = str(uuid.uuid4())
    ctx = baggage.set_baggage("session.id", session_id)
    token = attach(ctx)
    
    try:
        result = graph.invoke({"messages": [("user", query)]})
        return {
            "result": result["messages"][-1].content,
            "status": "success",
            "session_id": session_id
        }
    except Exception as e:
        return {
            "result": f"Error: {str(e)}",
            "status": "error",
            "session_id": session_id
        }
    finally:
        detach(token)


if __name__ == "__main__":
    print("\nLangGraph Travel Agent\n")
    print("This agent can help you with travel planning, destinations, and recommendations.")
    print("\nOptions:")
    print("  'exit' - Exit the program")
    print("\nAsk me about travel:")
    print("  'What are the best restaurants in Paris?'")
    print("  'Family activities in Tokyo?'")
    print("  'Best hiking trails near Seattle?'")

    # Interactive loop
    while True:
        try:
            user_input = input("\n> ")

            if user_input.lower() == "exit":
                print("\nGoodbye! 👋")
                break

            # Call the agent
            response = agent_invocation(user_input)
            
            if response["status"] == "success":
                print(f"\n{response['result']}")
                print(f"\n[Session ID: {response['session_id']}]")
            else:
                print(f"\nError: {response['result']}")
                print(f"\n[Session ID: {response['session_id']}]")

        except KeyboardInterrupt:
            print("\n\nExecution interrupted. Exiting...")
            break
        except EOFError:
            print("\n\nSession ended.")
            break
        except Exception as e:
            print(f"\nAn error occurred: {str(e)}")
            print("Please try a different request.")
