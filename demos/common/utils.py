"""
Common utilities for LlamaStack demos.

Provides shared authentication, configuration, and helper functions.
"""

import requests
from typing import Optional


# Default Keycloak configuration
KEYCLOAK_REALM = "llamastack-demo"
KEYCLOAK_CLIENT_ID = "llamastack"


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
