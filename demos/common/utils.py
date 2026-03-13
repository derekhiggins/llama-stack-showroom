"""
Common utilities for LlamaStack demos.

Provides shared authentication, configuration, and helper functions.
"""

import os
import sys
import requests
from typing import Optional, Dict
from pathlib import Path

# Import secrets_util from scripts
PROJECT_ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from scripts.secrets_util import get_or_set, get


# Default Keycloak configuration
KEYCLOAK_REALM = "llamastack-demo"
KEYCLOAK_CLIENT_ID = "llamastack"


def load_demo_config(
    argv: Optional[list] = None,
    arg_offset: int = 1
) -> Dict[str, Optional[str]]:
    """
    Load demo configuration from command line args, secrets file, or environment variables.

    Priority order: command line args > secrets file > environment variables

    Args:
        argv: Command line arguments (default: sys.argv)
        arg_offset: Offset to start reading args from (default: 1, skipping script name)

    Returns:
        Dictionary with keys:
            - llamastack_url: LlamaStack base URL
            - keycloak_url: Keycloak base URL (optional)
            - username: Keycloak username (optional)
            - password: Keycloak password (optional)
            - client_secret: OAuth2 client secret (optional)

    Example:
        config = load_demo_config()
        demo = MyDemo(
            config['llamastack_url'],
            config['keycloak_url'],
            config['username'],
            config['password'],
            config['client_secret']
        )
    """
    if argv is None:
        argv = sys.argv

    # Helper to get value from argv, secrets file, or env var
    def get_arg(index: int, secret_key: str, env_key: str, use_get_or_set: bool = False) -> Optional[str]:
        # Try command line arg
        if len(argv) > index:
            return argv[index]
        # Try secrets file or env var
        if use_get_or_set:
            return get_or_set(secret_key)
        else:
            return get(secret_key) or os.environ.get(env_key)

    return {
        'llamastack_url': get_arg(arg_offset, 'LLAMASTACK_URL', 'LLAMASTACK_URL'),
        'keycloak_url': get_arg(arg_offset + 1, 'KEYCLOAK_URL', 'KEYCLOAK_URL'),
        'username': get_arg(arg_offset + 2, 'KEYCLOAK_USERNAME', 'KEYCLOAK_USERNAME'),
        'password': get_arg(arg_offset + 3, 'KEYCLOAK_PASSWORD', 'KEYCLOAK_PASSWORD'),
        'client_secret': get_arg(arg_offset + 4, 'KEYCLOAK_CLIENT_SECRET', 'KEYCLOAK_CLIENT_SECRET', use_get_or_set=True),
    }


def get_keycloak_token(
    keycloak_url: str,
    username: str,
    password: str,
    client_secret: str,
    verbose: bool = True,
    realm: str = KEYCLOAK_REALM,
    client_id: str = KEYCLOAK_CLIENT_ID
) -> str:
    """
    Get JWT access token from Keycloak.

    Args:
        keycloak_url: Base Keycloak URL (e.g., https://keycloak.example.com)
        username: Keycloak username
        password: User password
        client_secret: OAuth2 client secret
        verbose: Print authentication progress (default: True)
        realm: Keycloak realm name (default: llamastack-demo)
        client_id: OAuth2 client ID (default: llamastack)

    Returns:
        JWT access token string

    Raises:
        requests.HTTPError: If authentication fails
        KeyError: If response doesn't contain access_token
    """
    keycloak_url = keycloak_url.rstrip('/')
    token_url = f"{keycloak_url}/realms/{realm}/protocol/openid-connect/token"

    payload = {
        'client_id': client_id,
        'client_secret': client_secret,
        'username': username,
        'password': password,
        'grant_type': 'password'
    }

    if verbose:
        print(f"\n🔐 Authenticating with Keycloak as '{username}'...")

    response = requests.post(token_url, data=payload, verify=True)
    response.raise_for_status()

    token_data = response.json()
    access_token = token_data.get('access_token')

    if not access_token:
        raise KeyError("No access_token in Keycloak response")

    if verbose:
        print(f"✓ Authentication successful")
        print(f"  Token type: {token_data.get('token_type', 'Bearer')}")
        print(f"  Expires in: {token_data.get('expires_in', 'unknown')} seconds")

    return access_token
