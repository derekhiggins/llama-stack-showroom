#!/usr/bin/env python3
"""
LlamaStack Responses API Demo

This script demonstrates how to:
1. Authenticate with Keycloak to get a JWT token
2. Use the OpenAI SDK Responses API (not Chat Completions) to verify LlamaStack API conformance
3. Create multi-turn conversations with system instructions
4. Track response IDs stored in LlamaStack's database

Usage:
    python demos/responses/demo.py [LLAMASTACK_URL] [KEYCLOAK_URL] [USERNAME] [PASSWORD] [CLIENT_SECRET] [--prompt PROMPT]

The script reads configuration from (in order): command line args, ~/.lls_showroom_generated,
environment variables. All arguments are optional if stored in ~/.lls_showroom_generated.

Example with no arguments (reads from ~/.lls_showroom_generated):
    python demos/responses/demo.py

Example with custom prompt:
    python demos/responses/demo.py --prompt "What is RAG?"

Example with URLs only:
    python demos/responses/demo.py https://llamastack-distribution.apps.example.com \
        https://keycloak.apps.example.com

Example with full authentication and custom prompt:
    python demos/responses/demo.py https://llamastack-distribution.apps.example.com \
        https://keycloak.apps.example.com \
        developer dev123 --prompt "Explain embeddings"

If Keycloak parameters are not provided, the script will run without authentication.
Default prompt: "What is a vector database?"
"""

import sys
import requests
import json
import os
import argparse
from typing import Optional, Dict, Any, List
from pathlib import Path
from openai import OpenAI

# Add project root to path for imports
PROJECT_ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from demos.common.utils import get_keycloak_token, load_demo_config


class ResponsesDemo:
    def __init__(self, base_url: str, keycloak_url: Optional[str] = None,
                 username: Optional[str] = None, password: Optional[str] = None,
                 client_secret: Optional[str] = None):
        self.base_url = base_url.rstrip('/')
        self.keycloak_url = keycloak_url.rstrip('/') if keycloak_url else None
        self.username = username
        self.password = password
        self.client_secret = client_secret

        # Track response IDs for each conversation turn
        self.response_history: List[Dict[str, Any]] = []

        # OpenAI client - will be initialized after auth
        self.client: Optional[OpenAI] = None

        # Get token and initialize client
        if self.keycloak_url and self.username and self.password and self.client_secret:
            access_token = self.authenticate()
            if access_token:
                self.client = OpenAI(
                    base_url=f"{self.base_url}/v1",
                    api_key=access_token,  # Use JWT token as API key
                )
        else:
            # No authentication - create client without token
            self.client = OpenAI(
                base_url=f"{self.base_url}/v1",
                api_key="not-needed",  # Some placeholder required
            )

    def authenticate(self) -> Optional[str]:
        """Get JWT token from Keycloak and return it"""
        try:
            access_token = get_keycloak_token(
                self.keycloak_url,
                self.username,
                self.password,
                self.client_secret
            )
            return access_token
        except Exception as e:
            print(f"✗ Authentication failed: {e}")
            return None

    def check_health(self) -> bool:
        """Check if LlamaStack API is healthy"""
        try:
            response = requests.get(f"{self.base_url}/v1/health", timeout=10, verify=True)
            response.raise_for_status()
            print(f"✓ LlamaStack is healthy")
            return True
        except Exception as e:
            print(f"✗ Health check failed: {e}")
            return False

    def create_response(self,
                       user_message: str,
                       instructions: Optional[str] = None,
                       model: str = "vllm-inference/llama-3-2-3b") -> Optional[Dict[str, Any]]:
        """
        Create a response using the OpenAI SDK Responses API.
        Auto-detects continuation based on response_history.

        Args:
            user_message: The user's input message
            instructions: Optional system instructions (only used for first turn)
            model: Model to use for inference

        Returns:
            Response dict containing id, content, and metadata
        """
        try:
            if not self.client:
                print(f"✗ OpenAI client not initialized")
                return None

            # Auto-detect if this is a continuation
            is_continuation = len(self.response_history) > 0

            # Build API call parameters
            params = {
                "model": model,
                "input": user_message,
                "store": True  # Store response in LlamaStack database
            }

            if is_continuation:
                # Continue existing conversation
                params["previous_response_id"] = self.response_history[-1]['id']
                # Use instructions from first turn
                params["instructions"] = self.response_history[0].get('instructions')
            else:
                # Start new conversation
                params["instructions"] = instructions

            # Call OpenAI Responses API - this verifies LlamaStack API conformance
            response = self.client.responses.create(**params)

            # Extract response content and metadata from Responses API
            # Response has 'output' field (list of items), not 'choices'
            content = ""
            for item in response.output:
                # Look for message items with text content
                if hasattr(item, 'type') and item.type == 'message':
                    if hasattr(item, 'content'):
                        for content_item in item.content:
                            if hasattr(content_item, 'text'):
                                content += content_item.text

            response_data = {
                'id': response.id,
                'content': content,
                'status': response.status if hasattr(response, 'status') else None,
                'user_message': user_message,
                'instructions': instructions if not is_continuation else None,
                'model': response.model,
                'usage': {
                    'input_tokens': response.usage.input_tokens if hasattr(response.usage, 'input_tokens') else 0,
                    'output_tokens': response.usage.output_tokens if hasattr(response.usage, 'output_tokens') else 0,
                    'total_tokens': response.usage.total_tokens if hasattr(response.usage, 'total_tokens') else 0
                } if response.usage else {},
                'turn': len(self.response_history) + 1
            }

            # Save to history
            self.response_history.append(response_data)

            return response_data

        except Exception as e:
            print(f"✗ Error creating response: {e}")
            return None

    def print_response(self, response_data: Dict[str, Any]):
        """Pretty print a response"""
        if not response_data:
            return

        print(f"\n{'=' * 60}")
        print(f"Turn {response_data['turn']}")
        print(f"{'=' * 60}")
        print(f"Response ID: {response_data['id']}")
        print(f"Model: {response_data['model']}")
        print(f"Status: {response_data.get('status', 'N/A')}")

        if response_data.get('instructions'):
            print(f"\nInstructions:")
            print(f"  {response_data['instructions']}")

        print(f"\nUser:")
        print(f"  {response_data['user_message']}")

        print(f"\nAssistant:")
        print(f"  {response_data['content']}")

        usage = response_data.get('usage', {})
        if usage:
            print(f"\nUsage:")
            print(f"  Input tokens: {usage.get('input_tokens', 'N/A')}")
            print(f"  Output tokens: {usage.get('output_tokens', 'N/A')}")
            print(f"  Total tokens: {usage.get('total_tokens', 'N/A')}")

    def print_history_summary(self):
        """Print summary of all response IDs in the conversation"""
        print(f"\n{'=' * 60}")
        print(f"Conversation History Summary")
        print(f"{'=' * 60}")
        print(f"Total turns: {len(self.response_history)}")
        print(f"\nResponse IDs by turn:")
        for turn in self.response_history:
            print(f"  Turn {turn['turn']}: {turn['id']}")


def main():
    # Parse command line arguments for demo-specific options
    parser = argparse.ArgumentParser(
        description='LlamaStack Responses API Demo - Verify OpenAI SDK compatibility',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run with stored configuration from ~/.lls_showroom_generated:
  python demos/responses/demo.py

  # Run with custom prompt:
  python demos/responses/demo.py --prompt "What is RAG?"

  # Run with explicit URLs:
  python demos/responses/demo.py https://llamastack-distribution.apps.example.com \\
      https://keycloak.apps.example.com

  # Run with full authentication and custom prompt:
  python demos/responses/demo.py https://llamastack-distribution.apps.example.com \\
      https://keycloak.apps.example.com developer dev123 --prompt "Explain embeddings"
        """
    )

    parser.add_argument('--prompt', type=str, default="What is a vector database?",
                        help='Initial question to ask (default: "What is a vector database?")')

    args, remaining = parser.parse_known_args()

    # Load configuration from command line args, secrets file, or environment variables
    # Pass remaining args to load_demo_config (handles the 5 standard params)
    config = load_demo_config(argv=[sys.argv[0]] + remaining)

    llamastack_url = config['llamastack_url']
    keycloak_url = config['keycloak_url']
    username = config['username']
    password = config['password']
    client_secret = config['client_secret']

    # Validate that we have at least the LlamaStack URL
    if not llamastack_url:
        print("Error: LLAMASTACK_URL is required")
        print("\nRun with --help for usage information")
        sys.exit(1)

    print("=" * 60)
    print("LlamaStack Responses API Demo")
    print("=" * 60)
    print(f"\nConnecting to: {llamastack_url}")
    if keycloak_url:
        print(f"Keycloak URL: {keycloak_url}")
        print(f"Username: {username}")

    # Initialize the demo
    demo = ResponsesDemo(llamastack_url, keycloak_url, username, password, client_secret)

    # Check health
    if not demo.check_health():
        print("\n✗ Cannot connect to LlamaStack. Please check the URL and try again.")
        sys.exit(1)

    # Define instructions for the conversation
    instructions = """You are a helpful AI assistant that specializes in explaining technology concepts.
When answering questions, be concise but informative. Keep all answers brief."""

    # Check if user provided a custom prompt
    is_custom_prompt = args.prompt != "What is a vector database?"

    if is_custom_prompt:
        # Single-turn mode: User wants to test their own question
        print("\n" + "=" * 60)
        print("Single-Turn Response Demo")
        print("=" * 60)
        print("\nTesting custom prompt with OpenAI SDK Responses API...")

        response1 = demo.create_response(
            user_message=args.prompt,
            instructions=instructions
        )

        if response1:
            demo.print_response(response1)
        else:
            print("\n✗ Failed to create response. Exiting.")
            sys.exit(1)

        print("\n" + "=" * 60)
        print("✅ Demo Complete!")
        print("=" * 60)
        print("\nSingle-turn response completed successfully.")
        print("OpenAI SDK Responses API compatibility verified with custom prompt.")
        print("\nTo see multi-turn conversation demo, run without --prompt option.")

    else:
        # Multi-turn mode: Full demo showing conversation capabilities
        print("\n" + "=" * 60)
        print("Multi-Turn Conversation Demo")
        print("=" * 60)
        print("\nThis demo will show:")
        print("  1. Using OpenAI SDK Responses API to verify LlamaStack API conformance")
        print("  2. Creating responses with system instructions")
        print("  3. Tracking response IDs for each turn")
        print("  4. Continuing conversations with context")

        # Turn 1: Create initial response with instructions
        print("\n" + "-" * 60)
        print("Creating Turn 1 with instructions...")
        print("-" * 60)

        response1 = demo.create_response(
            user_message=args.prompt,
            instructions=instructions
        )

        if response1:
            demo.print_response(response1)
        else:
            print("\n✗ Failed to create first response. Exiting.")
            sys.exit(1)

        # Turn 2: Continue conversation
        print("\n" + "-" * 60)
        print("Creating Turn 2 (continuing conversation)...")
        print("-" * 60)

        response2 = demo.create_response(
            user_message="Can you give me a practical example of when I would use one?"
        )

        if response2:
            demo.print_response(response2)
        else:
            print("\n✗ Failed to create second response.")

        # Turn 3: Continue conversation with another follow-up
        print("\n" + "-" * 60)
        print("Creating Turn 3 (another follow-up)...")
        print("-" * 60)

        response3 = demo.create_response(
            user_message="Based on that example, which vector database would you recommend?"
        )

        if response3:
            demo.print_response(response3)
        else:
            print("\n✗ Failed to create third response.")

        # Print summary
        demo.print_history_summary()

        print("\n" + "=" * 60)
        print("✅ Demo Complete!")
        print("=" * 60)
        print("\nThis demo showed:")
        print("  ✓ OpenAI SDK Responses API compatibility - verified LlamaStack API conformance")
        print("  ✓ Creating responses with system instructions")
        print("  ✓ Tracking response IDs for each conversation turn")
        print("  ✓ Maintaining conversation context across multiple turns")
        print("\nKey takeaways:")
        print("  - LlamaStack implements OpenAI-compatible Responses API")
        print("  - Successfully using OpenAI SDK Responses API verifies API conformance")
        print("  - Response IDs are unique and trackable across turns")
        print("  - Instructions persist throughout the conversation")
        print("  - Context is maintained by including previous messages")


if __name__ == "__main__":
    main()
