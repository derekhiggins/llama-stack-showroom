#!/usr/bin/env python3
"""
Read secrets and routes from the Kubernetes cluster.

Usage as module:
    from scripts.read_k8s import get_secret, get_route_url

Usage as CLI:
    python scripts/read_k8s.py secret keycloak-secret KEYCLOAK_PASSWORD
    python scripts/read_k8s.py route ogx-distribution
"""

import os
import subprocess
import sys
from typing import Optional

NAMESPACE = os.environ.get("NAMESPACE", "redhat-ods-applications")


def _run_oc(args: list[str]) -> Optional[str]:
    try:
        result = subprocess.run(
            ["oc"] + args,
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return None


def get_secret(secret_name: str, key: str, namespace: str = NAMESPACE) -> Optional[str]:
    """Read a decoded secret value from the cluster."""
    encoded = _run_oc([
        "get", "secret", secret_name,
        "-n", namespace,
        "-o", f"jsonpath={{.data.{key}}}",
    ])
    if not encoded:
        return None
    import base64
    return base64.b64decode(encoded).decode()


def get_route_url(route_name: str, namespace: str = NAMESPACE) -> Optional[str]:
    """Read a route's URL (https if TLS, else http)."""
    host = _run_oc([
        "get", "route", route_name,
        "-n", namespace,
        "-o", "jsonpath={.spec.host}",
    ])
    if not host:
        return None
    tls = _run_oc([
        "get", "route", route_name,
        "-n", namespace,
        "-o", "jsonpath={.spec.tls}",
    ])
    scheme = "https" if tls else "http"
    return f"{scheme}://{host}"


def main():
    if len(sys.argv) < 3:
        print("Usage:", file=sys.stderr)
        print("  read_k8s.py secret <name> <key> [-n namespace]", file=sys.stderr)
        print("  read_k8s.py route <name> [-n namespace]", file=sys.stderr)
        sys.exit(1)

    ns = NAMESPACE
    if "-n" in sys.argv:
        idx = sys.argv.index("-n")
        ns = sys.argv[idx + 1]
        sys.argv = sys.argv[:idx] + sys.argv[idx + 2:]

    cmd = sys.argv[1]

    if cmd == "secret":
        if len(sys.argv) < 4:
            print("Usage: read_k8s.py secret <name> <key>", file=sys.stderr)
            sys.exit(1)
        value = get_secret(sys.argv[2], sys.argv[3], ns)
        if value is None:
            sys.exit(1)
        print(value)

    elif cmd == "route":
        value = get_route_url(sys.argv[2], ns)
        if value is None:
            sys.exit(1)
        print(value)

    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
