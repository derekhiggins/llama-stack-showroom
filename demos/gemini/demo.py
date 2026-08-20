#!/usr/bin/env python3
"""
Gemini Remote Provider Demo - Chat Completion via remote::gemini

This demo verifies the optional Google Gemini remote inference provider. It:
1. Loads configuration (URLs and credentials)
2. Optionally authenticates with Keycloak
3. Sends a single chat completion request routed to a Gemini model

It only works when the OGX server was deployed with a Gemini API key
(ogx.gemini.apiKey / SHOWROOM_GEMINI_API_KEY). When no key is configured,
./test.sh skips this demo.

Usage:
    uv run demos/gemini/demo.py

The script reads configuration from environment variables. The Gemini model
can be overridden via GEMINI_INFERENCE_MODEL (default: gemini/models/gemini-2.5-flash).
"""

import os
import sys
from pathlib import Path
from openai import OpenAI

# Add project root to path for imports
PROJECT_ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from demos.common.utils import get_keycloak_token, load_demo_config


def main():
    print("=" * 60)
    print("OGX Gemini Remote Provider Demo")
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

    # Send a simple chat completion request routed to Gemini
    gemini_model = os.environ.get('GEMINI_INFERENCE_MODEL', 'gemini/models/gemini-2.5-flash')
    print(f"\nSending chat completion request to Gemini model: {gemini_model}")
    print("Prompt: 'Say hello in exactly 5 words'")
    print()

    try:
        response = client.chat.completions.create(
            model=gemini_model,
            messages=[
                {"role": "user", "content": "Say hello in exactly 5 words"}
            ],
            # Gemini 2.5+ are "thinking" models: reasoning tokens count against
            # max_tokens, so leave enough headroom for a visible answer.
            max_tokens=512,
        )

        # Print the response
        message = response.choices[0].message.content
        print("Response:")
        print(f"  {message}")
        print()

        print("✓ Gemini chat completion successful!")
        print(f"  Model: {response.model}")
        print(f"  Tokens: {response.usage.total_tokens} total")
        print(f"    - Prompt: {response.usage.prompt_tokens}")
        print(f"    - Completion: {response.usage.completion_tokens}")

    except Exception as e:
        print(f"✗ Gemini chat completion failed: {e}")
        sys.exit(1)

    print()
    print("=" * 60)


if __name__ == "__main__":
    main()
