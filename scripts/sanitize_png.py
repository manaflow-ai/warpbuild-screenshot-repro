#!/usr/bin/env python3
"""Validate a screenshot and remove non-critical PNG metadata."""

from __future__ import annotations

import os
import struct
import sys
import tempfile
import zlib
from pathlib import Path
from typing import NoReturn

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MAX_BYTES = 20 * 1024 * 1024
MAX_DIMENSION = 10_000
# PLTE is critical for indexed images. tRNS is retained when present because
# it affects pixels, while all textual/profile chunks are intentionally gone.
PRESERVED_CHUNKS = {b"IHDR", b"PLTE", b"IDAT", b"tRNS"}


def fail(message: str) -> NoReturn:
    raise SystemExit(f"PNG validation failed: {message}")


def read_chunks(data: bytes) -> list[tuple[bytes, bytes]]:
    if not data.startswith(PNG_SIGNATURE):
        fail("invalid signature")
    offset = len(PNG_SIGNATURE)
    chunks: list[tuple[bytes, bytes]] = []
    saw_header = False
    saw_end = False
    while offset < len(data):
        if offset + 12 > len(data):
            fail("truncated chunk header")
        length = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4 : offset + 8]
        end = offset + 12 + length
        if end > len(data):
            fail("truncated chunk payload")
        payload = data[offset + 8 : offset + 8 + length]
        checksum = struct.unpack_from(">I", data, offset + 8 + length)[0]
        if zlib.crc32(kind + payload) & 0xFFFFFFFF != checksum:
            fail(f"bad CRC in {kind!r}")
        if kind == b"IHDR":
            if saw_header:
                fail("duplicate IHDR")
            if length != 13:
                fail("invalid IHDR length")
            width, height = struct.unpack_from(">II", payload)
            if not 1 <= width <= MAX_DIMENSION or not 1 <= height <= MAX_DIMENSION:
                fail("dimensions exceed limit")
            saw_header = True
        elif not saw_header:
            fail("IHDR must be first")
        if kind == b"IEND":
            if length != 0:
                fail("invalid IEND length")
            saw_end = True
            offset = end
            if offset != len(data):
                fail("trailing bytes after IEND")
            break
        chunks.append((kind, payload))
        offset = end
    if not saw_header or not saw_end:
        fail("missing IHDR or IEND")
    if not any(kind == b"IDAT" for kind, _ in chunks):
        fail("missing IDAT")
    return chunks


def encode_chunks(chunks: list[tuple[bytes, bytes]]) -> bytes:
    result = bytearray(PNG_SIGNATURE)
    for kind, payload in chunks:
        result.extend(struct.pack(">I", len(payload)))
        result.extend(kind)
        result.extend(payload)
        result.extend(struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))
    result.extend(struct.pack(">I", 0))
    result.extend(b"IEND")
    result.extend(struct.pack(">I", zlib.crc32(b"IEND") & 0xFFFFFFFF))
    return bytes(result)


def sanitize(path: Path) -> None:
    stat = path.lstat()
    if path.is_symlink() or not path.is_file():
        fail("input is not a regular file")
    if stat.st_size > MAX_BYTES:
        fail("file is too large")
    chunks = read_chunks(path.read_bytes())
    sanitized = encode_chunks(
        [(kind, payload) for kind, payload in chunks if kind in PRESERVED_CHUNKS]
    )
    if stat.st_mode & 0o077:
        fail("input permissions are too broad")
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as output:
            output.write(sanitized)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


if __name__ == "__main__":
    if len(sys.argv) != 2:
        fail("usage: sanitize_png.py PATH")
    sanitize(Path(sys.argv[1]))
