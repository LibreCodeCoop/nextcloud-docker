#!/usr/bin/env python3
"""Offline regression tests for the dynamic upstream PHP release policy."""

import importlib.util
import io
import json
import pathlib
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("php_runtime_policy", ROOT / "scripts/check-php-runtime.py")
policy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(policy)

RELEASES = [
    {"branch": "8.3", "latest": "8.3.36", "state": "security"},
    {"branch": "8.4", "latest": "8.4.27", "state": "stable"},
    {"branch": "8.5", "latest": "8.5.12", "state": "stable"},
    {"branch": "8.1", "latest": "8.1.34", "state": "eol"},
]


class PhpRuntimePolicyTests(unittest.TestCase):
    def test_stale_php_is_blocked(self):
        with self.assertRaisesRegex(policy.SecurityPolicyError, "older"):
            policy.check_release("8.3.35", RELEASES)

    def test_current_php_passes(self):
        self.assertIn("supported", policy.check_release("8.3.36", RELEASES))
        self.assertIn("supported", policy.check_release("8.4.27", RELEASES))

    def test_future_series_requires_no_code_update(self):
        releases = RELEASES + [{"branch": "8.6", "latest": "8.6.0", "state": "stable"}]
        self.assertIn("supported", policy.check_release("8.6.0", releases))

    def test_eol_is_blocked_even_at_last_patch(self):
        with self.assertRaisesRegex(policy.SecurityPolicyError, "no upstream security support"):
            policy.check_release("8.1.34", RELEASES)

    def test_unknown_series_is_blocked(self):
        with self.assertRaisesRegex(policy.SecurityPolicyError, "missing or duplicated"):
            policy.check_release("9.0.0", RELEASES)

    def test_invalid_feed_is_blocked(self):
        for invalid in ([], {}, None):
            with self.subTest(feed=invalid), self.assertRaises(policy.SecurityPolicyError):
                policy.check_release("8.3.36", invalid)

    def test_bad_release_metadata_is_blocked(self):
        with self.assertRaisesRegex(policy.SecurityPolicyError, "Invalid"):
            policy.check_release("8.3.36", [{"branch": "8.3", "state": "security", "latest": "8.3.bad"}])

    def test_nonrelease_and_untrusted_versions_are_blocked(self):
        for version in ("8.3.36RC1", "8.3.36-dev", "8.3", "8.3.36\nX"):
            with self.subTest(version=version), self.assertRaises(policy.SecurityPolicyError):
                policy.check_release(version, RELEASES)

    def test_exact_runtime_is_read_from_image(self):
        fake = mock.Mock(stdout="PHP 8.3.36 (cli) (built: Oct 21 2026) (NTS)\n")
        with mock.patch.object(policy.subprocess, "run", return_value=fake) as run:
            self.assertEqual(policy.container_php_version("scan/app:arm64", "linux/arm64"), "8.3.36")
            cmd = run.call_args.args[0]
            self.assertEqual(cmd[0], "docker")
            self.assertIn("--network", cmd)
            self.assertIn("none", cmd)
            self.assertIn("--read-only", cmd)
            self.assertIn("linux/arm64", cmd)
            self.assertIn("scan/app:arm64", cmd)

    def test_malformed_runtime_output_is_blocked(self):
        with mock.patch.object(policy.subprocess, "run", return_value=mock.Mock(stdout="not PHP")):
            with self.assertRaisesRegex(policy.SecurityPolicyError, "Cannot parse"):
                policy.container_php_version("scan/app:amd64", "linux/amd64")

    def test_failed_image_probe_is_blocked(self):
        with mock.patch.object(policy.subprocess, "run", side_effect=OSError("docker unavailable")):
            with self.assertRaisesRegex(policy.SecurityPolicyError, "Cannot determine"):
                policy.container_php_version("scan/app:amd64", "linux/amd64")

    def test_feed_network_failure_is_blocked(self):
        with mock.patch.object(policy.urllib.request, "urlopen", side_effect=OSError("network unavailable")):
            with self.assertRaisesRegex(policy.SecurityPolicyError, "Cannot read"):
                policy.fetch_releases()

    def test_cli_uses_feed_without_any_version_matrix(self):
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / "releases.json"
            path.write_text(json.dumps(RELEASES))
            with redirect_stderr(io.StringIO()):
                self.assertEqual(policy.main(["--version", "8.3.35", "--releases-file", str(path)]), 1)
            with redirect_stdout(io.StringIO()):
                self.assertEqual(policy.main(["--version", "8.3.36", "--releases-file", str(path)]), 0)


if __name__ == "__main__":
    unittest.main()
