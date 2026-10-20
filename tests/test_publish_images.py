"""Mocked Docker tests: no registry writes, Docker daemon or network required."""

import sys
import unittest
import json
import tempfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import publish_images as images  # noqa: E402

SHA = "a" * 40
APP = "ghcr.io/librecodecoop/nextcloud-docker-app"
WEB = "ghcr.io/librecodecoop/nextcloud-docker-web"


class PublishImagesTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.approved = Path(self.directory.name) / "manifest.json"
        manifest = {
            "schema_version": 1,
            "source": "https://github.com/nextcloud/server/wiki/Maintenance-and-Release-Schedule",
            "versions": [
                {"major": 33, "release": "33.0.10", "eol": "2099-12"},
                {"major": 34, "release": "34.0.5", "eol": "2099-12"},
                {"major": 35, "release": "35.0.2", "eol": "2099-12"},
            ],
        }
        self.approved.write_text(json.dumps(manifest), encoding="utf-8")
    @patch.object(images, "run")
    def test_stage_app_publishes_only_requested_version(self, docker):
        images.stage(APP, SHA, "34-fpm")
        self.assertEqual([call.args for call in docker.call_args_list], [
            ("tag", "scan/app:amd64", f"{APP}:sha-{SHA}-34-fpm-amd64"),
            ("push", f"{APP}:sha-{SHA}-34-fpm-amd64"),
            ("tag", "scan/app:arm64", f"{APP}:sha-{SHA}-34-fpm-arm64"),
            ("push", f"{APP}:sha-{SHA}-34-fpm-arm64"),
        ])

    @patch.object(images, "run")
    def test_web_does_not_depend_on_nextcloud_major(self, docker):
        images.stage(WEB, SHA, "web")
        self.assertEqual(docker.call_count, 4)
        self.assertIn(f"{WEB}:sha-{SHA}-web-arm64", str(docker.call_args_list))
        self.assertNotIn("35-fpm", str(docker.call_args_list))

    @patch.object(images, "run")
    def test_promote_uses_highest_approved_major_and_web_always(self, docker):
        images.promote(APP, WEB, SHA, self.approved)
        calls = [call.args for call in docker.call_args_list]
        created = [item for item in calls if item[:3] == ("buildx", "imagetools", "create")]
        self.assertEqual(len(created), 10)
        tags = [item[4] for item in created]
        self.assertEqual(tags, [
            f"{APP}:33-fpm", f"{APP}:33.0.10-fpm",
            f"{APP}:34-fpm", f"{APP}:34.0.5-fpm",
            f"{APP}:35-fpm", f"{APP}:35.0.2-fpm",
            f"{APP}:stable-fpm", f"{APP}:latest", f"{WEB}:main", f"{WEB}:latest",
        ])
        self.assertEqual(created[7][-2:], (
            f"{APP}:sha-{SHA}-35-fpm-amd64", f"{APP}:sha-{SHA}-35-fpm-arm64",
        ))
        self.assertEqual(created[8][-2:], (
            f"{WEB}:sha-{SHA}-web-amd64", f"{WEB}:sha-{SHA}-web-arm64",
        ))

    @patch.object(images, "run")
    @patch.object(images, "read_manifest")
    def test_promote_selects_next_major_without_hardcoding(self, reviewed, docker):
        reviewed.return_value = {"versions": [
            {"major": 34, "release": "34.0.5"},
            {"major": 35, "release": "35.0.2"},
            {"major": 36, "release": "36.0.0"},
        ]}
        images.promote(APP, WEB, SHA, self.approved)
        creates = [call.args for call in docker.call_args_list if call.args[:3] ==
                   ("buildx", "imagetools", "create")]
        self.assertIn(f"{APP}:sha-{SHA}-36-fpm-amd64", creates[7])
        self.assertIn(f"{APP}:sha-{SHA}-36-fpm-arm64", creates[7])
        self.assertEqual(creates[7][4], f"{APP}:latest")

    @patch.object(images, "run")
    def test_invalid_tag_or_commit_never_publishes(self, docker):
        for bad in ("35; rm -rf /", "latest", "0-fpm"):
            with self.assertRaises(ValueError):
                images.stage(APP, SHA, bad)
        with self.assertRaises(ValueError):
            images.stage(APP, "short", "35-fpm")
        docker.assert_not_called()


if __name__ == "__main__":
    unittest.main()
