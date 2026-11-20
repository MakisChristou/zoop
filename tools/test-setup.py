#!/usr/bin/env python3
"""Exercise configuration generation without Docker or existing installation files."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "tools").mkdir()
        shutil.copy(Path(__file__).with_name("setup.sh"), self.root / "tools/setup.sh")

    def tearDown(self):
        self.temp.cleanup()

    def run_setup(self, *args, **env):
        return subprocess.run(
            ["sh", str(self.root / "tools/setup.sh"), *args],
            env={**os.environ, "ZOOP_BIND": "127.0.0.1", "ZOOP_PORT": "8080", **env},
            capture_output=True,
        )

    def test_private_unique_secrets_and_no_overwrite(self):
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        path = self.root / ".env"
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        original = path.read_bytes()
        fields = dict(line.split("=", 1) for line in original.decode().splitlines())
        secrets = [fields[k] for k in ("ZOOP_DB_PASSWORD", "ZOOP_INGEST_TOKEN", "ZOOP_SETUP_CODE")]
        self.assertEqual(len(set(secrets)), 3)
        for secret in secrets:
            self.assertRegex(secret, r"^[0-9a-f]{64}$")
            self.assertNotIn(secret.encode(), result.stdout)
        self.assertNotEqual(self.run_setup().returncode, 0)
        self.assertEqual(path.read_bytes(), original)
        self.assertEqual(self.run_setup("--show-code").stdout.decode().strip(), fields["ZOOP_SETUP_CODE"])

    def test_rejects_interpolation_and_multiline_inputs(self):
        for value in ("ftp://host", "http://host/path", "http://host/", "http://", "http://host?x=1", "http://host\nZOOP_PORT=9999", "http://$(id)", "http://host#fragment"):
            with self.subTest(value=value):
                self.assertNotEqual(self.run_setup(value).returncode, 0)
                self.assertFalse((self.root / ".env").exists())
        for port in ("0", "65536", "abc", "80\n999"):
            self.assertNotEqual(self.run_setup(ZOOP_PORT=port).returncode, 0)
        self.assertNotEqual(self.run_setup(ZOOP_BIND="127.0.0.1\nBAD=value").returncode, 0)

    def test_accepts_private_http_ipv6_and_https(self):
        for origin in ("http://192.168.1.20:8080", "http://zoop.local:8080", "http://[::1]:8080", "https://zoop.example"):
            with self.subTest(origin=origin):
                self.assertEqual(self.run_setup(origin).returncode, 0)
                (self.root / ".env").unlink()


if __name__ == "__main__":
    unittest.main()
