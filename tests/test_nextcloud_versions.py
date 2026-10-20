"""Offline regression tests for wiki discovery, schema validation and failure handling."""

import datetime as dt
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import nextcloud_versions as versions  # noqa: E402


class NextcloudVersionsTest(unittest.TestCase):
    def fixture(self, name: str) -> str:
        return (ROOT / "tests" / "fixtures" / (name + ".md")).read_text(encoding="utf-8")

    def test_real_historical_wiki_formats(self):
        cases = [
            ("2023-maintained", dt.date(2023, 7, 1), [25, 26, 27]),
            ("2024-maintained", dt.date(2024, 7, 1), [28, 29]),
            ("2025-supported", dt.date(2025, 7, 1), [30, 31]),
            ("2026-supported", dt.date(2026, 10, 20), [33, 34, 35]),
        ]
        for name, day, expected in cases:
            with self.subTest(revision=name):
                result = versions.parse_wiki(self.fixture(name), today=day)
                self.assertEqual([item["major"] for item in result["versions"]], expected)

    def test_malformed_historical_revision_fails_closed(self):
        with self.assertRaises(versions.VersionError):
            versions.parse_wiki(self.fixture("2024-malformed"), today=dt.date(2024, 10, 24))

    def test_unreleased_or_conflicting_historical_wiki_fails_closed(self):
        with self.assertRaisesRegex(versions.VersionError, "Invalid current release"):
            versions.parse_wiki(self.fixture("2026-unreleased"), today=dt.date(2026, 2, 12))
        with self.assertRaisesRegex(versions.VersionError, "both supported and EOL"):
            versions.parse_wiki(self.fixture("2025-eol-overlap"), today=dt.date(2025, 4, 15))

    def test_heading_removed_fails_closed(self):
        source = self.fixture("2026-supported").replace("Currently supported versions", "Upcoming releases")
        with self.assertRaisesRegex(versions.VersionError, "No 'Currently"):
            versions.parse_wiki(source, today=dt.date(2026, 10, 20))

    def test_supported_and_eol_conflict_fails_closed(self):
        source = self.fixture("2026-supported").replace("| **32**", "| **35**")
        with self.assertRaisesRegex(versions.VersionError, "both supported and EOL"):
            versions.parse_wiki(source, today=dt.date(2026, 10, 20))

    def test_end_of_life_month_fails_closed(self):
        with self.assertRaisesRegex(versions.VersionError, "EOL"):
            versions.parse_wiki(self.fixture("2026-supported"), today=dt.date(2027, 10, 1))

    def test_json_schema_rejects_out_of_order_or_eol(self):
        manifest = versions.parse_wiki(self.fixture("2026-supported"), today=dt.date(2026, 10, 20))
        reversed_manifest = {**manifest, "versions": list(reversed(manifest["versions"]))}
        with self.assertRaisesRegex(versions.VersionError, "sorted"):
            versions.validate_manifest(reversed_manifest, today=dt.date(2026, 10, 20))
        expired_manifest = json.loads(json.dumps(manifest))
        expired_manifest["versions"][0]["eol"] = "2026-09"
        with self.assertRaisesRegex(versions.VersionError, "EOL"):
            versions.validate_manifest(expired_manifest, today=dt.date(2026, 10, 20))

    def test_manifest_matrix_uses_approved_patch_versions(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest_file = Path(tmp) / "approved.json"
            fixture = versions.parse_wiki(self.fixture("2026-supported"), today=dt.date(2026, 10, 20))
            for entry in fixture["versions"]:
                entry["eol"] = "2099-12"  # Never tie a unit test to the real-world EOL clock.
            manifest_file.write_text(json.dumps(fixture), encoding="utf-8")
            output = Path(tmp) / "actions_output"
            completed = subprocess.run(
                [sys.executable, str(ROOT / "scripts" / "nextcloud_versions.py"),
                 "matrix", "--file", str(manifest_file), "--github-output", str(output)],
                capture_output=True, text=True, cwd=ROOT, check=True,
            )
            self.assertIn("Approved Nextcloud versions", completed.stdout)
            raw = output.read_text(encoding="utf-8").strip()
            self.assertTrue(raw.startswith("matrix="))
            self.assertEqual(json.loads(raw.partition("=")[2]), {
                "include": [
                    {"major": 33, "tag": "33-fpm", "release": "33.0.10"},
                    {"major": 34, "tag": "34-fpm", "release": "34.0.5"},
                    {"major": 35, "tag": "35-fpm", "release": "35.0.2"},
                ]
            })

    def test_bad_wiki_does_not_modify_approved_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            approved = Path(tmp) / "approved.json"
            approved.write_text('{"approved":true}\n')
            completed = subprocess.run(
                [sys.executable, str(ROOT / "scripts" / "nextcloud_versions.py"), "discover",
                 "--file", str(approved), "--wiki-file",
                 str(ROOT / "tests/fixtures/2024-malformed.md"), "--skip-upstream-check"],
                capture_output=True, text=True, cwd=ROOT,
            )
            self.assertEqual(completed.returncode, 1)
            self.assertEqual(approved.read_text(), '{"approved":true}\n')
            self.assertIn("::error title=Nextcloud version discovery failed::", completed.stderr)

    def test_upstream_verification_requires_release_and_both_architectures(self):
        entries = [{"major": 35, "release": "35.0.2", "eol": "2027-09"}]
        with patch.object(versions, "request_json", side_effect=[
            {"tag_name": "v35.0.2", "prerelease": False, "draft": False},
            {"name": "35.0.2-fpm", "images": [
                {"os": "linux", "architecture": "amd64"},
                {"os": "linux", "architecture": "arm64"},
            ]},
        ]) as request:
            versions.verify_upstream(entries)
            self.assertEqual(request.call_count, 2)
        with patch.object(versions, "request_json", side_effect=[
            {"tag_name": "v35.0.2", "prerelease": False, "draft": False},
            {"name": "35.0.2-fpm", "images": [{"os": "linux", "architecture": "amd64"}]},
        ]):
            with self.assertRaisesRegex(versions.VersionError, "lacks amd64 or arm64"):
                versions.verify_upstream(entries)


if __name__ == "__main__":
    unittest.main()
