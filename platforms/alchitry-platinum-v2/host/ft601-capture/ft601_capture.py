#!/usr/bin/env python3
"""FT601 capture dump: packed 8-bit LA samples as 32-bit little-endian words.

Reads the LA capture bitstream (not the loopback top). Prints timestamped
blocks and optionally writes the raw packed stream. --self-test does not
need the D3XX SDK.
"""

from __future__ import annotations

import argparse
import ctypes
import os
import sys
import time
from ctypes import POINTER, c_uint8, c_ulong, c_void_p
from typing import List, Optional, TextIO, Tuple

PIPE_OUT = 0x02
PIPE_IN = 0x82
FT_OK = 0
FT_OPEN_BY_INDEX = 0
WORD = 4

SRC_COUNTER = 0
SRC_WALKING = 1
SRC_LIVE = 2


def pack_word(s0: int, s1: int, s2: int, s3: int) -> int:
    return (s0 & 0xFF) | ((s1 & 0xFF) << 8) | ((s2 & 0xFF) << 16) | ((s3 & 0xFF) << 24)


def unpack_word(word: int) -> Tuple[int, int, int, int]:
    return (word & 0xFF, (word >> 8) & 0xFF, (word >> 16) & 0xFF, (word >> 24) & 0xFF)


def sample_at(idx: int, source: int) -> int:
    if source == SRC_WALKING:
        return 1 << (idx & 7)
    return idx & 0xFF


def expected_word(word_idx: int, source: int) -> int:
    base = word_idx * 4
    return pack_word(
        sample_at(base, source),
        sample_at(base + 1, source),
        sample_at(base + 2, source),
        sample_at(base + 3, source),
    )


def verify_packed(words: List[int], start_word: int, source: int
                  ) -> Tuple[int, int, Optional[Tuple[int, int, int]]]:
    ok = 0
    bad = 0
    first = None
    for i, value in enumerate(words):
        exp = expected_word(start_word + i, source)
        if value == exp:
            ok += 1
        else:
            if first is None:
                first = (start_word + i, value, exp)
            bad += 1
    return ok, bad, first


def self_test() -> int:
    ctr = [expected_word(i, SRC_COUNTER) for i in range(16)]
    ok, bad, first = verify_packed(ctr, 0, SRC_COUNTER)
    if ok != 16 or bad != 0 or unpack_word(ctr[0]) != (0, 1, 2, 3):
        print("self-test: counter pack/unpack failed", file=sys.stderr)
        return 1
    if unpack_word(ctr[1]) != (4, 5, 6, 7):
        print("self-test: counter word 1 packing is wrong", file=sys.stderr)
        return 1

    walk = [expected_word(i, SRC_WALKING) for i in range(4)]
    if unpack_word(walk[0]) != (0x01, 0x02, 0x04, 0x08):
        print("self-test: walking word 0 packing is wrong", file=sys.stderr)
        return 1
    if unpack_word(walk[1]) != (0x10, 0x20, 0x40, 0x80):
        print("self-test: walking word 1 packing is wrong", file=sys.stderr)
        return 1
    ok, bad, first = verify_packed(walk, 0, SRC_WALKING)
    if ok != 4 or bad != 0:
        print("self-test: walking verify failed", file=sys.stderr)
        return 1

    broken = list(ctr)
    broken[2] ^= 0x00000100
    ok, bad, first = verify_packed(broken, 0, SRC_COUNTER)
    if bad != 1 or first is None or first[0] != 2:
        print(f"self-test: verifier did not fail closed (bad={bad} first={first})",
              file=sys.stderr)
        return 1
    print("self-test PASS (packer round-trip + matcher fails closed)")
    return 0


def load_d3xx() -> ctypes.CDLL:
    names = [
        os.environ.get("FTD3XX_LIB"),
        "libftd3xx.so",
        "libftd3xx.dylib",
        "FTD3XX.dll",
    ]
    last = None
    lib = None
    for name in names:
        if not name:
            continue
        try:
            lib = ctypes.CDLL(name)
            break
        except OSError as exc:
            last = exc
    if lib is None:
        raise FileNotFoundError(
            "D3XX library not found. Install the FTDI D3XX SDK and put "
            "libftd3xx.so on LD_LIBRARY_PATH, or set FTD3XX_LIB. "
            f"Last error: {last}"
        )

    lib.FT_Create.argtypes = [c_void_p, c_ulong, POINTER(c_void_p)]
    lib.FT_Create.restype = c_ulong
    lib.FT_Close.argtypes = [c_void_p]
    lib.FT_Close.restype = c_ulong
    lib.FT_WritePipe.argtypes = [c_void_p, c_uint8, ctypes.c_void_p, c_ulong,
                                 POINTER(c_ulong), c_void_p]
    lib.FT_WritePipe.restype = c_ulong
    lib.FT_ReadPipe.argtypes = [c_void_p, c_uint8, ctypes.c_void_p, c_ulong,
                                POINTER(c_ulong), c_void_p]
    lib.FT_ReadPipe.restype = c_ulong
    lib.FT_SetPipeTimeout.argtypes = [c_void_p, c_uint8, c_ulong]
    lib.FT_SetPipeTimeout.restype = c_ulong
    return lib


def bytes_to_words(buf: bytes) -> List[int]:
    return [int.from_bytes(buf[i:i + 4], "little") for i in range(0, len(buf), 4)]


def log_block(stream: TextIO, t0: float, block: int, raw: bytes, words: List[int]) -> None:
    now = time.perf_counter()
    s0 = unpack_word(words[0]) if words else (None, None, None, None)
    print(
        f"t={now - t0:.6f}s  block={block}  bytes={len(raw)}  "
        f"samples={len(raw)}  first={s0[0]:02x} {s0[1]:02x} {s0[2]:02x} {s0[3]:02x}"
        if words else
        f"t={now - t0:.6f}s  block={block}  bytes={len(raw)}  samples=0",
        file=stream,
    )


def run_hw(args: argparse.Namespace) -> int:
    lib = load_d3xx()
    handle = c_void_p()
    st = lib.FT_Create(c_void_p(args.index), FT_OPEN_BY_INDEX, ctypes.byref(handle))
    if st != FT_OK or not handle.value:
        print(f"error: FT_Create index {args.index} failed ({st})", file=sys.stderr)
        return 1

    lib.FT_SetPipeTimeout(handle, PIPE_OUT, args.timeout_ms)
    lib.FT_SetPipeTimeout(handle, PIPE_IN, args.timeout_ms)

    dump = open(args.dump, "wb") if args.dump else None
    nwords = args.bytes // WORD
    chunk = min(16 * 1024, nwords)
    next_word = 0
    bytes_done = 0
    words_ok = 0
    words_bad = 0
    odd_bytes = 0
    first_bad = None
    block = 0
    t0 = time.perf_counter()

    try:
        if args.source is not None:
            cmd = int(args.source).to_bytes(4, "little")
            xferred = c_ulong(0)
            st = lib.FT_WritePipe(handle, PIPE_OUT, cmd, 4, ctypes.byref(xferred), None)
            if st != FT_OK or xferred.value != 4:
                print(f"error: FT_WritePipe source select {st}", file=sys.stderr)
                return 1

        while bytes_done < args.bytes:
            this = min(chunk, (args.bytes - bytes_done) // WORD)
            rx = ctypes.create_string_buffer(this * WORD)
            xferred = c_ulong(0)
            st = lib.FT_ReadPipe(handle, PIPE_IN, rx, this * WORD,
                                 ctypes.byref(xferred), None)
            if st != FT_OK:
                print(f"error: FT_ReadPipe {st}", file=sys.stderr)
                break
            n = int(xferred.value)
            if n % WORD != 0:
                print(f"error: odd read {n} bytes (not a whole word)", file=sys.stderr)
                odd_bytes += n % WORD
                break
            raw = rx.raw[:n]
            got = bytes_to_words(raw)
            log_block(sys.stdout, t0, block, raw, got)
            if dump is not None:
                dump.write(raw)
            if args.pattern != "none":
                src = SRC_WALKING if args.pattern == "walking" else SRC_COUNTER
                ok, bad, first = verify_packed(got, next_word, src)
                words_ok += ok
                words_bad += bad
                if first_bad is None:
                    first_bad = first
            if len(got) != this:
                odd_bytes += (this * WORD) - n
                if args.pattern != "none":
                    words_bad += this - len(got)
            next_word += this
            bytes_done += this * WORD
            block += 1
    finally:
        lib.FT_Close(handle)
        if dump is not None:
            dump.close()

    dt = time.perf_counter() - t0
    mibps = (bytes_done / (1024 * 1024) / dt) if dt > 0 else 0.0
    print(f"mode        : capture dump")
    print(f"bytes       : {bytes_done}")
    print(f"samples     : {bytes_done}")
    print(f"blocks      : {block}")
    print(f"seconds     : {dt:.4f}")
    print(f"throughput  : {mibps:.2f} MiB/s")
    if args.dump:
        print(f"dump        : {args.dump}")
    if args.pattern != "none":
        print(f"pattern     : {args.pattern}")
        print(f"words_ok    : {words_ok}")
        print(f"words_bad   : {words_bad}")
        if first_bad:
            idx, got_v, exp = first_bad
            print(f"first_bad   : word={idx} got=0x{got_v:08x} exp=0x{exp:08x}")
        if words_bad or odd_bytes or bytes_done != args.bytes:
            print("FAIL: packed-sample mismatch or incomplete transfer", file=sys.stderr)
            return 1
        print("PASS")
        return 0
    if odd_bytes or bytes_done != args.bytes:
        print("FAIL: incomplete transfer", file=sys.stderr)
        return 1
    print("PASS (dump only, pattern not checked)")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="FT601 LA capture dump (D3XX)")
    p.add_argument("--bytes", type=int, default=16 * 1024 * 1024)
    p.add_argument("--index", type=int, default=0)
    p.add_argument("--timeout-ms", type=int, default=5000)
    p.add_argument("--dump", metavar="FILE", help="write packed little-endian words")
    p.add_argument("--pattern", choices=("counter", "walking", "none"), default="counter",
                   help="verify on-FPGA test pattern (default counter)")
    p.add_argument("--source", type=int, choices=(0, 1, 2),
                   help="write source select (0=counter 1=walking 2=live) before dump")
    p.add_argument("--self-test", action="store_true")
    args = p.parse_args()
    if args.self_test:
        return self_test()
    if args.bytes < WORD or args.bytes % WORD:
        print("error: --bytes must be a positive multiple of 4", file=sys.stderr)
        return 2
    try:
        return run_hw(args)
    except FileNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
