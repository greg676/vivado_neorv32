#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Greg Jackson
# SPDX-License-Identifier: MIT
"""FT601 LA capture: host IN of packed 8-bit samples, write PulseView .sr.

FPGA streams four 8-bit samples per 32-bit FT601 word through the PR #18
4 KiB PHY (DATA-before-WR). Host IN only. Hardware uses libusb first; D3XX
is the Jetson path (FTD3XX_LIB). --self-test needs neither.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
from typing import List, Optional, Sequence, Tuple

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "common"))
from ft601_usb import open_ft601  # noqa: E402

WORD = 4
SAMPLE_RATE_HZ = 100_000_000
DEFAULT_PROBES = ("D0", "D1", "D2", "D3", "D4", "D5", "D6", "D7")
SRC_COUNTER = 0
SRC_WALKING = 1


def pack_word(s0: int, s1: int, s2: int, s3: int) -> int:
    return (s0 & 0xFF) | ((s1 & 0xFF) << 8) | ((s2 & 0xFF) << 16) | ((s3 & 0xFF) << 24)


def unpack_word(word: int) -> Tuple[int, int, int, int]:
    return (word & 0xFF, (word >> 8) & 0xFF, (word >> 16) & 0xFF, (word >> 24) & 0xFF)


def sample_at(idx: int, source: int) -> int:
    if source == SRC_WALKING:
        return 1 << (idx & 7)
    return idx & 0xFF


def expected_word(sample_base: int, source: int) -> int:
    return pack_word(
        sample_at(sample_base, source),
        sample_at(sample_base + 1, source),
        sample_at(sample_base + 2, source),
        sample_at(sample_base + 3, source),
    )


def bytes_to_words(buf: bytes) -> List[int]:
    return [int.from_bytes(buf[i:i + 4], "little") for i in range(0, len(buf), 4)]


def unpack_samples(buf: bytes) -> bytes:
    return buf


def samplerate_string(rate_hz: int) -> str:
    if rate_hz % 1_000_000 == 0:
        return f"{rate_hz // 1_000_000} MHz"
    if rate_hz % 1_000 == 0:
        return f"{rate_hz // 1_000} kHz"
    return f"{rate_hz} Hz"


def write_sr(
    path: str,
    samples: bytes,
    *,
    rate_hz: int = SAMPLE_RATE_HZ,
    probes: Sequence[str] = DEFAULT_PROBES,
) -> str:
    """Write a sigrok v2 session (.sr / srzip) PulseView 0.4.2 opens."""
    if len(probes) < 1 or len(probes) > 8:
        raise ValueError("need 1-8 probe names")
    lines = [
        "[global]",
        "sigrok version=0.5.2",
        "",
        "[device 1]",
        "capturefile=logic-1",
        f"total probes={len(probes)}",
        f"samplerate={samplerate_string(rate_hz)}",
        "total analog=0",
    ]
    for i, name in enumerate(probes, 1):
        lines.append(f"probe{i}={name}")
    lines.append("unitsize=1")
    metadata = "\n".join(lines) + "\n"
    parent = os.path.dirname(os.path.abspath(path))
    if parent:
        os.makedirs(parent, exist_ok=True)
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("version", "2")
        zf.writestr("metadata", metadata)
        zf.writestr("logic-1-1", samples)
    return path


def verify_packed(words: List[int], source: int, start_sample: int = 0
                  ) -> Tuple[int, int, Optional[Tuple[int, int, int]]]:
    ok = 0
    bad = 0
    first = None
    for i, value in enumerate(words):
        exp = expected_word(start_sample + i * 4, source)
        if value == exp:
            ok += 1
        else:
            if first is None:
                first = (i, value, exp)
            bad += 1
    return ok, bad, first


def fmt_first8(words: List[int]) -> str:
    show = words[:8]
    if not show:
        return "(none)"
    return " ".join(f"0x{w:08x}" for w in show)


def self_test() -> int:
    ctr = [expected_word(i * 4, SRC_COUNTER) for i in range(16)]
    if unpack_word(ctr[0]) != (0, 1, 2, 3) or unpack_word(ctr[1]) != (4, 5, 6, 7):
        print("self-test: counter packing is wrong", file=sys.stderr)
        return 1
    ok, bad, first = verify_packed(ctr, SRC_COUNTER)
    if ok != 16 or bad != 0:
        print("self-test: counter verify failed", file=sys.stderr)
        return 1
    shifted = [expected_word(0x44 + i * 4, SRC_COUNTER) for i in range(8)]
    ok, bad, first = verify_packed(shifted, SRC_COUNTER, start_sample=0x44)
    if ok != 8 or bad != 0:
        print("self-test: free-run origin verify failed", file=sys.stderr)
        return 1
    broken = list(ctr)
    broken[2] ^= 0x00000100
    ok, bad, first = verify_packed(broken, SRC_COUNTER)
    if bad != 1 or first is None or first[0] != 2:
        print(f"self-test: verifier did not fail closed (bad={bad} first={first})",
              file=sys.stderr)
        return 1
    walk = expected_word(0, SRC_WALKING)
    if unpack_word(walk) != (0x01, 0x02, 0x04, 0x08):
        print("self-test: walking word 0 packing is wrong", file=sys.stderr)
        return 1

    samples = bytes([i & 0xFF for i in range(64)])
    with tempfile.TemporaryDirectory() as tmp:
        sr_path = os.path.join(tmp, "counter.sr")
        write_sr(sr_path, samples, rate_hz=SAMPLE_RATE_HZ)
        with zipfile.ZipFile(sr_path) as zf:
            names = set(zf.namelist())
            if names != {"version", "metadata", "logic-1-1"}:
                print(f"self-test: .sr members {names}", file=sys.stderr)
                return 1
            if zf.read("version") != b"2":
                print("self-test: .sr version is not 2", file=sys.stderr)
                return 1
            meta = zf.read("metadata").decode()
            if "samplerate=100 MHz" not in meta or "probe1=D0" not in meta:
                print(f"self-test: .sr metadata {meta!r}", file=sys.stderr)
                return 1
            if zf.read("logic-1-1") != samples:
                print("self-test: .sr payload mismatch", file=sys.stderr)
                return 1
        cli = shutil.which("sigrok-cli")
        if cli:
            show = subprocess.run(
                [cli, "-i", sr_path, "--show"],
                check=False, capture_output=True, text=True,
            )
            if show.returncode != 0:
                print(f"self-test: sigrok-cli --show failed: {show.stderr}",
                      file=sys.stderr)
                return 1
            if "100000000" not in show.stdout and "100 MHz" not in show.stdout:
                print(f"self-test: sigrok-cli samplerate missing: {show.stdout}",
                      file=sys.stderr)
                return 1
            print("self-test PASS (packer + .sr + sigrok-cli)")
            return 0
    print("self-test PASS (packer + .sr; sigrok-cli not on PATH)")
    return 0


def try_sigrok(sr_path: str) -> None:
    cli = shutil.which("sigrok-cli")
    if not cli:
        print("sigrok-cli  : not on PATH")
        return
    show = subprocess.run(
        [cli, "-i", sr_path, "--show"],
        check=False, capture_output=True, text=True,
    )
    print("sigrok-cli  : --show")
    sys.stdout.write(show.stdout)
    if show.returncode != 0:
        sys.stderr.write(show.stderr)


def try_pulseview(sr_path: str) -> None:
    pv = shutil.which("pulseview")
    if not pv:
        print("pulseview   : not on PATH")
        return
    print(f"pulseview   : {pv} (not launched; open {sr_path})")


def run_hw(args: argparse.Namespace) -> int:
    source = SRC_WALKING if args.pattern == "walking" else SRC_COUNTER
    try:
        dev = open_ft601(index=args.index, timeout_ms=args.timeout_ms,
                         backend=args.backend)
    except FileNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    nwords = args.bytes // WORD
    chunk_bytes = args.chunk_bytes if args.chunk_bytes else 4096
    chunk = min(chunk_bytes // WORD, nwords)
    bytes_done = 0
    payload = bytearray()
    first_words: List[int] = []
    t0 = time.perf_counter()

    try:
        while bytes_done < args.bytes:
            this = min(chunk, (args.bytes - bytes_done) // WORD)
            try:
                raw = dev.read(this * WORD)
            except RuntimeError as exc:
                print(f"error: {exc}", file=sys.stderr)
                break
            if len(raw) % WORD != 0:
                print(f"error: odd read {len(raw)} bytes", file=sys.stderr)
                break
            got = bytes_to_words(raw)
            if len(first_words) < 8:
                first_words.extend(got[: 8 - len(first_words)])
            payload.extend(raw)
            bytes_done += len(raw)
            if len(got) != this:
                break
    finally:
        dev.close()

    dt = time.perf_counter() - t0
    samples = unpack_samples(bytes(payload))
    words = bytes_to_words(bytes(payload))
    words_ok = words_bad = 0
    first_bad = None
    start_sample = 0
    if args.pattern != "none" and words:
        start_sample = unpack_word(words[0])[0]
        words_ok, words_bad, first_bad = verify_packed(
            words, source, start_sample=start_sample
        )

    print("mode        : la-capture (dual 4 KiB BRAM, 4 KiB PHY bursts)")
    print(f"first_8     : {fmt_first8(first_words)}")
    print(f"bytes       : {bytes_done}")
    print(f"samples     : {len(samples)}")
    print(f"start_sample: {start_sample} (0x{start_sample:02x})")
    print(f"seconds     : {dt:.4f}")
    if dt > 0:
        print(f"throughput  : {bytes_done / (1024 * 1024) / dt:.2f} MiB/s")
    print(f"words_ok    : {words_ok}")
    print(f"words_bad   : {words_bad}")
    if first_bad:
        idx, got_v, exp = first_bad
        print(f"first_bad   : word={idx} got=0x{got_v:08x} exp=0x{exp:08x}")

    if args.dump:
        os.makedirs(os.path.dirname(os.path.abspath(args.dump)) or ".", exist_ok=True)
        with open(args.dump, "wb") as f:
            f.write(samples)
        print(f"dump        : {args.dump}")

    sr_path = args.sr
    if sr_path:
        write_sr(sr_path, samples, rate_hz=args.rate)
        print(f"sr          : {sr_path}")
        try_sigrok(sr_path)
        try_pulseview(sr_path)

    if words_bad or bytes_done != args.bytes:
        print("FAIL: mismatch or incomplete transfer", file=sys.stderr)
        return 1
    print("PASS")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(
        description="FT601 LA capture → PulseView .sr (libusb, D3XX optional)")
    p.add_argument("--bytes", type=int, default=16 * 1024)
    p.add_argument("--index", type=int, default=0)
    p.add_argument("--timeout-ms", type=int, default=5000)
    p.add_argument("--chunk-bytes", type=int, default=4096,
                   help="host IN size; PHY writes 4 KiB transactions")
    p.add_argument("--backend", choices=("auto", "libusb", "d3xx"), default="auto")
    p.add_argument("--pattern", choices=("counter", "walking", "none"), default="counter")
    p.add_argument("--dump", metavar="FILE", help="write unpacked 8-bit samples")
    p.add_argument("--sr", metavar="FILE", help="write sigrok v2 PulseView session")
    p.add_argument("--rate", type=int, default=SAMPLE_RATE_HZ)
    p.add_argument("--self-test", action="store_true")
    args = p.parse_args()
    if args.self_test:
        return self_test()
    if args.bytes < WORD or args.bytes % WORD:
        print("error: --bytes must be a positive multiple of 4", file=sys.stderr)
        return 2
    return run_hw(args)


if __name__ == "__main__":
    sys.exit(main())
