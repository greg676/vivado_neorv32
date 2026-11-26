#!/usr/bin/env python3
"""Decode one FT601 host uint32 against DATA[31:0] (no USB)."""
import sys

GOT = int(sys.argv[1], 0) if len(sys.argv) > 1 else 0x00000DF6
EXP = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0

ones = [i for i in range(32) if (GOT >> i) & 1]
print(f"got=0x{GOT:08x} exp=0x{EXP:08x}")
print(f"popcount got={bin(GOT).count('1')} exp={bin(EXP).count('1')}")
print("byte-reverse exp", f"0x{int.from_bytes(EXP.to_bytes(4,'little'),'big'):08x}")
print("nibble-swap exp", f"0x{((EXP & 0x0F0F0F0F)<<4 | (EXP & 0xF0F0F0F0)>>4):08x}")
print("bit-reverse exp", f"0x{int(f'{EXP:032b}'[::-1], 2):08x}")
print("ones at DATA bits", ones)
print("ones in DATA[0:13] (PT_ALPHA vs V2 split)", [i for i in ones if i <= 13])
print("ones in DATA[14:31] (same on both pinouts)", [i for i in ones if i >= 14])
if EXP == 0 and GOT != 0:
    print("not a permutation of exp: any shuffle of 0 stays 0")
