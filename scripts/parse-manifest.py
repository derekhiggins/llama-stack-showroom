#!/usr/bin/env python3
"""
Parse demos/manifest.yaml and output filtered demos.

Usage:
    python scripts/parse-manifest.py [tag1,tag2,...]

Output format (one per line):
    path|name|type|requires_key
"""

import sys
import yaml
from pathlib import Path


def main():
    # Get filter tags from command line (comma-separated or "all")
    filter_tags = sys.argv[1] if len(sys.argv) > 1 else "all"

    # Parse manifest
    manifest_path = Path(__file__).parent.parent / "demos" / "manifest.yaml"
    with open(manifest_path) as f:
        manifest = yaml.safe_load(f)

    demos = manifest.get("demos", [])

    # Filter demos by tags
    for demo in demos:
        path = demo.get("path", "")
        tags = demo.get("tags", [])
        name = demo.get("name", "")
        demo_type = demo.get("type", "python")
        requires_key = demo.get("requires_key", "")

        # Check if demo matches filter
        if should_run(tags, filter_tags):
            print(f"{path}|{name}|{demo_type}|{requires_key}")


def should_run(demo_tags, filter_tags):
    """Check if demo should run based on filter tags."""
    if filter_tags == "all":
        return True

    # Split filter by comma
    filters = [f.strip() for f in filter_tags.split(",")]

    # Check if any filter tag matches any demo tag (OR logic)
    for filter_tag in filters:
        if filter_tag in demo_tags:
            return True

    return False


if __name__ == "__main__":
    main()
