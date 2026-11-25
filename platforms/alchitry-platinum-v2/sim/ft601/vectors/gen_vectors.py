#!/usr/bin/env python3
"""Write host-reusable 32-bit LE FT601 loopback vectors.

The Icarus testbench reads the .hex files. The host tools send the matching
.bin files over USB bulk OUT and expect the same words back.
"""
from __future__ import annotations

import os
from pathlib import Path

HERE = Path(__file__).resolve().parent
N = 64


def counter(i: int) -> int:
    return i & 0xFFFFFFFF


def walking(i: int) -> int:
    return (1 << (i % 32)) & 0xFFFFFFFF


def xor_pat(i: int) -> int:
    return (i ^ 0xA5A5A5A5) & 0xFFFFFFFF


def write_set(name: str, fn) -> None:
    words = [fn(i) for i in range(N)]
    bin_path = HERE / f"{name}.bin"
    hex_path = HERE / f"{name}.hex"
    bin_path.write_bytes(b"".join(w.to_bytes(4, "little") for w in words))
    hex_path.write_text("".join(f"{w:08x}\n" for w in words))
    print(f"{name}: {N} words -> {bin_path.name} {hex_path.name}")


def main() -> int:
    os.chdir(HERE)
    write_set("counter", counter)
    write_set("walking", walking)
    write_set("xor", xor_pat)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
