#!/usr/bin/env python3
"""
Conversations API Demo

Demonstrates how Conversations API maintains server-side state across multiple
Responses API calls. Unlike using previous_response_id, conversation_id provides
a persistent container that automatically accumulates conversation history.

This demo shows:
1. Create a conversation
2. Use Responses API with conversation_id (Turn 1)
3. Use Responses API with same conversation_id (Turn 2)
4. Use Responses API with same conversation_id (Turn 3)
5. Verify AI remembers context from all previous turns

Usage:
    uv run demos/conversations/demo.py
"""

import sys
from pathlib import Path
from openai import OpenAI

# Add project root to path for imports
PROJECT_ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from demos.common.utils import get_keycloak_token, load_demo_config


def print_section(title: str):
    """Print a formatted section header"""
    print("\n" + "=" * 60)
    print(title)
    print("=" * 60)


def print_message(role: str, content: str):
    """Print a formatted message"""
    print(f"{role.upper()}: {content}")


def create_response_in_conversation(client: OpenAI, conversation_id: str,
                                    user_message: str,
                                    instructions: str = None,
                                    model: str = "vllm-inference/llama-3-2-3b"):
    """
    Send a message in a conversation and get AI response.
    Uses Responses API with conversation_id to maintain state.
    """
    try:
        print_message("user", user_message)

        params = {
            "model": model,
            "input": user_message,
            "conversation": conversation_id,
            "store": True
        }

        if instructions:
            params["instructions"] = instructions

        response = client.responses.create(**params)

        # Extract content from response
        content = ""
        for item in response.output:
            if hasattr(item, 'type') and item.type == 'message':
                if hasattr(item, 'content'):
                    for content_item in item.content:
                        if hasattr(content_item, 'text'):
                            content += content_item.text

        print_message("assistant", content)

        return {
            'id': response.id,
            'content': content,
            'status': response.status if hasattr(response, 'status') else None
        }

    except Exception as e:
        print(f"✗ Failed to create response: {e}")
        return None


def main():
    print_section("Conversations API Demo")

    # Load configuration
    config = load_demo_config()

    ogx_url = config['ogx_url']
    keycloak_url = config['keycloak_url']
    username = config['username']
    password = config['password']
    client_secret = config['client_secret']

    if not ogx_url:
        print("\nError: OGX_URL is required")
        print("Set it via environment variables or run through ./test.sh")
        sys.exit(1)

    print(f"\nConnecting to: {ogx_url}")

    # Get authentication token if Keycloak is configured
    api_key = "not-needed"
    if keycloak_url and username and password and client_secret:
        try:
            print(f"Authenticating as '{username}'...")
            api_key = get_keycloak_token(keycloak_url, username, password, client_secret)
            print("✓ Authentication successful")
        except Exception as e:
            print(f"✗ Authentication failed: {e}")
            sys.exit(1)

    # Initialize OpenAI client
    client = OpenAI(
        base_url=f"{ogx_url}/v1",
        api_key=api_key,
    )

    # Step 1: Create a conversation
    print_section("Step 1: Create Conversation")

    try:
        conversation = client.conversations.create(
            metadata={
                "topic": "pet-living-quarters",
                "user": username or "demo-user"
            }
        )
        conversation_id = conversation.id
        print(f"✓ Created conversation: {conversation_id}")
        if hasattr(conversation, 'metadata'):
            print(f"  Metadata: {conversation.metadata}")
    except Exception as e:
        print(f"✗ Failed to create conversation: {e}")
        sys.exit(1)

    # Step 2: Turn 1 - Initial question
    print_section("Step 2: Turn 1 - Start Conversation")

    instructions = "You are a helpful assistant. Keep all responses brief (1-2 sentences max)."

    response1 = create_response_in_conversation(
        client,
        conversation_id,
        "I want to get living quarters for a rabbit. What is it called? It begins with 'hu'.",
        instructions=instructions
    )

    if not response1:
        print("\n✗ Demo failed at turn 1")
        sys.exit(1)

    # Step 3: Turn 2 - Follow-up (should remember rabbit context)
    print_section("Step 3: Turn 2 - Continue Conversation")

    response2 = create_response_in_conversation(
        client,
        conversation_id,
        "I also have a dog. What are the living quarters for a dog called? It begins with 'ke'.",
        instructions=instructions
    )

    if not response2:
        print("\n✗ Demo failed at turn 2")
        sys.exit(1)

    # Step 4: Turn 3 - Another follow-up (should remember both rabbit and dog)
    print_section("Step 4: Turn 3 - Continue Conversation")

    response3 = create_response_in_conversation(
        client,
        conversation_id,
        "List the living quarters I need for my pets. One begins with 'hu' and one begins with 'ke'.",
        instructions=instructions
    )

    if not response3:
        print("\n✗ Demo failed at turn 3")
        sys.exit(1)

    # Validate response contains BOTH rabbit and dog shelter terms
    content_lower = response3['content'].lower()
    has_rabbit_shelter = any(word in content_lower for word in ['hutch', 'hut'])
    has_dog_shelter = 'kennel' in content_lower

    if not has_rabbit_shelter or not has_dog_shelter:
        print(f"\n✗ Turn 3 validation failed: Expected both rabbit shelter and kennel")
        print(f"   Found rabbit shelter: {has_rabbit_shelter}, Found kennel: {has_dog_shelter}")
        print(f"   Response was: {response3['content']}")
        sys.exit(1)
    print("✓ Turn 3 validation: Both rabbit shelter and kennel found in response")

    # Step 5: Verify conversation state
    print_section("Step 5: Verify Conversation State")

    try:
        items_page = client.conversations.items.list(conversation_id, order="asc")
        items = items_page.data if hasattr(items_page, 'data') else []

        # Count messages
        user_msgs = sum(1 for item in items if hasattr(item, 'role') and item.role == 'user')
        assistant_msgs = sum(1 for item in items if hasattr(item, 'role') and item.role == 'assistant')

        print(f"\n✓ Found {len(items)} items: {user_msgs} user, {assistant_msgs} assistant")

        # Verify we got all turns
        if user_msgs >= 3 and assistant_msgs >= 3:
            print(f"✓ All conversation turns verified")
        else:
            print(f"⚠ Warning: Expected 3+ turns, found {user_msgs} user / {assistant_msgs} assistant")
            sys.exit(1)

    except Exception as e:
        print(f"✗ Failed to list conversation items: {e}")
        sys.exit(1)

    # Cleanup
    print_section("Cleanup")

    try:
        client.conversations.delete(conversation_id)
        print(f"✓ Deleted conversation")
    except Exception as e:
        print(f"✗ Failed to delete conversation: {e}")

    # Summary
    print_section("✅ Demo Complete!")

    print("\nVerified:")
    print("  ✓ Conversation maintains state across multiple Responses API calls")
    print("  ✓ AI remembered context from previous turns (hutch + kennel)")
    print("  ✓ Server-side state persisted in conversation_id")


if __name__ == "__main__":
    main()
