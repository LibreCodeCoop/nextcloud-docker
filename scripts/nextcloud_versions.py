#!/usr/bin/env python3
"""Discover maintained Nextcloud releases and validate the reviewed CI manifest."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

SOURCE = "https://github.com/nextcloud/server/wiki/Maintenance-and-Release-Schedule"
MARKDOWN_URL = "https://raw.githubusercontent.com/wiki/nextcloud/server/Maintenance-and-Release-Schedule.md"
DEFAULT_MANIFEST = Path(".github/nextcloud-supported.json")
SECTION = re.compile(r"^#{1,6}\s+Currently\s+(?:supported|maintained)\s+versions?\s*$", re.I)
HEADING = re.compile(r"^#{1,3}\s+")
RELEASE = re.compile(r"^\d{2,3}\.\d+\.\d+$")
REQUIRED_COLUMNS = {"version code", "release date", "end of life", "current version"}


class VersionError(ValueError):
    """Unexpected upstream or manifest structure; never guess a release list."""


def cells(line: str) -> list[str]:
    return [re.sub(r"\s+", " ", cell.strip().replace("**", "").replace(chr(96), ""))
            for cell in line.strip().strip("|").split("|")]


def table_after(lines: list[str], start: int, end: int) -> list[dict[str, str]]:
    for index in range(start, end - 1):
        if not lines[index].lstrip().startswith("|"):
            continue
        header = [col.lower() for col in cells(lines[index])]
        if not REQUIRED_COLUMNS.issubset(set(header)):
            continue
        separator = cells(lines[index + 1])
        if len(separator) != len(header) or not all(re.fullmatch(r":?-{3,}:?", col) for col in separator):
            raise VersionError("Supported-version table separator has changed")
        rows = []
        for line in lines[index + 2:end]:
            if not line.lstrip().startswith("|"):
                break
            values = cells(line)
            if len(values) != len(header):
                raise VersionError("Supported-version table row has a different column count")
            rows.append(dict(zip(header, values)))
        if not rows:
            raise VersionError("Supported-version table has no data rows")
        return rows
    raise VersionError("Supported-version table or required columns not found")


def parse_wiki(markdown: str, today: dt.date | None = None) -> dict:
    today = today or dt.datetime.now(dt.timezone.utc).date()
    lines = markdown.splitlines()
    start = next((i for i, line in enumerate(lines) if SECTION.fullmatch(line.strip())), None)
    if start is None:
        raise VersionError("No 'Currently supported/maintained versions' section")
    end = next((i for i in range(start + 1, len(lines)) if HEADING.match(lines[i])), len(lines))
    rows = table_after(lines, start + 1, end)
    versions = []
    for row in rows:
        try:
            major = int(row["version code"])
        except ValueError as error:
            raise VersionError(f"Invalid major version: {row['version code']!r}") from error
        match = re.match(r"^(\d{2,3}\.\d+\.\d+)(?:\s|$)", row["current version"])
        release = match.group(1) if match else ""
        eol = row["end of life"]
        if not RELEASE.fullmatch(release) or int(release.split(".", 1)[0]) != major:
            raise VersionError(f"Invalid current release for Nextcloud {major}: {row['current version']!r}")
        try:
            eol_date = dt.date.fromisoformat(eol + "-01")
            released = dt.date.fromisoformat(row["release date"])
        except ValueError as error:
            raise VersionError(f"Invalid release/EOL date for Nextcloud {major}") from error
        if eol_date.year < today.year or (eol_date.year == today.year and eol_date.month < today.month):
            raise VersionError(f"Upstream still lists Nextcloud {major} although EOL month {eol} has passed")
        if released > today:
            raise VersionError(f"Nextcloud {major} is listed before its release date")
        versions.append({"major": major, "release": release, "eol": eol})
    # Independently check that no proposed major is listed as End of Life.
    eol_start = next((i for i, line in enumerate(lines) if re.match(r"^#{1,3}\s+EOL Versions\s*$", line, re.I)), None)
    if eol_start is None:
        raise VersionError("Missing 'EOL Versions' section")
    eol_end = next((i for i in range(eol_start + 1, len(lines)) if HEADING.match(lines[i])), len(lines))
    eol_majors = set()
    for line in lines[eol_start + 1:eol_end]:
        if line.lstrip().startswith("|"):
            first = cells(line)[0]
            if first.isdigit():
                eol_majors.add(int(first))
    conflict = eol_majors.intersection(v["major"] for v in versions)
    if conflict:
        raise VersionError(f"Versions listed as both supported and EOL: {sorted(conflict)}")
    manifest = {"schema_version": 1, "source": SOURCE, "versions": sorted(versions, key=lambda x: x["major"])}
    validate_manifest(manifest, today=today)
    return manifest


def validate_manifest(manifest: dict, today: dt.date | None = None) -> list[dict]:
    today = today or dt.datetime.now(dt.timezone.utc).date()
    if not isinstance(manifest, dict) or manifest.get("schema_version") != 1 or manifest.get("source") != SOURCE:
        raise VersionError("Unknown supported-versions schema or provenance")
    versions = manifest.get("versions")
    if not isinstance(versions, list) or not 1 <= len(versions) <= 5:
        raise VersionError("Expected between one and five maintained majors")
    majors = []
    for entry in versions:
        if not isinstance(entry, dict) or set(entry) != {"major", "release", "eol"}:
            raise VersionError("Malformed version entry")
        major, release, eol = entry["major"], entry["release"], entry["eol"]
        if type(major) is not int or not 20 <= major <= 99 or not isinstance(release, str):
            raise VersionError("Invalid major or release type")
        if not RELEASE.fullmatch(release) or int(release.split(".", 1)[0]) != major:
            raise VersionError(f"Invalid release for major {major}")
        if not isinstance(eol, str) or not re.fullmatch(r"20\d{2}-(0[1-9]|1[0-2])", eol):
            raise VersionError(f"Invalid EOL month for major {major}")
        if eol < today.strftime("%Y-%m"):
            raise VersionError(f"Nextcloud {major} has reached EOL ({eol}); update the approved manifest")
        majors.append(major)
    if sorted(set(majors)) != majors:
        raise VersionError("Majors must be unique and sorted ascending")
    if any(b - a != 1 for a, b in zip(majors, majors[1:])):
        raise VersionError("Unexpected gap in supported majors; review the upstream schedule")
    return versions


def request_json(url: str) -> dict:
    headers = {"User-Agent": "librecode-nextcloud-version-discovery", "Accept": "application/json"}
    if "api.github.com" in url and os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = "Bearer " + os.environ["GITHUB_TOKEN"]
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=20) as response:
        return json.load(response)


def verify_upstream(versions: list[dict]) -> None:
    """Require an official stable release and an FPM image for each proposed version."""
    for item in versions:
        release = item["release"]
        published = request_json(
            f"https://api.github.com/repos/nextcloud-releases/server/releases/tags/v{release}"
        )
        if published.get("tag_name") != f"v{release}" or published.get("prerelease") or published.get("draft"):
            raise VersionError(f"Nextcloud {release} is not an official stable GitHub release")
        docker_tag = request_json(
            f"https://hub.docker.com/v2/repositories/library/nextcloud/tags/{release}-fpm"
        )
        if docker_tag.get("name") != f"{release}-fpm":
            raise VersionError(f"Official Docker image nextcloud:{release}-fpm is unavailable")
        platforms = {(i.get("os"), i.get("architecture")) for i in docker_tag.get("images", [])}
        if not {("linux", "amd64"), ("linux", "arm64")}.issubset(platforms):
            raise VersionError(f"nextcloud:{release}-fpm lacks amd64 or arm64")


def read_manifest(path: Path) -> dict:
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise VersionError(f"Cannot load reviewed supported versions at {path}: {error}") from error
    validate_manifest(manifest)
    return manifest


def append_summary(message: str) -> None:
    print(message)
    if os.getenv("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as summary:
            summary.write(message + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    discover = sub.add_parser("discover", help="Parse upstream wiki and propose JSON")
    discover.add_argument("--file", type=Path, default=DEFAULT_MANIFEST)
    discover.add_argument("--wiki-file", type=Path, help="Read a local fixture instead")
    discover.add_argument("--skip-upstream-check", action="store_true", help="Offline testing only")
    matrix = sub.add_parser("matrix", help="Validate reviewed JSON and export GitHub Actions matrix")
    matrix.add_argument("--file", type=Path, default=DEFAULT_MANIFEST)
    matrix.add_argument("--github-output", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "discover":
            if args.wiki_file:
                markdown = args.wiki_file.read_text(encoding="utf-8")
            else:
                with urllib.request.urlopen(
                    urllib.request.Request(MARKDOWN_URL, headers={"User-Agent": "librecode-nextcloud-version-discovery"}),
                    timeout=20,
                ) as response:
                    markdown = response.read().decode("utf-8")
            candidate = parse_wiki(markdown)
            if not args.skip_upstream_check:
                verify_upstream(candidate["versions"])
            new_content = json.dumps(candidate, indent=2, ensure_ascii=False) + "\n"
            changed = not args.file.exists() or args.file.read_text(encoding="utf-8") != new_content
            if changed:
                args.file.write_text(new_content, encoding="utf-8")
            append_summary(f"Nextcloud discovery: {', '.join(str(v['major']) for v in candidate['versions'])}; "
                           f"manifest {'updated' if changed else 'unchanged'}. Source: {SOURCE}")
        else:
            versions = read_manifest(args.file)["versions"]
            include = [
                {"major": item["major"], "tag": f"{item['major']}-fpm", "release": item["release"]}
                for item in versions
            ]
            matrix_json = json.dumps({"include": include}, separators=(",", ":"))
            if args.github_output:
                with args.github_output.open("a", encoding="utf-8") as output:
                    output.write(f"matrix={matrix_json}\n")
            else:
                print(matrix_json)
            append_summary(f"Approved Nextcloud versions: {', '.join(str(v['major']) for v in versions)}")
    except (OSError, ValueError, urllib.error.URLError) as error:
        message = str(error).replace("\n", " ")
        print(f"::error title=Nextcloud version discovery failed::{message}", file=sys.stderr)
        append_summary(f"**Nextcloud version discovery FAILED:** {message}. No manifest update can be proposed.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
