#!/usr/bin/env python3
"""Golden 4/8/16-channel pack into 32-bit USB words (no Vivado).

Matches ip/pvla/hdl/pvla_word_packer.v:
  4 ch  -> 8 samples/word   [3:0]=t+0  ... [31:28]=t+7
  8 ch  -> 4 samples/word   [7:0]=t+0  ... [31:24]=t+3
  16 ch -> 2 samples/word   [15:0]=t+0 ... [31:16]=t+1
"""
from __future__ import annotations

import sys


def samples_per_word(num_ch: int) -> int:
    if num_ch not in (4, 8, 16):
        raise ValueError(f"C_NUM_CH must be 4, 8, or 16 (got {num_ch})")
    return 32 // num_ch


def pack_words(num_ch: int, samples: list[int]) -> list[int]:
    spw = samples_per_word(num_ch)
    mask = (1 << num_ch) - 1
    words: list[int] = []
    acc = 0
    n = 0
    for s in samples:
        acc |= (s & mask) << (n * num_ch)
        n += 1
        if n == spw:
            words.append(acc & 0xFFFFFFFF)
            acc = 0
            n = 0
    return words


def usb_mword(sample_mhz: float, num_ch: int, div: int) -> float:
    rate = sample_mhz / div
    return rate / samples_per_word(num_ch)


def main() -> int:
    errors: list[str] = []

    def check(name: str, got, exp) -> None:
        if got != exp:
            errors.append(f"{name}: got {got!r} exp {exp!r}")

    check("spw4", samples_per_word(4), 8)
    check("spw8", samples_per_word(8), 4)
    check("spw16", samples_per_word(16), 2)

    # 8 ch: bytes t+0..t+3 in [7:0]..[31:24]
    check("8ch 0..3", pack_words(8, [0, 1, 2, 3]), [0x03020100])
    check("8ch rolling", pack_words(8, list(range(8))), [0x03020100, 0x07060504])

    # 4 ch: nibbles. samples 1..8 -> 0x87654321
    check("4ch 1..8", pack_words(4, [1, 2, 3, 4, 5, 6, 7, 8]), [0x87654321])
    # High nibble of the word IS sample t+7 (DATA[31:28]), not unused.
    w4 = pack_words(4, [0xA, 0xB, 0xC, 0xD, 0xE, 0xF, 0x1, 0x2])[0]
    check("4ch DATA[31:28]", (w4 >> 28) & 0xF, 0x2)
    check("4ch DATA[3:0]", w4 & 0xF, 0xA)

    # 16 ch: two halfwords
    check("16ch", pack_words(16, [0x1111, 0x2222, 0xAAAA, 0xBBBB]),
          [0x22221111, 0xBBBBAAAA])

    # Partial last group is not emitted (packer waits for a full word).
    check("8ch partial", pack_words(8, [1, 2, 3]), [])

    # Rate math vs FT601 100 MHz 32-bit
    check("8ch 100/1 usb", usb_mword(100, 8, 1), 25.0)
    check("4ch 100/1 usb", usb_mword(100, 4, 1), 12.5)
    check("16ch 100/1 usb", usb_mword(100, 16, 1), 50.0)
    if usb_mword(100, 8, 1) > 100:
        errors.append("8ch @ 100 MS/s must fit in 100 Mword/s FT601")

    if errors:
        print("pvla_word_packer golden FAILED:")
        for e in errors:
            print(f"  - {e}")
        return 1
    print("pvla_word_packer golden PASS")
    print("  4 ch: 8 samples/word  [3:0]=t+0 ... [31:28]=t+7")
    print("  8 ch: 4 samples/word  [7:0]=t+0 ... [31:24]=t+3")
    print("  16ch: 2 samples/word  [15:0]=t+0 ... [31:16]=t+1")
    print("  8ch @ 100 MS/s -> 25 Mword/s USB (<= 100 MHz ft_clk)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
