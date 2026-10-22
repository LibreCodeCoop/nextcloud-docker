#!/usr/bin/env python3
"""Reject mutable or unversioned remote uses references in GitHub Actions."""
from pathlib import Path
import re
import sys

uses = re.compile(r"^\s*(?:-\s*)?uses:\s*(\S+)(.*)$")
pinned = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*@[a-f0-9]{40}$")
version = re.compile(r"^#\s+v?[0-9]+\.[0-9]+\.[0-9]+$")
checked = 0
errors = []

for directory in (Path(".github"), Path("templates/workflows")):
    for path in sorted((*directory.rglob("*.yml"), *directory.rglob("*.yaml"))):
        for lineno, line in enumerate(path.read_text().splitlines(), 1):
            match = uses.match(line)
            if not match:
                continue
            ref, comment = match.groups()
            if ref.startswith("./"):
                continue
            checked += 1
            # The distributed example pins a branch snapshot, not a tagged Action.
            is_template = ref.startswith("LibreCodeCoop/nextcloud-docker/.github/workflows/")
            valid_comment = bool(version.fullmatch(comment.strip()))
            if is_template:
                valid_comment = comment.strip() == "# main"
            if not pinned.fullmatch(ref) or not valid_comment:
                errors.append(f"{path}:{lineno}: {ref}{comment}")

if errors:
    print("Unpinned or unversioned GitHub Actions references:", *errors, sep="\n", file=sys.stderr)
    sys.exit(1)
print(f"Validated {checked} SHA-pinned external Actions/workflow references")
