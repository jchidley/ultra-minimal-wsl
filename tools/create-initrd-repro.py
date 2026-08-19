#!/usr/bin/env python3
"""Create WSL's one-file newc initrd deterministically."""

from __future__ import annotations

import os
from pathlib import Path


def pad4(stream) -> None:
    remainder = stream.tell() % 4
    if remainder:
        stream.write(b"\0" * (4 - remainder))


def entry(stream, name: bytes, data: bytes, mode: int, mtime: int, inode: int) -> None:
    fields = (
        inode,
        mode,
        0,
        0,
        1,
        mtime,
        len(data),
        0,
        0,
        0,
        0,
        len(name),
        0,
    )
    stream.write(b"070701" + b"".join(f"{value:08X}".encode("ascii") for value in fields))
    stream.write(name)
    pad4(stream)
    stream.write(data)
    pad4(stream)


def main() -> None:
    source = Path(os.environ["INIT_INPUT"])
    output = Path(os.environ["INITRD_OUTPUT"])
    mtime = int(os.environ["SOURCE_DATE_EPOCH"])
    data = source.read_bytes()

    with output.open("wb") as stream:
        entry(stream, b"init\0", data, 0o100755, mtime, 1)
        entry(stream, b"TRAILER!!!\0", b"", 0, 0, 0)


if __name__ == "__main__":
    main()
