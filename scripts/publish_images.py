#!/usr/bin/env python3
"""Stage tested multi-architecture images and promote only after all CI gates pass."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

from nextcloud_versions import read_manifest

ARCHITECTURES = ("amd64", "arm64")
GIT_SHA = re.compile(r"^[a-f0-9]{40}$")
IMAGE = re.compile(r"^[a-z0-9.-]+(?::[0-9]+)?/[a-z0-9._/-]+$")


def run(*arguments: str) -> None:
    subprocess.run(["docker", *arguments], check=True)


def validate(image: str, revision: str) -> None:
    if not IMAGE.fullmatch(image):
        raise ValueError(f"Unsafe image reference: {image!r}")
    if not GIT_SHA.fullmatch(revision):
        raise ValueError("Expected the full 40-character Git commit SHA")


def staging_tag(image: str, revision: str, component: str, arch: str) -> str:
    assert arch in ARCHITECTURES
    if component == "web":
        return f"{image}:sha-{revision}-web-{arch}"
    if not re.fullmatch(r"[2-9]\d-fpm", component):
        raise ValueError(f"Invalid Nextcloud channel: {component}")
    return f"{image}:sha-{revision}-{component}-{arch}"


def stage(image: str, revision: str, component: str) -> None:
    validate(image, revision)
    if component != "web" and not re.fullmatch(r"[2-9]\d-fpm", component):
        raise ValueError("Expected a stable Nextcloud major-fpm tag")
    local_component = "web" if component == "web" else "app"
    for arch in ARCHITECTURES:
        local = f"scan/{local_component}:{arch}"
        remote = staging_tag(image, revision, component, arch)
        run("tag", local, remote)
        run("push", remote)


def manifest(image: str, tag: str, sources: list[str]) -> None:
    if len(sources) != 2:
        raise ValueError("A manifest must combine exactly amd64 and arm64")
    run("buildx", "imagetools", "create", "--tag", f"{image}:{tag}", *sources)
    run("buildx", "imagetools", "inspect", f"{image}:{tag}")


def promote(app_image: str, web_image: str, revision: str, manifest_file: Path) -> None:
    validate(app_image, revision)
    validate(web_image, revision)
    versions = read_manifest(manifest_file)["versions"]
    # Publish stable versioned manifests before moving any alias.
    for entry in versions:
        tag = f"{entry['major']}-fpm"
        sources = [staging_tag(app_image, revision, tag, arch) for arch in ARCHITECTURES]
        manifest(app_image, tag, sources)
        manifest(app_image, f"{entry['release']}-fpm", sources)
    current = f"{versions[-1]['major']}-fpm"
    current_sources = [staging_tag(app_image, revision, current, arch) for arch in ARCHITECTURES]
    # Both aliases move only after every supported version has passed all jobs.
    manifest(app_image, "stable-fpm", current_sources)
    manifest(app_image, "latest", current_sources)

    web_sources = [staging_tag(web_image, revision, "web", arch) for arch in ARCHITECTURES]
    manifest(web_image, "main", web_sources)
    # Keep the existing web latest consumers on a tested web runtime.
    manifest(web_image, "latest", web_sources)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    app = sub.add_parser("stage-app")
    app.add_argument("--image", required=True)
    app.add_argument("--revision", required=True)
    app.add_argument("--tag", required=True)
    web = sub.add_parser("stage-web")
    web.add_argument("--image", required=True)
    web.add_argument("--revision", required=True)
    promote_cmd = sub.add_parser("promote")
    promote_cmd.add_argument("--app-image", required=True)
    promote_cmd.add_argument("--web-image", required=True)
    promote_cmd.add_argument("--revision", required=True)
    promote_cmd.add_argument("--file", type=Path, default=Path(".github/nextcloud-supported.json"))
    args = parser.parse_args()
    try:
        if args.action == "stage-app":
            stage(args.image, args.revision, args.tag)
        elif args.action == "stage-web":
            stage(args.image, args.revision, "web")
        else:
            promote(args.app_image, args.web_image, args.revision, args.file)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"::error title=Container publication failed::{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
