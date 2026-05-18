#!/usr/bin/env python3
"""
Hello World Demo - Minimal OGX Chat Completion Example

This is the simplest possible OGX demo. It shows how to:
1. Load configuration (URLs and credentials)
2. Optionally authenticate with Keycloak
3. Send a single chat completion request

Usage:
    uv run demos/hello/demo.py

The script reads configuration from environment variables.
"""

import sys
from pathlib import Path
from openai import OpenAI

# Add project root to path for imports
PROJECT_ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from demos.common.utils import get_keycloak_token, load_demo_config


def main():
    print("=" * 60)
    print("OGX Hello World Demo")
    print("=" * 60)

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
            api_key = get_keycloak_token(keycloak_url, username, password, client_secret)
        except Exception as e:
            print(f"✗ Authentication failed: {e}")
            sys.exit(1)

    # Initialize OpenAI client
    client = OpenAI(
        base_url=f"{ogx_url}/v1",
        api_key=api_key,
    )

    # Send a simple chat completion request
    print("\nSending chat completion request...")
    print("Prompt: 'Say hello in exactly 5 words'")
    print()

    try:
        response = client.chat.completions.create(
            model="vllm-inference/llama-3-2-3b",
            messages=[
                {"role": "user", "content": "Say hello in exactly 5 words"}
            ],
            max_tokens=50,
        )

        # Print the response
        message = response.choices[0].message.content
        print("Response:")
        print(f"  {message}")
        print()

        print("✓ Chat completion successful!")
        print(f"  Model: {response.model}")
        print(f"  Tokens: {response.usage.total_tokens} total")
        print(f"    - Prompt: {response.usage.prompt_tokens}")
        print(f"    - Completion: {response.usage.completion_tokens}")

    except Exception as e:
        print(f"✗ Chat completion failed: {e}")
        sys.exit(1)

    print()
    print("=" * 60)


if __name__ == "__main__":
    main()
