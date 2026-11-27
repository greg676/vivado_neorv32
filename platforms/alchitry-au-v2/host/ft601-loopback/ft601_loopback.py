#!/usr/bin/env python3
"""FT601 32-bit loopback / TX-only / RX-only host tool.

Fails closed on dropped words, bit swaps, and odd/short transfers.
Prints first 8 received words and sustained throughput.

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


def verify_words(got: List[int], start_idx: int) -> Tuple[int, int, list]:
    ok = 0
    bad = 0
    fails: list = []
    for i, value in enumerate(got):
        exp = pattern_word(start_idx + i)
        if value == exp:
            ok += 1
        else:
            if len(fails) < 2:
                fails.append((start_idx + i, value, exp))
            bad += 1
    return ok, bad, fails


def self_test() -> int:
    buf = [pattern_word(i) for i in range(16)]
    ok, bad, first = verify_words(buf, 0)
    if ok != 16 or bad != 0:
        print("self-test: expected clean match", file=sys.stderr)
        return 1
    buf[3] ^= 0x00010000
    buf[7] = 99
    ok, bad, fails = verify_words(buf, 0)
    if bad != 2 or not fails or fails[0][0] != 3 or len(fails) != 2:
        print(f"self-test: verifier did not fail closed (bad={bad} fails={fails})",
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


def fmt_first8(words: List[int]) -> str:
    show = words[:8]
    if not show:
        return "(none)"
    return " ".join(f"0x{w:08x}" for w in show)


def run_hw(args: argparse.Namespace) -> int:
    if args.tx_only and args.rx_only:
        print("error: --tx-only and --rx-only are mutually exclusive", file=sys.stderr)
        return 2

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
    chunk_bytes = args.chunk_bytes if args.chunk_bytes else 16384
    chunk = min(chunk_bytes // WORD, nwords)
    next_idx = 0
    bytes_done = 0
    words_ok = 0
    words_bad = 0
    odd_bytes = 0
    first_bads: list = []
    first_words: List[int] = []
    t0 = time.perf_counter()

    try:
        if args.rx_only:
            # FPGA RD while RXF; host OUT only for the payload. Then IN 8
            # words of the latched first-RX constant (not a full echo).
            while bytes_done < args.bytes:
                this = min(chunk, (args.bytes - bytes_done) // WORD)
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
                next_idx += this
                bytes_done += this * WORD
            report: List[int] = []
            try:
                raw = dev.read(8 * WORD)
                report = bytes_to_words(raw)
                first_words = report[:8]
            except RuntimeError as exc:
                print(f"error: first-RX constant IN failed: {exc}", file=sys.stderr)
            print("mode        : rx-only (host OUT; FPGA latches first word)")
            print(f"out_bytes   : {bytes_done}")
            print(f"first_rx_const (FPGA TX of latched word, not echo): {fmt_first8(first_words)}")
            if first_words:
                print(f"note        : all IN words should equal first OUT word "
                      f"0x{pattern_word(0):08x} if RX captured idx 0")
            dt = time.perf_counter() - t0
            print(f"seconds     : {dt:.4f}")
            if not first_words or bytes_done != args.bytes or odd_bytes:
                print("FAIL: RX-only OUT incomplete or no first-RX constant", file=sys.stderr)
                return 1
            if any(w != first_words[0] for w in first_words):
                print("FAIL: first-RX constant was not constant", file=sys.stderr)
                return 1
            if first_words[0] != pattern_word(0) and vec is None:
                print("FAIL: latched first RX word != 0x00000000", file=sys.stderr)
                return 1
            print("PASS")
            return 0

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
            if len(first_words) < 8:
                first_words.extend(got[: 8 - len(first_words)])
            if vec:
                ok = bad = 0
                fails = []
                for i, value in enumerate(got):
                    exp = vec[(next_idx + i) % len(vec)]
                    if value == exp:
                        ok += 1
                    else:
                        if len(fails) < 2:
                            fails.append((next_idx + i, value, exp))
                        bad += 1
            else:
                ok, bad, fails = verify_words(got, next_idx)
            words_ok += ok
            words_bad += bad
            for item in fails:
                if len(first_bads) < 2:
                    first_bads.append(item)
            if len(got) != this:
                words_bad += this - len(got)
                odd_bytes += (this * WORD) - n
            next_idx += this
            bytes_done += this * WORD
    finally:
        dev.close()

    dt = time.perf_counter() - t0
    mibps = (bytes_done / (1024 * 1024) / dt) if dt > 0 else 0.0
    print(f"mode        : {'tx-only (host IN, no OUT)' if args.tx_only else 'loopback'}")
    print(f"first_8     : {fmt_first8(first_words)}")
    print(f"bytes       : {bytes_done}")
    print(f"seconds     : {dt:.4f}")
    print(f"throughput  : {mibps:.2f} MiB/s")
    print(f"words_ok    : {words_ok}")
    print(f"words_bad   : {words_bad}")
    print(f"odd_bytes   : {odd_bytes}")
    for n, (idx, got_v, exp) in enumerate(first_bads, start=1):
        print(f"fail_{n}      : idx={idx} got=0x{got_v:08x} exp=0x{exp:08x}")

    if words_bad or odd_bytes or bytes_done != args.bytes:
        print("FAIL: mismatch or incomplete transfer", file=sys.stderr)
        return 1
    print("PASS")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="FT601 loopback checker (libusb, D3XX optional)")
    p.add_argument("--bytes", type=int, default=16 * 1024 * 1024)
    p.add_argument("--index", type=int, default=0)
    p.add_argument("--timeout-ms", type=int, default=5000)
    p.add_argument("--chunk-bytes", type=int, default=16384)
    p.add_argument("--tx-only", action="store_true",
                   help="host IN only (FPGA TX_ONLY bitstream; never RD)")
    p.add_argument("--rx-only", action="store_true",
                   help="host OUT known pattern, then IN 8 words of latched first-RX constant")
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
