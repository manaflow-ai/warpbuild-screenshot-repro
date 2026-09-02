from __future__ import annotations

import binascii
import os
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/repro.yml"
QUOTA_WORKFLOW = ROOT / ".github/workflows/macos-quota-probe.yml"
VALIDATE_WORKFLOW = ROOT / ".github/workflows/validate.yml"
SANITIZER = ROOT / "scripts/sanitize_png.py"


def chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", binascii.crc32(kind + payload) & 0xFFFFFFFF)
    )


def one_pixel_png() -> bytes:
    # RGB, eight-bit, one pixel. The ancillary text chunk simulates metadata
    # that must not leave the runner.
    header = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    scanline = zlib.compress(b"\x00\x12\x34\x56")
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(
        b"tEXt", b"comment\x00do-not-publish-secret"
    ) + chunk(b"IDAT", scanline) + chunk(b"IEND", b"")


def chunk_types(data: bytes) -> list[bytes]:
    offset = 8
    result = []
    while offset < len(data):
        length = struct.unpack_from(">I", data, offset)[0]
        result.append(data[offset + 4 : offset + 8])
        offset += length + 12
    return result


class WorkflowPolicyTests(unittest.TestCase):
    def test_probe_workflow_has_no_untrusted_dispatch_or_write_path(self) -> None:
        text = WORKFLOW.read_text()
        self.assertIsNone(re.search(r"(?m)^\s+workflow_dispatch:", text))
        self.assertIsNone(re.search(r"(?m)^\s+pull_request:", text))
        self.assertNotIn("contents: write", text)
        self.assertNotIn("git push", text)
        self.assertNotIn("raw/main/runs", text)
        self.assertIn("permissions: {}", text)
        self.assertIn("repository_dispatch:", text)
        self.assertIn("types: [run-repro]", text)
        self.assertIn("austinywang", text)
        self.assertIn("azooz2003-bit", text)
        self.assertIn("lawrencecchen", text)
        for sha in (
            "de0fac2e4500dabe0009e67214ff5f5447ce83dd",
            "043fb46d1a93c77aae656e7c1c64a875d1fc6a0a",
        ):
            self.assertIn(sha, text)
        self.assertIn("retention-days: 14", text)
        self.assertIn("if-no-files-found: error", text)

    def test_quota_workflow_has_only_trusted_dispatch(self) -> None:
        text = QUOTA_WORKFLOW.read_text()
        self.assertIsNone(re.search(r"(?m)^\s+workflow_dispatch:", text))
        self.assertIn("types: [run-quota-probe]", text)
        self.assertIn("github.ref_protected == true", text)
        self.assertIn("austinywang", text)
        self.assertIn("azooz2003-bit", text)
        self.assertIn("lawrencecchen", text)

    def test_validation_workflow_isolated_from_external_runners(self) -> None:
        text = VALIDATE_WORKFLOW.read_text()
        self.assertIsNotNone(re.search(r"(?m)^\s+pull_request:", text))
        self.assertIsNone(re.search(r"(?m)^\s+pull_request_target:", text))
        self.assertIn("permissions: {}", text)
        self.assertNotIn("self-hosted", text)
        self.assertNotIn("warp-macos", text)

    def test_requirements_are_hash_locked(self) -> None:
        text = (ROOT / "requirements.txt").read_text()
        self.assertRegex(text, r"(?m)^Pillow==11\.3\.0 \\\s*$")
        self.assertGreaterEqual(text.count("--hash=sha256:"), 10)
        self.assertNotIn("Pillow==", text.replace("Pillow==11.3.0", ""))


class PngSanitizerTests(unittest.TestCase):
    def run_sanitizer(self, path: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SANITIZER), str(path)],
            check=False,
            capture_output=True,
            text=True,
        )

    def test_removes_ancillary_metadata_and_keeps_pixels(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "desktop.png"
            path.write_bytes(one_pixel_png())
            path.chmod(0o600)
            result = self.run_sanitizer(path)
            self.assertEqual(result.returncode, 0, result.stderr)
            data = path.read_bytes()
            self.assertEqual(chunk_types(data), [b"IHDR", b"IDAT", b"IEND"])
            self.assertNotIn(b"do-not-publish-secret", data)

    def test_rejects_bad_crc(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad.png"
            data = bytearray(one_pixel_png())
            data[29] ^= 1
            path.write_bytes(data)
            path.chmod(0o600)
            result = self.run_sanitizer(path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("bad CRC", result.stderr)

    @unittest.skipUnless(os.name == "posix", "symlinks require POSIX")
    def test_rejects_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "target.png"
            target.write_bytes(one_pixel_png())
            target.chmod(0o600)
            link = root / "desktop.png"
            link.symlink_to(target)
            result = self.run_sanitizer(link)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("regular file", result.stderr)


if __name__ == "__main__":
    unittest.main()
