#!/usr/bin/env python3

from strands import Agent, tool
from strands_tools import calculator
from strands.models import BedrockModel
import logging
import os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create a custom tool 
@tool
def weather():
    """ Get weather """ # Dummy implementation
    return "sunny"

# Create a Bedrock model
model = BedrockModel(
    model_id=os.getenv("BEDROCK_MODEL_ID", "anthropic.claude-3-sonnet-20240229-v1:0"),
    region_name=os.getenv("AWS_REGION", "us-west-2")
)

# Create the agent
agent = Agent(
    model=model,
    tools=[calculator, weather],
    system_prompt="You're a helpful assistant. You can do simple math calculation, and tell the weather.",
    trace_attributes={
        "session.id": "abc-1234",
        "user.id": "demo@example.com",
        "tags": [
            "Python-AgentSDK",
            "Observability-Tags",
            "CloudWatch-Demo"
        ]
    } 
)

# Example usage
if __name__ == "__main__":
    print("\nStrands Agent with Calculator and Weather\n")
    print("This example demonstrates using Strands Agents with calculator and weather tools.")
    print("\nOptions:")
    print("  'exit' - Exit the program")
    print("\nAsk me to calculate something or check the weather:")
    print("  'What is 25 * 16?'")
    print("  'How's the weather today?'")

    # Interactive loop
    while True:
        try:
            user_input = input("\n> ")

            if user_input.lower() == "exit":
                print("\nGoodbye! 👋")
                break

            # Call the agent
            response = agent(user_input)
            
            # Log the response
            logger.info(str(response))
             
        except KeyboardInterrupt:
            print("\n\nExecution interrupted. Exiting...")
            break
        except Exception as e:
            print(f"\nAn error occurred: {str(e)}")
            print("Please try a different request.")