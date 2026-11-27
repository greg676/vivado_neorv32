"""Simulated FT601 LA device: LAT3 header + packed 8-ch samples, PulseView .sr.

No hardware. The byte stream matches platforms/alchitry-platinum-v2/host/ft601-capture
(PR #4 / #5): 8 little-endian header words (magic 0x3354414C "LAT3"), then four
8-bit samples per 32-bit word, oldest in the LSB. Channel 0 is bit 0 of each
sample, which is also sigrok probe1.
"""

from __future__ import annotations

import os
import struct
import sys
import zipfile
from dataclasses import dataclass
from typing import Dict, List, Optional, Sequence, Tuple

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "ft601-capture"))
from ft601_capture import (  # noqa: E402
    CMD_FORCE,
    CMD_START,
    CMD_STOP,
    EDGE_FALL,
    EDGE_RISE,
    HDR_WORDS,
    LAT3_MAGIC,
    LAT3_VERSION,
    SRC_COUNTER,
    SRC_LIVE,
    SRC_WALKING,
    make_cmd,
    pack_word,
    parse_header,
    unpack_word,
)

WORD = 4
SAMPLE_RATE_HZ = 200_000_000
DEFAULT_PROBES = ("D0", "D1", "D2", "D3", "D4", "D5", "D6", "D7")


def pack_payload(samples: bytes) -> bytes:
    """Four samples per little-endian word; pad with zeros past nsamples."""
    pad = (-len(samples)) % WORD
    return samples + bytes(pad)


def unpack_payload(payload: bytes, nsamples: int) -> bytes:
    if nsamples < 0 or nsamples > len(payload):
        raise ValueError(f"nsamples {nsamples} out of range for {len(payload)}-byte payload")
    return payload[:nsamples]


def build_header_words(
    nsamples: int,
    *,
    source: int = SRC_LIVE,
    channel: int = 0,
    edge: int = EDGE_FALL,
    trig_pos: int = 0,
    overflow: int = 0,
    drop: int = 0,
    post_cfg: int = 0,
    triggered: bool = True,
    aborted: bool = False,
    immediate: bool = False,
) -> List[int]:
    status = (
        (source & 3)
        | ((channel & 7) << 2)
        | ((edge & 3) << 5)
        | ((1 if triggered else 0) << 8)
        | ((1 if overflow else 0) << 9)
        | ((1 if aborted else 0) << 10)
        | ((1 if immediate else 0) << 11)
    )
    tpos = 0xFFFFFFFF if not triggered else (trig_pos & 0xFFFFFFFF)
    return [
        LAT3_MAGIC,
        LAT3_VERSION,
        status,
        nsamples & 0xFFFFFFFF,
        tpos,
        overflow & 0xFFFFFFFF,
        drop & 0xFFFFFFFF,
        post_cfg & 0xFFFF,
    ]


def header_bytes(words: Sequence[int]) -> bytes:
    return b"".join(int(w).to_bytes(4, "little") for w in words)


def parse_lat3_stream(blob: bytes) -> Tuple[dict, bytes]:
    if len(blob) < HDR_WORDS * WORD:
        raise ValueError("LAT3 stream shorter than 32-byte header")
    words = [
        int.from_bytes(blob[i : i + 4], "little")
        for i in range(0, HDR_WORDS * WORD, 4)
    ]
    hdr = parse_header(words)
    payload = blob[HDR_WORDS * WORD :]
    need = ((hdr["nsamples"] + 3) // 4) * 4
    if len(payload) < need:
        raise ValueError(
            f"LAT3 payload short: got {len(payload)} bytes, need {need} for "
            f"{hdr['nsamples']} samples"
        )
    return hdr, unpack_payload(payload[:need], hdr["nsamples"])


def pack_channels(channels: Sequence[Sequence[int]]) -> bytes:
    """channels[c][t] is 0/1 for channel c. Channel 0 -> bit 0 (sigrok probe1)."""
    if not channels:
        return b""
    n = len(channels[0])
    if any(len(ch) != n for ch in channels):
        raise ValueError("channel traces must be the same length")
    if len(channels) > 8:
        raise ValueError("at most 8 channels")
    out = bytearray(n)
    for c, seq in enumerate(channels):
        bit = 1 << c
        for t, v in enumerate(seq):
            if v:
                out[t] |= bit
    return bytes(out)


def channel_bits(samples: bytes, ch: int) -> List[int]:
    mask = 1 << ch
    return [1 if (s & mask) else 0 for s in samples]


def samplerate_string(rate_hz: int) -> str:
    if rate_hz <= 0:
        raise ValueError("sample rate must be positive")
    if rate_hz % 1_000_000_000 == 0:
        return f"{rate_hz // 1_000_000_000} GHz"
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
    os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("version", "2")
        zf.writestr("metadata", metadata)
        zf.writestr("logic-1-1", samples)
    return path


def write_raw(path: str, samples: bytes) -> str:
    """Unpacked 8-bit samples for PulseView File → Import → Raw binary."""
    os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)
    with open(path, "wb") as f:
        f.write(samples)
    return path


@dataclass
class Capture:
    samples: bytes
    probes: Tuple[str, ...]
    rate_hz: int
    trig_pos: int
    channel: int
    edge: int
    source: int
    post_cfg: int
    pattern: str
    notes: str

    def device(self) -> "SimulatedLat3Device":
        return SimulatedLat3Device(
            self.samples,
            rate_hz=self.rate_hz,
            channel=self.channel,
            edge=self.edge,
            source=self.source,
            trig_pos=self.trig_pos,
            post_cfg=self.post_cfg,
        )


class SimulatedLat3Device:
    """File-based stand-in for the FT601 TX path of la_capture_top."""

    def __init__(
        self,
        samples: bytes,
        *,
        rate_hz: int = SAMPLE_RATE_HZ,
        channel: int = 0,
        edge: int = EDGE_FALL,
        source: int = SRC_LIVE,
        trig_pos: int = 0,
        overflow: int = 0,
        drop: int = 0,
        post_cfg: int = 0,
        triggered: bool = True,
        immediate: bool = False,
    ) -> None:
        self.samples = bytes(samples)
        self.rate_hz = rate_hz
        self.channel = channel
        self.edge = edge
        self.source = source
        self.trig_pos = trig_pos
        self.overflow = overflow
        self.drop = drop
        self.post_cfg = post_cfg or len(self.samples)
        self.triggered = triggered
        self.immediate = immediate

    def header_words(self) -> List[int]:
        return build_header_words(
            len(self.samples),
            source=self.source,
            channel=self.channel,
            edge=self.edge,
            trig_pos=self.trig_pos,
            overflow=self.overflow,
            drop=self.drop,
            post_cfg=self.post_cfg,
            triggered=self.triggered,
            immediate=self.immediate,
        )

    def payload(self) -> bytes:
        return pack_payload(self.samples)

    def stream(self) -> bytes:
        """Bytes the FPGA would push on FT601 TX after START/STOP."""
        return header_bytes(self.header_words()) + self.payload()

    def handle_cmd(self, cmd_word: int) -> bytes:
        opcode = cmd_word & 0xF
        if opcode not in (CMD_START, CMD_STOP, CMD_FORCE):
            return b""
        src = (cmd_word >> 4) & 3
        ch = (cmd_word >> 6) & 7
        edge = (cmd_word >> 9) & 3
        post = (cmd_word >> 16) & 0xFFFF
        self.source = src
        self.channel = ch
        self.edge = edge
        if post:
            self.post_cfg = post
        if opcode == CMD_FORCE:
            self.triggered = True
            self.immediate = True
        return self.stream()

    def write_lat3(self, path: str) -> str:
        os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)
        with open(path, "wb") as f:
            f.write(self.stream())
        return path


def _repeat(bit: int, n: int) -> List[int]:
    return [bit] * n


def uart_bits(payload: bytes, bit_samples: int) -> List[int]:
    """8N1 UART, idle-high, LSB first."""
    bits: List[int] = []
    for byte in payload:
        frame = [0] + [(byte >> i) & 1 for i in range(8)] + [1]
        for b in frame:
            bits.extend(_repeat(b, bit_samples))
    return bits


def find_falling(seq: Sequence[int]) -> Optional[int]:
    for i in range(1, len(seq)):
        if seq[i - 1] == 1 and seq[i] == 0:
            return i
    return None


def decode_uart(samples: bytes, ch: int, bit_samples: int) -> bytes:
    rx = channel_bits(samples, ch)
    out = bytearray()
    i = 0
    n = len(rx)
    while i < n - bit_samples:
        if not (rx[i] == 0 and (i == 0 or rx[i - 1] == 1)):
            i += 1
            continue
        mid = i + bit_samples + bit_samples // 2
        value = 0
        ok = True
        for b in range(8):
            idx = mid + b * bit_samples
            if idx >= n:
                ok = False
                break
            if rx[idx]:
                value |= 1 << b
        stop_idx = mid + 8 * bit_samples
        if not ok or stop_idx >= n or rx[stop_idx] != 1:
            i += 1
            continue
        out.append(value)
        i = i + 10 * bit_samples
    return bytes(out)


def _i2c_ext(sda: List[int], scl: List[int], sda_bit: int, scl_bit: int, n: int) -> None:
    sda.extend(_repeat(sda_bit, n))
    scl.extend(_repeat(scl_bit, n))


def i2c_write_bits(
    addr7: int, data: bytes, half_samples: int
) -> Tuple[List[int], List[int]]:
    """7-bit write: START, addr+W, ACK, data+ACK..., STOP. SDA/SCL idle-high."""
    sda: List[int] = []
    scl: List[int] = []
    n = half_samples

    def bit(b: int) -> None:
        _i2c_ext(sda, scl, b, 0, n)
        _i2c_ext(sda, scl, b, 1, n)

    def byte_with_ack(value: int) -> None:
        for i in range(7, -1, -1):
            bit((value >> i) & 1)
        bit(0)  # ACK pulled low

    _i2c_ext(sda, scl, 1, 1, n * 4)
    _i2c_ext(sda, scl, 1, 1, n)
    _i2c_ext(sda, scl, 0, 1, n)  # START
    _i2c_ext(sda, scl, 0, 0, n)
    byte_with_ack((addr7 & 0x7F) << 1)
    for d in data:
        byte_with_ack(d)
    # ACK leaves SCL high and SDA low; STOP is SDA rising while SCL is high.
    _i2c_ext(sda, scl, 0, 1, n)
    _i2c_ext(sda, scl, 1, 1, n)
    _i2c_ext(sda, scl, 1, 1, n * 4)
    return sda, scl


def decode_i2c(samples: bytes, sda_ch: int = 0, scl_ch: int = 1) -> List[Dict]:
    """Minimal START/STOP + MSB-first byte decoder (self-test, not libsigrok)."""
    sda = channel_bits(samples, sda_ch)
    scl = channel_bits(samples, scl_ch)
    events: List[Dict] = []
    bytes_now: List[int] = []
    bitacc = 0
    nbits = 0
    i = 1
    n = min(len(sda), len(scl))
    while i < n:
        if scl[i] == 1 and scl[i - 1] == 1 and sda[i - 1] == 1 and sda[i] == 0:
            if bytes_now:
                events.append({"type": "txn", "bytes": bytes_now})
                bytes_now = []
            events.append({"type": "start", "index": i})
            bitacc = 0
            nbits = 0
            i += 1
            continue
        if scl[i] == 1 and scl[i - 1] == 1 and sda[i - 1] == 0 and sda[i] == 1:
            if bytes_now:
                events.append({"type": "txn", "bytes": bytes_now})
                bytes_now = []
            events.append({"type": "stop", "index": i})
            bitacc = 0
            nbits = 0
            i += 1
            continue
        if scl[i - 1] == 0 and scl[i] == 1:
            bitacc = (bitacc << 1) | sda[i]
            nbits += 1
            if nbits == 9:
                data8 = (bitacc >> 1) & 0xFF
                ack = bitacc & 1
                bytes_now.append(data8)
                events.append({"type": "byte", "value": data8, "ack": ack == 0, "index": i})
                bitacc = 0
                nbits = 0
        i += 1
    return events


def _pad_channels(*seqs: Sequence[int], fill: int = 0, width: int = 8) -> List[List[int]]:
    n = max(len(s) for s in seqs)
    chans: List[List[int]] = []
    for i in range(width):
        if i < len(seqs):
            seq = list(seqs[i]) + [seqs[i][-1] if seqs[i] else fill] * (n - len(seqs[i]))
            chans.append(seq)
        else:
            chans.append([fill] * n)
    return chans


def make_uart_capture(
    payload: bytes = b"Hello UART\n",
    *,
    rate_hz: int = SAMPLE_RATE_HZ,
    baud: int = 1_000_000,
    idle_bits: int = 16,
) -> Capture:
    if rate_hz % baud != 0:
        raise ValueError(f"rate {rate_hz} is not a multiple of baud {baud}")
    bit_samples = rate_hz // baud
    idle = _repeat(1, idle_bits * bit_samples)
    rx = idle + uart_bits(payload, bit_samples) + idle
    samples = pack_channels(_pad_channels(rx, fill=0))
    trig = find_falling(rx)
    if trig is None:
        raise RuntimeError("UART start bit not found")
    return Capture(
        samples=samples,
        probes=("RX", "D1", "D2", "D3", "D4", "D5", "D6", "D7"),
        rate_hz=rate_hz,
        trig_pos=trig,
        channel=0,
        edge=EDGE_FALL,
        source=SRC_LIVE,
        post_cfg=len(samples) - trig,
        pattern="uart",
        notes=f"8N1 {baud} baud on RX (D0); payload {payload!r}",
    )


def make_i2c_capture(
    addr7: int = 0x50,
    data: bytes = b"Hi",
    *,
    rate_hz: int = SAMPLE_RATE_HZ,
    scl_hz: int = 400_000,
) -> Capture:
    if rate_hz % (scl_hz * 2) != 0:
        raise ValueError(f"rate {rate_hz} is not a multiple of 2*{scl_hz}")
    half = rate_hz // (scl_hz * 2)
    sda, scl = i2c_write_bits(addr7, data, half)
    samples = pack_channels(_pad_channels(sda, scl, fill=0))
    trig = find_falling(sda)
    if trig is None:
        raise RuntimeError("I2C START not found")
    return Capture(
        samples=samples,
        probes=("SDA", "SCL", "D2", "D3", "D4", "D5", "D6", "D7"),
        rate_hz=rate_hz,
        trig_pos=trig,
        channel=0,
        edge=EDGE_FALL,
        source=SRC_LIVE,
        post_cfg=len(samples) - trig,
        pattern="i2c",
        notes=f"I2C write {addr7:#04x} data={data!r} at {scl_hz} Hz (SDA=D0 SCL=D1)",
    )


def make_counter_capture(nsamples: int = 4096, *, rate_hz: int = SAMPLE_RATE_HZ) -> Capture:
    samples = bytes(i & 0xFF for i in range(nsamples))
    return Capture(
        samples=samples,
        probes=DEFAULT_PROBES,
        rate_hz=rate_hz,
        trig_pos=0,
        channel=0,
        edge=EDGE_RISE,
        source=SRC_COUNTER,
        post_cfg=nsamples,
        pattern="counter",
        notes="FPGA-style 8-bit counter (source 0)",
    )


def make_walking_capture(nsamples: int = 4096, *, rate_hz: int = SAMPLE_RATE_HZ) -> Capture:
    samples = bytes(1 << (i & 7) for i in range(nsamples))
    return Capture(
        samples=samples,
        probes=DEFAULT_PROBES,
        rate_hz=rate_hz,
        trig_pos=0,
        channel=0,
        edge=EDGE_RISE,
        source=SRC_WALKING,
        post_cfg=nsamples,
        pattern="walking",
        notes="FPGA-style walking-one (source 1)",
    )


PATTERNS = {
    "uart": make_uart_capture,
    "i2c": make_i2c_capture,
    "counter": make_counter_capture,
    "walking": make_walking_capture,
}


def export_capture(cap: Capture, out_dir: str, stem: Optional[str] = None) -> Dict[str, str]:
    stem = stem or cap.pattern
    os.makedirs(out_dir, exist_ok=True)
    dev = cap.device()
    paths = {
        "sr": os.path.join(out_dir, f"{stem}.sr"),
        "lat3": os.path.join(out_dir, f"{stem}.lat3"),
        "raw": os.path.join(out_dir, f"{stem}.raw"),
    }
    write_sr(paths["sr"], cap.samples, rate_hz=cap.rate_hz, probes=cap.probes)
    dev.write_lat3(paths["lat3"])
    write_raw(paths["raw"], cap.samples)
    return paths


def capture_from_lat3(path: str, *, probes: Sequence[str] = DEFAULT_PROBES,
                      rate_hz: int = SAMPLE_RATE_HZ) -> Capture:
    with open(path, "rb") as f:
        blob = f.read()
    hdr, samples = parse_lat3_stream(blob)
    return Capture(
        samples=samples,
        probes=tuple(probes),
        rate_hz=rate_hz,
        trig_pos=hdr["trig_pos"] if hdr["triggered"] else 0,
        channel=hdr["channel"],
        edge=hdr["edge"],
        source=hdr["source"],
        post_cfg=hdr["post_cfg"],
        pattern="lat3",
        notes=f"imported {path}",
    )
