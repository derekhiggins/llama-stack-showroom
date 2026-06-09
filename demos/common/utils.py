"""
Common utilities for OGX demos.

Provides shared authentication, configuration, and helper functions.
"""

import os
import sys
import requests
from typing import Optional, Dict
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from scripts.read_k8s import get_secret, get_route_url

KEYCLOAK_REALM = "ogx-demo"
KEYCLOAK_CLIENT_ID = "ogx"


def load_demo_config(
    argv: Optional[list] = None,
    arg_offset: int = 1
) -> Dict[str, Optional[str]]:
    """
    Load demo configuration from command line args, K8s cluster, or environment variables.

    Priority order: command line args > K8s cluster > environment variables
    """
    if argv is None:
        argv = sys.argv

    def get_arg(index: int, env_key: str, k8s_fn=None) -> Optional[str]:
        if len(argv) > index:
            return argv[index]
        if k8s_fn is not None:
            value = k8s_fn()
            if value:
                return value
        return os.environ.get(env_key)

    return {
        'ogx_url': get_arg(
            arg_offset, 'OGX_URL',
            lambda: get_route_url("ogx-distribution"),
        ),
        'keycloak_url': get_arg(
            arg_offset + 1, 'KEYCLOAK_URL',
            lambda: get_route_url("keycloak"),
        ),
        'username': get_arg(
            arg_offset + 2, 'KEYCLOAK_USERNAME',
            lambda: get_secret("keycloak-secret", "KEYCLOAK_USERNAME") or "admin",
        ),
        'password': get_arg(
            arg_offset + 3, 'KEYCLOAK_ADMIN_PASSWORD',
            lambda: get_secret("keycloak-secret", "KEYCLOAK_ADMIN_PASSWORD"),
        ),
        'client_secret': get_arg(
            arg_offset + 4, 'KEYCLOAK_CLIENT_SECRET',
            lambda: get_secret("keycloak-secret", "KEYCLOAK_CLIENT_SECRET"),
        ),
        'grafana_url': get_arg(
            arg_offset + 5, 'GRAFANA_URL',
            lambda: get_route_url("grafana"),
        ),
        'grafana_password': get_arg(
            arg_offset + 6, 'GRAFANA_ADMIN_PASSWORD',
            lambda: get_secret("grafana-secret", "GRAFANA_ADMIN_PASSWORD"),
        ),
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
