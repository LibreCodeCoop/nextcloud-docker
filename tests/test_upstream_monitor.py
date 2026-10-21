#!/usr/bin/env python3
"""Offline unit tests for automatic rebuild decisions."""

import importlib.util
import json
import pathlib
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "upstream_image_monitor", ROOT / "scripts/monitor-upstream-images.py"
)
monitor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(monitor)

SHA = "e" * 40
DIGEST = "sha256:" + "a" * 64
NEW_DIGEST = "sha256:" + "b" * 64
VERSIONS = {"versions": [
    {"major": 33, "release": "33.0.10"},
    {"major": 34, "release": "34.0.5"},
]}
RELEASES = [
    {"branch": "8.4", "latest": "8.4.27", "state": "stable"},
    {"branch": "8.5", "latest": "8.5.12", "state": "stable"},
    {"branch": "8.1", "latest": "8.1.34", "state": "eol"},
]


def configs(php, *, digest=DIGEST, revision=SHA):
    return {
        arch: {
            "Env": ["PHP_VERSION=" + php],
            "Labels": {
                "coop.librecode.nextcloud.base.digest": digest,
                "org.opencontainers.image.revision": revision,
            },
        }
        for arch in monitor.PLATFORMS
    }


class MonitoringTests(unittest.TestCase):
    def setUp(self):
        self.digest = mock.patch.object(monitor, "manifest_digest", return_value=DIGEST)
        self.images = mock.patch.object(monitor, "image_config")
        self.digest_mock = self.digest.start()
        self.images_mock = self.images.start()
        self.addCleanup(self.digest.stop)
        self.addCleanup(self.images.stop)

    def configure(self, *, base="8.4.27", published=None):
        if published is None:
            published = configs(base)

        def get_image(ref):
            if ref.startswith("nextcloud:") or ref.startswith("nextcloud@"):
                return configs(base)
            if published == "missing":
                raise FileNotFoundError(ref)
            return published
        self.images_mock.side_effect = get_image

    def test_matching_manifest_and_revision_does_not_rebuild(self):
        self.configure()
        result = monitor.evaluate({"versions": [VERSIONS["versions"][0]]}, RELEASES, SHA)
        self.assertFalse(result["rebuild"])
        self.assertFalse(result["blocked"])
        self.assertEqual(result["rows"][0]["status"], "Up to date")

    def test_changed_upstream_digest_requests_rebuild(self):
        self.configure(published=configs("8.4.27", digest=NEW_DIGEST))
        result = monitor.evaluate({"versions": [VERSIONS["versions"][0]]}, RELEASES, SHA)
        self.assertTrue(result["rebuild"])
        self.assertFalse(result["blocked"])

    def test_changed_code_revision_retries_failed_publication(self):
        self.configure(published=configs("8.4.27", revision="f" * 40))
        result = monitor.evaluate({"versions": [VERSIONS["versions"][0]]}, RELEASES, SHA)
        self.assertTrue(result["rebuild"])

    def test_missing_published_tag_requests_rebuild(self):
        self.configure(published="missing")
        result = monitor.evaluate({"versions": [VERSIONS["versions"][0]]}, RELEASES, SHA)
        self.assertTrue(result["rebuild"])

    def test_legacy_image_without_provenance_requests_rebuild(self):
        self.configure(published={arch: {"Env": ["PHP_VERSION=8.4.27"], "Labels": {}}
                                 for arch in monitor.PLATFORMS})
        result = monitor.evaluate({"versions": [VERSIONS["versions"][0]]}, RELEASES, SHA)
        self.assertTrue(result["rebuild"])

    def test_outdated_upstream_php_blocks_rebuild(self):
        self.configure(base="8.4.26")
        result = monitor.evaluate({"versions": [VERSIONS["versions"][0]]}, RELEASES, SHA)
        self.assertTrue(result["blocked"])
        self.assertFalse(result["rebuild"])
        self.assertNotIn("ghcr.io", str(self.images_mock.call_args_list))

    def test_eol_upstream_php_blocks_rebuild(self):
        self.configure(base="8.1.34")
        result = monitor.evaluate({"versions": [VERSIONS["versions"][0]]}, RELEASES, SHA)
        self.assertTrue(result["blocked"])
        self.assertFalse(result["rebuild"])

    def test_any_blocked_channel_prevents_partial_alias_promotion(self):
        self.digest_mock.side_effect = lambda ref: DIGEST if "33.0.10" in ref else NEW_DIGEST
        def get_image(ref):
            if ref == "nextcloud@" + DIGEST:
                return configs("8.4.27")
            if ref == "nextcloud@" + NEW_DIGEST:
                return configs("8.5.11")
            return configs("8.4.27", digest=NEW_DIGEST)
        self.images_mock.side_effect = get_image
        result = monitor.evaluate(VERSIONS, RELEASES, SHA)
        self.assertTrue(result["blocked"])
        self.assertFalse(result["rebuild"])
        self.assertEqual(result["rows"][0]["status"], "Rebuild required")
        self.assertEqual(result["rows"][1]["status"], "Awaiting patched upstream")

    def test_missing_published_platform_requests_rebuild(self):
        self.configure()
        self.images_mock.side_effect = lambda ref: configs("8.4.27") if ref.startswith("nextcloud:") or ref.startswith("nextcloud@") else self._missing()
        result = monitor.evaluate({"versions": [VERSIONS["versions"][0]]}, RELEASES, SHA)
        self.assertTrue(result["rebuild"])

    @staticmethod
    def _missing():
        raise monitor.MissingPlatformError("published image missing linux/arm64")

    def test_missing_arm64_config_is_an_error_not_noop(self):
        self.images.stop()
        with mock.patch.object(monitor, "inspect", return_value={"linux/amd64": {"config": configs("8.4.27")["linux/amd64"]}}):
            with self.assertRaisesRegex(monitor.InspectionError, "linux/arm64"):
                monitor.image_config("nextcloud:33.0.10-fpm")

    def test_invalid_manifest_is_an_error_not_noop(self):
        for wrong in ({"versions": []}, {"versions": [{"major": 33, "release": "34.0.1"}]}, {}):
            with self.subTest(wrong=wrong), self.assertRaises(monitor.InspectionError):
                monitor.evaluate(wrong, RELEASES, SHA)

    def test_invalid_git_revision_is_an_error(self):
        with self.assertRaisesRegex(monitor.InspectionError, "40-digit"):
            monitor.evaluate(VERSIONS, RELEASES, "main")

    def test_summary_has_actionable_reasons(self):
        self.configure(base="8.4.26")
        result = monitor.evaluate({"versions": [VERSIONS["versions"][0]]}, RELEASES, SHA)
        rendered = monitor.render_summary(result)
        self.assertIn("Awaiting patched upstream", rendered)
        self.assertIn("8.4.26", rendered)
        self.assertIn("Rebuild requested:** False", rendered)

    def test_missing_registry_or_network_fails_closed(self):
        self.images_mock.side_effect = monitor.InspectionError("registry unreachable")
        with self.assertRaises(monitor.InspectionError):
            monitor.evaluate({"versions": [VERSIONS["versions"][0]]}, RELEASES, SHA)

    def test_manifest_digest_is_taken_from_upstream_index(self):
        self.digest.stop()
        with mock.patch.object(monitor, "inspect", return_value={"digest": DIGEST}):
            self.assertEqual(monitor.manifest_digest("nextcloud:33.0.10-fpm"), DIGEST)
        with mock.patch.object(monitor, "inspect", return_value={"digest": "invalid"}):
            with self.assertRaises(monitor.InspectionError):
                monitor.manifest_digest("nextcloud:33.0.10-fpm")


if __name__ == "__main__":
    unittest.main()
