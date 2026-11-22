#!/usr/bin/env python3
"""FT601 triggered capture dump: LAT3 header + packed 8-bit LA samples.

Writes START/STOP, reads the 8-word header (trigger position, overflow/drop),
then packed little-endian payload. Hardware uses libusb (preferred); D3XX is
optional via FTD3XX_LIB=/opt/ftdi/d3xx/libftd3xx.so. --self-test needs neither.
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
HDR_WORDS = 8
LAT3_MAGIC = 0x3354414C
LAT3_VERSION = 1

CMD_NOP = 0
CMD_CFG = 1
CMD_START = 2
CMD_STOP = 3
CMD_FORCE = 4

EDGE_RISE = 0
EDGE_FALL = 1
EDGE_BOTH = 2
EDGE_IMM = 3
EDGES = {"rise": EDGE_RISE, "rising": EDGE_RISE, "fall": EDGE_FALL,
         "falling": EDGE_FALL, "both": EDGE_BOTH, "imm": EDGE_IMM,
         "immediate": EDGE_IMM}

SRC_COUNTER = 0
SRC_WALKING = 1
SRC_LIVE = 2


def make_cmd(cmd: int, src: int, ch: int, edge: int, post: int) -> int:
    return ((cmd & 0xF) | ((src & 3) << 4) | ((ch & 7) << 6) |
            ((edge & 3) << 9) | ((post & 0xFFFF) << 16))


def parse_header(words: List[int]) -> dict:
    if len(words) < HDR_WORDS:
        raise ValueError("header too short")
    status = words[2]
    hdr = {
        "magic": words[0],
        "version": words[1],
        "status": status,
        "nsamples": words[3],
        "trig_pos": words[4],
        "overflow": words[5],
        "drop": words[6],
        "post_cfg": words[7] & 0xFFFF,
        "source": status & 3,
        "channel": (status >> 2) & 7,
        "edge": (status >> 5) & 3,
        "triggered": bool((status >> 8) & 1),
        "aborted": bool((status >> 10) & 1),
        "immediate": bool((status >> 11) & 1),
    }
    if hdr["magic"] != LAT3_MAGIC:
        raise ValueError(f"bad MAGIC 0x{hdr['magic']:08x}")
    if hdr["version"] != LAT3_VERSION:
        raise ValueError(f"bad VERSION {hdr['version']}")
    return hdr


def pack_word(s0: int, s1: int, s2: int, s3: int) -> int:
    return (s0 & 0xFF) | ((s1 & 0xFF) << 8) | ((s2 & 0xFF) << 16) | ((s3 & 0xFF) << 24)


def unpack_word(word: int) -> Tuple[int, int, int, int]:
    return (word & 0xFF, (word >> 8) & 0xFF, (word >> 16) & 0xFF, (word >> 24) & 0xFF)


def sample_at(idx: int, source: int) -> int:
    if source == SRC_WALKING:
        return 1 << (idx & 7)
    return idx & 0xFF


def expected_word_n(sample_base: int, nsamples: int, source: int) -> int:
    s = []
    for i in range(4):
        idx = sample_base + i
        s.append(sample_at(idx, source) if idx < nsamples else 0)
    return pack_word(*s)


def verify_packed_n(words: List[int], nsamples: int, source: int
                    ) -> Tuple[int, int, Optional[Tuple[int, int, int]]]:
    ok = 0
    bad = 0
    first = None
    for i, value in enumerate(words):
        exp = expected_word_n(i * 4, nsamples, source)
        if value == exp:
            ok += 1
        else:
            if first is None:
                first = (i, value, exp)
            bad += 1
    return ok, bad, first


def self_test() -> int:
    cmd = make_cmd(CMD_START, 0, 3, EDGE_FALL, 64)
    if ((cmd >> 16) & 0xFFFF) != 64 or (cmd & 0xF) != CMD_START:
        print(f"self-test: command packing is wrong (0x{cmd:08x})", file=sys.stderr)
        return 1
    if ((cmd >> 6) & 7) != 3 or ((cmd >> 9) & 3) != EDGE_FALL:
        print(f"self-test: command ch/edge packing is wrong (0x{cmd:08x})", file=sys.stderr)
        return 1
    if make_cmd(CMD_STOP, 0, 0, 0, 0) != CMD_STOP:
        print("self-test: STOP command packing is wrong", file=sys.stderr)
        return 1

    hdr_words = [
        LAT3_MAGIC, LAT3_VERSION,
        (1 << 8),  # triggered, rise, ch0, counter
        6, 1, 0, 0, 4,
    ]
    hdr = parse_header(hdr_words)
    if not hdr["triggered"] or hdr["trig_pos"] != 1 or hdr["nsamples"] != 6:
        print("self-test: header parse failed", file=sys.stderr)
        return 1
    bad = list(hdr_words)
    bad[0] ^= 1
    try:
        parse_header(bad)
        print("self-test: bad MAGIC did not fail closed", file=sys.stderr)
        return 1
    except ValueError:
        pass

    ctr = [expected_word_n(i * 4, 64, SRC_COUNTER) for i in range(16)]
    ok, badn, first = verify_packed_n(ctr, 64, SRC_COUNTER)
    if ok != 16 or badn != 0 or unpack_word(ctr[0]) != (0, 1, 2, 3):
        print("self-test: counter pack/unpack failed", file=sys.stderr)
        return 1

    walk = expected_word_n(0, 8, SRC_WALKING)
    if unpack_word(walk) != (0x01, 0x02, 0x04, 0x08):
        print("self-test: walking word 0 packing is wrong", file=sys.stderr)
        return 1

    padded = expected_word_n(4, 6, SRC_COUNTER)
    if unpack_word(padded) != (4, 5, 0, 0):
        print("self-test: pad bytes must be zero past nsamples", file=sys.stderr)
        return 1

    broken = list(ctr)
    broken[2] ^= 0x00000100
    ok, badn, first = verify_packed_n(broken, 64, SRC_COUNTER)
    if badn != 1 or first is None or first[0] != 2:
        print(f"self-test: verifier did not fail closed (bad={badn} first={first})",
              file=sys.stderr)
        return 1
    print("self-test PASS (cmd + LAT3 header + packer, matcher fails closed)")
    return 0


def bytes_to_words(buf: bytes) -> List[int]:
    return [int.from_bytes(buf[i:i + 4], "little") for i in range(0, len(buf), 4)]


def run_hw(args: argparse.Namespace) -> int:
    try:
        dev = open_ft601(index=args.index, timeout_ms=args.timeout_ms,
                         backend=args.backend)
    except FileNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    dump = open(args.dump, "wb") if args.dump else None
    t0 = time.perf_counter()
    words_ok = 0
    words_bad = 0
    first_bad = None
    hdr = None

    try:
        opcode = CMD_STOP if args.stop else CMD_START
        cmd = make_cmd(opcode, args.source, args.channel, args.edge, args.post)
        raw_cmd = cmd.to_bytes(4, "little")
        dev.write(raw_cmd)

        hdr_raw = dev.read(HDR_WORDS * WORD)
        hdr = parse_header(bytes_to_words(hdr_raw))
        tpos = hdr["trig_pos"] if hdr["triggered"] else None
        print(
            f"t=0.000000s  header  magic=LAT3  nsamp={hdr['nsamples']}  "
            f"tpos={tpos}  ovf={hdr['overflow']}  drop={hdr['drop']}"
        )

        nwords = (hdr["nsamples"] + 3) // 4
        payload = b""
        if nwords:
            payload = dev.read(nwords * WORD)
            got = bytes_to_words(payload)
            s0 = unpack_word(got[0]) if got else (0, 0, 0, 0)
            now = time.perf_counter()
            print(
                f"t={now - t0:.6f}s  payload  bytes={len(payload)}  "
                f"samples={hdr['nsamples']}  first={s0[0]:02x} {s0[1]:02x} {s0[2]:02x} {s0[3]:02x}"
            )
            if dump is not None:
                dump.write(payload)
            if args.pattern != "none":
                src = SRC_WALKING if args.pattern == "walking" else SRC_COUNTER
                words_ok, words_bad, first_bad = verify_packed_n(
                    got, hdr["nsamples"], src
                )
    except (RuntimeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    finally:
        dev.close()
        if dump is not None:
            dump.close()

    dt = time.perf_counter() - t0
    print("mode        : triggered capture")
    print(f"triggered   : {'yes' if hdr['triggered'] else 'no'}")
    print(f"trig_pos    : {hdr['trig_pos'] if hdr['triggered'] else 0xffffffff}")
    print(f"nsamples    : {hdr['nsamples']}")
    print(f"overflow    : {hdr['overflow']}")
    print(f"drop        : {hdr['drop']}")
    print(f"post_cfg    : {hdr['post_cfg']}")
    print(f"channel     : {hdr['channel']}")
    print(f"edge        : {hdr['edge']}")
    print(f"seconds     : {dt:.4f}")
    if args.dump:
        print(f"dump        : {args.dump}")
    if args.pattern != "none":
        print(f"pattern     : {args.pattern}")
        print(f"words_ok    : {words_ok}")
        print(f"words_bad   : {words_bad}")
        if first_bad:
            idx, got_v, exp = first_bad
            print(f"first_bad   : word={idx} got=0x{got_v:08x} exp=0x{exp:08x}")
        if words_bad:
            print("FAIL: packed-sample mismatch", file=sys.stderr)
            return 1
        print("PASS")
        return 0
    print("PASS (dump only, pattern not checked)")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="FT601 LA triggered capture dump (libusb, D3XX optional)")
    p.add_argument("--index", type=int, default=0)
    p.add_argument("--timeout-ms", type=int, default=5000)
    p.add_argument("--backend", choices=("auto", "libusb", "d3xx"), default="auto")
    p.add_argument("--dump", metavar="FILE", help="write packed little-endian payload")
    p.add_argument("--pattern", choices=("counter", "walking", "none"), default="counter",
                   help="verify on-FPGA test pattern (default counter)")
    p.add_argument("--source", type=int, choices=(0, 1, 2), default=0,
                   help="0=counter 1=walking 2=live")
    p.add_argument("--channel", type=int, default=0, help="trigger channel 0-7")
    p.add_argument("--edge", choices=tuple(EDGES.keys()), default="rise")
    p.add_argument("--post", type=int, default=0, help="post-trigger samples (0=FPGA default)")
    p.add_argument("--stop", action="store_true", help="send STOP instead of START")
    p.add_argument("--self-test", action="store_true")
    args = p.parse_args()
    if args.self_test:
        return self_test()
    if not (0 <= args.channel <= 7):
        print("error: --channel must be 0-7", file=sys.stderr)
        return 2
    args.edge = EDGES[args.edge]
    try:
        return run_hw(args)
    except FileNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
