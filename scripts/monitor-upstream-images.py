#!/usr/bin/env python3
"""Watch Nextcloud base digests and published GHCR provenance.

Only suggest a rebuild once every maintained upstream base has a supported,
up-to-date PHP release. Published amd64 and arm64 images must identify the
exact upstream base digest and source revision used in their builds.
"""

import argparse
import importlib.util
import json
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
POLICY_SPEC = importlib.util.spec_from_file_location(
    "php_runtime_policy", ROOT / "scripts/check-php-runtime.py"
)
policy = importlib.util.module_from_spec(POLICY_SPEC)
POLICY_SPEC.loader.exec_module(policy)

PLATFORMS = ("linux/amd64", "linux/arm64")
DIGEST_PATTERN = re.compile(r"^sha256:[0-9a-f]{64}$")
APP_IMAGE = "ghcr.io/librecodecoop/nextcloud-docker-app"


class InspectionError(Exception):
    pass


class MissingPlatformError(InspectionError):
    pass


def inspect(reference, template):
    command = ["docker", "buildx", "imagetools", "inspect", reference, "--format", template]
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=False, timeout=45)
    except (OSError, subprocess.SubprocessError) as exc:
        raise InspectionError(f"Cannot inspect {reference}: {exc}") from exc
    if result.returncode:
        message = result.stderr.strip() or result.stdout.strip()
        # Only a missing published image is a first-build condition.
        if re.search(r"(?:manifest unknown|not found|404 Not Found)", message, re.I):
            raise FileNotFoundError(reference) from None
        raise InspectionError(f"Cannot inspect {reference}: {message[:250]}")
    try:
        return json.loads(result.stdout)
    except ValueError as exc:
        raise InspectionError(f"Invalid OCI metadata for {reference}") from exc


def manifest_digest(reference):
    document = inspect(reference, "{{json .Manifest}}")
    digest = document.get("digest") if isinstance(document, dict) else None
    if not isinstance(digest, str) or not DIGEST_PATTERN.fullmatch(digest):
        raise InspectionError(f"Missing valid digest for {reference}")
    return digest


def image_config(reference):
    document = inspect(reference, "{{json .Image}}")
    if not isinstance(document, dict):
        raise InspectionError(f"Missing image configuration for {reference}")
    configs = {}
    for platform in PLATFORMS:
        value = document.get(platform)
        if not isinstance(value, dict) or not isinstance(value.get("config"), dict):
            raise MissingPlatformError(f"{reference} has no {platform} image configuration")
        configs[platform] = value["config"]
    return configs


def php_version(config):
    variables = config.get("Env")
    if not isinstance(variables, list):
        raise InspectionError("Image configuration has no environment variables")
    versions = [part.removeprefix("PHP_VERSION=") for part in variables
                if isinstance(part, str) and part.startswith("PHP_VERSION=")]
    if len(versions) != 1:
        raise InspectionError("Could not determine a unique PHP_VERSION from official base metadata")
    policy.parse_version(versions[0])
    return versions[0]


def published_status(reference, upstream_digest, revision):
    try:
        configs = image_config(reference)
    except FileNotFoundError:
        return ["published image missing"]
    except MissingPlatformError as exc:
        return [str(exc)]
    reasons = []
    for platform, config in configs.items():
        labels = config.get("Labels") or {}
        if labels.get("coop.librecode.nextcloud.base.digest") != upstream_digest:
            reasons.append(f"{platform}: upstream base digest differs or was not recorded")
        if labels.get("org.opencontainers.image.revision") != revision:
            reasons.append(f"{platform}: published Git revision differs or was not recorded")
    return reasons


def evaluate(versions, releases, revision, image_prefix=APP_IMAGE):
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise InspectionError("Expected the reviewed 40-digit Git revision")
    if not isinstance(versions, dict) or not isinstance(versions.get("versions"), list):
        raise InspectionError("Invalid reviewed Nextcloud version manifest")
    entries = versions["versions"]
    if not entries:
        raise InspectionError("The reviewed Nextcloud version manifest is empty")

    rows = []
    blocked = False
    rebuild = False
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("major"), int):
            raise InspectionError("Malformed Nextcloud version entry")
        major = entry["major"]
        release = entry.get("release")
        if not isinstance(release, str) or not re.fullmatch(rf"{major}\.[0-9]+\.[0-9]+", release):
            raise InspectionError(f"Invalid release for Nextcloud {major}")
        upstream = f"nextcloud:{release}-fpm"
        published = f"{image_prefix}:{major}-fpm"
        digest = manifest_digest(upstream)
        configs = image_config(f"nextcloud@{digest}")
        php_versions = {platform: php_version(config) for platform, config in configs.items()}
        problems = []
        for platform, version in php_versions.items():
            try:
                policy.check_release(version, releases)
            except policy.SecurityPolicyError as exc:
                problems.append(f"{platform}: {exc}")
        if problems:
            blocked = True
            status = "Awaiting patched upstream"
            reason = "; ".join(problems)
        else:
            differences = published_status(published, digest, revision)
            if differences:
                rebuild = True
                status = "Rebuild required"
                reason = "; ".join(differences)
            else:
                status = "Up to date"
                reason = "Both published platforms match the upstream digest and Git revision"
        rows.append({
            "major": major, "release": release, "upstream_digest": digest,
            "php": php_versions, "status": status, "reason": reason,
        })
    # Publishing stable aliases requires all maintained versions to pass.
    return {"rebuild": rebuild and not blocked, "blocked": blocked, "rows": rows}


def render_summary(result):
    lines = [
        "## Nextcloud upstream image monitor",
        "",
        "Compares reviewed upstream Docker image digests and actual PHP versions "
        "against the metadata of both published GHCR architectures.",
        "",
        "| Nextcloud | PHP amd64 / arm64 | Status | Details |",
        "| --- | --- | --- | --- |",
    ]
    for row in result["rows"]:
        versions = " / ".join(row["php"][platform] for platform in PLATFORMS)
        detail = row["reason"].replace("|", "/").replace("\n", " ")
        lines.append(f"| {row['release']} | {versions} | {row['status']} | {detail} |")
    lines.extend([
        "", f"**Blocked by upstream PHP:** {result['blocked']}",
        f"**Rebuild requested:** {result['rebuild']}", "",
        "If PHP has a new upstream release but Nextcloud still embeds the old "
        "interpreter, wait for the base to change. Rebuilding that same "
        "unpatched base would not resolve the vulnerability.",
    ])
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--versions", default=".github/nextcloud-supported.json")
    parser.add_argument("--revision", default=os.environ.get("GITHUB_SHA", ""))
    parser.add_argument("--output", help="GitHub Actions output file")
    parser.add_argument("--summary", help="GitHub Actions step summary")
    parser.add_argument("--report", help="Write Markdown for a tracking issue")
    parser.add_argument("--releases-file", help="Use a checked offline release fixture")
    args = parser.parse_args(argv)
    try:
        with open(args.versions, encoding="utf-8") as stream:
            versions = json.load(stream)
        if args.releases_file:
            with open(args.releases_file, encoding="utf-8") as stream:
                releases = json.load(stream)
        else:
            releases = policy.fetch_releases()
        result = evaluate(versions, releases, args.revision)
        summary = render_summary(result)
        print(summary)
        if args.output:
            with open(args.output, "a", encoding="utf-8") as stream:
                stream.write(f"rebuild={str(result['rebuild']).lower()}\n")
                stream.write(f"blocked={str(result['blocked']).lower()}\n")
        for path in (args.summary, args.report):
            if path:
                with open(path, "a", encoding="utf-8") as stream:
                    stream.write(summary)
        return 0
    except (OSError, ValueError, InspectionError, policy.SecurityPolicyError) as exc:
        print(f"Upstream image inspection failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
