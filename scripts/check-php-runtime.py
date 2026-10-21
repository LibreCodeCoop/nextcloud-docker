#!/usr/bin/env python3
"""Reject out-of-date or EOL official PHP runtimes before image publication.

The upstream PHP release feed owns the version policy. This script does not
maintain CVE-specific version ranges and is intended for upstream-derived images.
"""

import argparse
import json
import re
import subprocess
import sys
import urllib.request

RELEASES_URL = "https://www.php.net/releases/branches.php"
VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
SUPPORTED_STATES = frozenset(("stable", "security"))


class SecurityPolicyError(Exception):
    pass


def parse_version(value):
    if not isinstance(value, str) or not VERSION_RE.fullmatch(value):
        raise SecurityPolicyError(f"Invalid stable PHP version: {value!r}")
    return tuple(int(part) for part in value.split("."))


def check_release(version, releases):
    current = parse_version(version)
    if not isinstance(releases, list) or not releases:
        raise SecurityPolicyError("PHP release feed is empty or invalid")

    branch_name = f"{current[0]}.{current[1]}"
    matching = [r for r in releases if isinstance(r, dict) and r.get("branch") == branch_name]
    if len(matching) != 1:
        raise SecurityPolicyError(f"PHP {branch_name} is missing or duplicated in the upstream release feed")

    record = matching[0]
    if record.get("state") not in SUPPORTED_STATES:
        raise SecurityPolicyError(f"PHP {branch_name} has no upstream security support (state: {record.get('state')!r})")

    latest = parse_version(record.get("latest"))
    if latest[:2] != current[:2]:
        raise SecurityPolicyError(f"Inconsistent PHP release feed for {branch_name}: {record.get('latest')!r}")

    if current < latest:
        raise SecurityPolicyError(
            f"PHP {version} is older than the upstream {branch_name} release {record['latest']}"
        )
    return f"PHP {version}: supported branch and current upstream patch release"


def fetch_releases():
    req = urllib.request.Request(
        RELEASES_URL,
        headers={"Accept": "application/json", "User-Agent": "LibreCode-PHP-Runtime-Check/1"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            return json.load(response)
    except (OSError, ValueError) as exc:
        raise SecurityPolicyError(f"Cannot read upstream PHP release feed: {exc}") from exc


def container_php_version(image, platform):
    if platform not in ("linux/amd64", "linux/arm64"):
        raise SecurityPolicyError(f"Unsupported image platform: {platform!r}")
    if not image or image.startswith("-"):
        raise SecurityPolicyError("An existing, fully named Docker image is required")
    command = [
        "docker", "run", "--rm", "--network", "none", "--read-only",
        "--platform", platform, "--entrypoint", "php", image, "-v",
    ]
    try:
        result = subprocess.run(
            command, capture_output=True, text=True, timeout=45, check=True,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise SecurityPolicyError(f"Cannot determine PHP version in {image}: {exc}") from exc
    for line in result.stdout.splitlines():
        match = re.match(r"^PHP ([0-9]+\.[0-9]+\.[0-9]+)(?:\s|$)", line.strip())
        if match:
            return match.group(1)
    raise SecurityPolicyError(f"Cannot parse PHP version from {image}: {result.stdout[:120]!r}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--image", help="Locally built Docker image")
    source.add_argument("--version", help="PHP version (for tests and diagnostics)")
    parser.add_argument("--platform", default="linux/amd64", choices=("linux/amd64", "linux/arm64"))
    parser.add_argument("--releases-file", help="Use a local PHP release feed (offline tests)")
    args = parser.parse_args(argv)
    try:
        version = args.version if args.version is not None else container_php_version(args.image, args.platform)
        if args.releases_file:
            with open(args.releases_file, encoding="utf-8") as handle:
                releases = json.load(handle)
        else:
            releases = fetch_releases()
        print(check_release(version, releases))
        return 0
    except (SecurityPolicyError, OSError, ValueError) as exc:
        print(f"PHP runtime security check failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
