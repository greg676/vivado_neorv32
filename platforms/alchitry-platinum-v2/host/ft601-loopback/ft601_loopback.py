#!/usr/bin/env python3
"""FT601 32-bit loopback / TX-counter host tool.

Fails closed on dropped words, bit swaps, and odd/short transfers.
Prints sustained throughput.

Hardware uses libusb (preferred). D3XX is an optional fallback if the
Linux SDK is unpacked to /opt/ftdi/d3xx. --self-test needs neither.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from typing import List, Optional, Tuple

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "common"))
from ft601_usb import open_ft601  # noqa: E402

WORD = 4


def pattern_word(idx: int) -> int:
    return idx & 0xFFFFFFFF


def load_vector(path: str) -> List[int]:
    raw = open(path, "rb").read()
    if len(raw) < WORD or len(raw) % WORD:
        raise ValueError(f"{path}: length {len(raw)} is not a positive multiple of 4")
    return bytes_to_words(raw)


def verify_words(got: List[int], start_idx: int) -> Tuple[int, int, Optional[Tuple[int, int, int]]]:
    ok = 0
    bad = 0
    first = None
    for i, value in enumerate(got):
        exp = pattern_word(start_idx + i)
        if value == exp:
            ok += 1
        else:
            if first is None:
                first = (start_idx + i, value, exp)
            bad += 1
    return ok, bad, first


def self_test() -> int:
    buf = [pattern_word(i) for i in range(16)]
    ok, bad, first = verify_words(buf, 0)
    if ok != 16 or bad != 0:
        print("self-test: expected clean match", file=sys.stderr)
        return 1
    buf[3] ^= 0x00010000
    buf[7] = 99
    ok, bad, first = verify_words(buf, 0)
    if bad != 2 or first is None or first[0] != 3:
        print(f"self-test: verifier did not fail closed (bad={bad} first={first})",
              file=sys.stderr)
        return 1
    print("self-test PASS (matcher fails closed on bit-swap and drop)")

    vec_dir = os.path.join(os.path.dirname(__file__), "..", "..", "sim", "ft601", "vectors")
    gold = os.path.join(vec_dir, "counter.bin")
    if os.path.isfile(gold):
        words = load_vector(gold)
        if words[:8] != [pattern_word(i) for i in range(8)]:
            print(f"self-test: {gold} does not match pattern_word", file=sys.stderr)
            return 1
        print(f"self-test PASS (sim vector {gold} matches host pattern)")
    return 0


def words_to_bytes(words: List[int]) -> bytes:
    return b"".join(int(w).to_bytes(4, "little") for w in words)


def bytes_to_words(buf: bytes) -> List[int]:
    return [int.from_bytes(buf[i:i + 4], "little") for i in range(0, len(buf), 4)]


def run_hw(args: argparse.Namespace) -> int:
    vec: Optional[List[int]] = None
    if args.vector:
        try:
            vec = load_vector(args.vector)
        except (OSError, ValueError) as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2

    try:
        dev = open_ft601(index=args.index, timeout_ms=args.timeout_ms,
                         backend=args.backend)
    except FileNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    nwords = args.bytes // WORD
    chunk = min(16 * 1024, nwords)
    next_idx = 0
    bytes_done = 0
    words_ok = 0
    words_bad = 0
    odd_bytes = 0
    first_bad = None
    t0 = time.perf_counter()

    try:
        while bytes_done < args.bytes:
            this = min(chunk, (args.bytes - bytes_done) // WORD)

            if not args.tx_only:
                if vec:
                    payload = words_to_bytes([vec[(next_idx + i) % len(vec)] for i in range(this)])
                else:
                    payload = words_to_bytes([pattern_word(next_idx + i) for i in range(this)])
                try:
                    dev.write(payload)
                except RuntimeError as exc:
                    print(f"error: {exc}", file=sys.stderr)
                    odd_bytes += 1
                    break

            try:
                raw = dev.read(this * WORD)
            except RuntimeError as exc:
                print(f"error: {exc}", file=sys.stderr)
                break
            n = len(raw)
            if n % WORD != 0:
                print(f"error: odd read {n} bytes (not a whole word)", file=sys.stderr)
                odd_bytes += n % WORD
                break
            got = bytes_to_words(raw)
            if vec:
                ok = bad = 0
                first = None
                for i, value in enumerate(got):
                    exp = vec[(next_idx + i) % len(vec)]
                    if value == exp:
                        ok += 1
                    else:
                        if first is None:
                            first = (next_idx + i, value, exp)
                        bad += 1
            else:
                ok, bad, first = verify_words(got, next_idx)
            words_ok += ok
            words_bad += bad
            if first_bad is None:
                first_bad = first
            if len(got) != this:
                words_bad += this - len(got)
                odd_bytes += (this * WORD) - n
            next_idx += this
            bytes_done += this * WORD
    finally:
        dev.close()

    dt = time.perf_counter() - t0
    mibps = (bytes_done / (1024 * 1024) / dt) if dt > 0 else 0.0
    print(f"mode        : {'tx-only' if args.tx_only else 'loopback'}")
    print(f"bytes       : {bytes_done}")
    print(f"seconds     : {dt:.4f}")
    print(f"throughput  : {mibps:.2f} MiB/s")
    print(f"words_ok    : {words_ok}")
    print(f"words_bad   : {words_bad}")
    print(f"odd_bytes   : {odd_bytes}")
    if first_bad:
        idx, got_v, exp = first_bad
        print(f"first_bad   : idx={idx} got=0x{got_v:08x} exp=0x{exp:08x}")

    if words_bad or odd_bytes or bytes_done != args.bytes:
        print("FAIL: loopback mismatch or incomplete transfer", file=sys.stderr)
        return 1
    print("PASS")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="FT601 loopback checker (libusb, D3XX optional)")
    p.add_argument("--bytes", type=int, default=16 * 1024 * 1024)
    p.add_argument("--index", type=int, default=0)
    p.add_argument("--timeout-ms", type=int, default=5000)
    p.add_argument("--tx-only", action="store_true")
    p.add_argument("--backend", choices=("auto", "libusb", "d3xx"), default="auto")
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--vector", help="LE 32-bit .bin from sim/ft601/vectors (host reuses sim gold)")
    args = p.parse_args()
    if args.self_test:
        return self_test()
    if args.bytes < WORD or args.bytes % WORD:
        print("error: --bytes must be a positive multiple of 4", file=sys.stderr)
        return 2
    return run_hw(args)


if __name__ == "__main__":
    sys.exit(main())
