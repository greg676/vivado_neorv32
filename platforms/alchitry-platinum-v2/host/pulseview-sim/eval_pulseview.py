#!/usr/bin/env python3
"""Generate LAT3 sim dumps and PulseView .sr sessions. Optionally open PulseView.

No FT601 / FPGA required. Canned UART and I2C traces plus FPGA counter/walking
patterns. `--self-test` is offline; `--decode` uses sigrok-cli when installed;
`--open` / `--screenshot` need PulseView + a display (xvfb is enough).
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
from typing import Dict, List, Optional

from lat3_sim import (
    CMD_START,
    EDGE_FALL,
    LAT3_MAGIC,
    PATTERNS,
    SAMPLE_RATE_HZ,
    SRC_COUNTER,
    SimulatedLat3Device,
    capture_from_lat3,
    decode_i2c,
    decode_uart,
    export_capture,
    make_cmd,
    make_counter_capture,
    make_i2c_capture,
    make_uart_capture,
    make_walking_capture,
    parse_lat3_stream,
    unpack_word,
    write_sr,
)

UART_PAYLOAD = b"Hello UART\n"
I2C_ADDR = 0x50
I2C_DATA = b"Hi"
UART_BAUD = 1_000_000
I2C_SCL = 400_000


def which(name: str) -> Optional[str]:
    return shutil.which(name)


def run(cmd: List[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=False, capture_output=True, text=True, **kw)


def self_test() -> int:
    errors: List[str] = []

    def check(cond: bool, msg: str) -> None:
        if not cond:
            errors.append(msg)

    cmd = make_cmd(CMD_START, SRC_COUNTER, 0, EDGE_FALL, 64)
    check((cmd & 0xF) == CMD_START, "START opcode packing")
    check(((cmd >> 9) & 3) == EDGE_FALL, "edge packing")

    uart = make_uart_capture(UART_PAYLOAD, baud=UART_BAUD)
    got = decode_uart(uart.samples, 0, uart.rate_hz // UART_BAUD)
    check(got == UART_PAYLOAD, f"UART decode {got!r} != {UART_PAYLOAD!r}")
    check(uart.samples[uart.trig_pos] & 1 == 0, "UART trigger is start-bit low")
    check(uart.trig_pos > 0 and (uart.samples[uart.trig_pos - 1] & 1) == 1,
          "UART trigger is a falling edge")

    i2c = make_i2c_capture(I2C_ADDR, I2C_DATA)
    ev = decode_i2c(i2c.samples)
    starts = [e for e in ev if e["type"] == "start"]
    stops = [e for e in ev if e["type"] == "stop"]
    txn = [e for e in ev if e["type"] == "txn"]
    check(len(starts) == 1 and len(stops) == 1, f"I2C start/stop {starts!r} {stops!r}")
    check(bool(txn) and txn[0]["bytes"][0] == (I2C_ADDR << 1),
          f"I2C address byte {txn}")
    check(bool(txn) and bytes(txn[0]["bytes"][1:1 + len(I2C_DATA)]) == I2C_DATA,
          f"I2C data {txn}")

    ctr = make_counter_capture(64)
    walk = make_walking_capture(8)
    check(ctr.samples[:4] == bytes([0, 1, 2, 3]), "counter samples")
    check(walk.samples[:4] == bytes([0x01, 0x02, 0x04, 0x08]), "walking samples")

    dev = uart.device()
    blob = dev.handle_cmd(make_cmd(CMD_START, 2, 0, EDGE_FALL, 128))
    hdr, samples = parse_lat3_stream(blob)
    check(hdr["magic"] == LAT3_MAGIC, "LAT3 magic")
    check(hdr["triggered"] and hdr["nsamples"] == len(uart.samples), "LAT3 nsamples")
    check(samples == uart.samples, "LAT3 payload round-trip")
    check(unpack_word(int.from_bytes(dev.payload()[:4], "little")) == tuple(uart.samples[:4]),
          "packed word 0 is first four samples")

    bad = bytearray(blob)
    bad[0] ^= 1
    try:
        parse_lat3_stream(bytes(bad))
        errors.append("bad MAGIC did not fail closed")
    except ValueError:
        pass

    with tempfile.TemporaryDirectory() as tmp:
        paths = export_capture(uart, tmp, "uart")
        with zipfile.ZipFile(paths["sr"]) as zf:
            names = set(zf.namelist())
            check(names == {"version", "metadata", "logic-1-1"}, f".sr members {names}")
            check(zf.read("version") == b"2", "version is 2")
            meta = zf.read("metadata").decode()
            check("samplerate=200 MHz" in meta, f"samplerate in metadata: {meta!r}")
            check("probe1=RX" in meta, "UART probe1=RX")
            check(zf.read("logic-1-1") == uart.samples, "logic-1-1 payload")
        again = capture_from_lat3(paths["lat3"], probes=uart.probes, rate_hz=uart.rate_hz)
        check(again.samples == uart.samples, "import .lat3 samples")
        check(again.trig_pos == uart.trig_pos, "import .lat3 trig_pos")

        sr_cli = which("sigrok-cli")
        if sr_cli:
            show = run([sr_cli, "-i", paths["sr"], "--show"])
            check(show.returncode == 0, f"sigrok-cli --show failed: {show.stderr}")
            show_txt = show.stdout
            check("200000000" in show_txt or "200 MHz" in show_txt,
                  f"show samplerate: {show_txt}")
            check("RX" in show_txt, f"show channels: {show_txt}")
            dec = run([
                sr_cli, "-i", paths["sr"],
                "-P", f"uart:rx=RX:baudrate={UART_BAUD}",
                "-A", "uart=rx-data",
            ])
            check(dec.returncode == 0, f"uart decoder failed: {dec.stderr}")
            hex_bytes = [
                ln.split(":")[-1].strip()
                for ln in dec.stdout.splitlines()
                if ln.strip()
            ]
            try:
                decoded = bytes(int(h, 16) for h in hex_bytes)
            except ValueError:
                decoded = b""
            check(
                decoded == UART_PAYLOAD or "Hello UART" in dec.stdout,
                f"uart decoder output: {dec.stdout!r} decoded={decoded!r}",
            )

            i2c_paths = export_capture(i2c, tmp, "i2c")
            i2c_dec = run([
                sr_cli, "-i", i2c_paths["sr"],
                "-P", "i2c:sda=SDA:scl=SCL",
                "-A", "i2c",
            ])
            check(i2c_dec.returncode == 0, f"i2c decoder failed: {i2c_dec.stderr}")
            text = i2c_dec.stdout
            check("50" in text or "Address write: 50" in text or "0x50" in text,
                  f"i2c address missing: {text!r}")
            check("48" in text or "Hi" in text,  # 0x48='H', 0x69='i'
                  f"i2c data missing: {text!r}")
        else:
            print("self-test: sigrok-cli not on PATH (skipped decoder checks)")

    if errors:
        for e in errors:
            print(f"self-test FAIL: {e}", file=sys.stderr)
        return 1
    print("self-test PASS (LAT3 + UART/I2C traces + .sr"
          + (" + sigrok-cli decode" if which("sigrok-cli") else "")
          + ")")
    return 0


def generate(pattern: str, out_dir: str) -> Dict[str, Dict[str, str]]:
    os.makedirs(out_dir, exist_ok=True)
    names = list(PATTERNS) if pattern == "all" else [pattern]
    written: Dict[str, Dict[str, str]] = {}
    for name in names:
        cap = PATTERNS[name]()
        paths = export_capture(cap, out_dir, name)
        written[name] = paths
        print(f"{name:8s}  samples={len(cap.samples)}  trig={cap.trig_pos}  "
              f"{cap.notes}")
        for kind, path in paths.items():
            print(f"          {kind:4s}  {path}")
        meta_path = os.path.join(out_dir, f"{name}.txt")
        with open(meta_path, "w", encoding="utf-8") as f:
            f.write(
                f"pattern={cap.pattern}\n"
                f"notes={cap.notes}\n"
                f"rate_hz={cap.rate_hz}\n"
                f"nsamples={len(cap.samples)}\n"
                f"trig_pos={cap.trig_pos}\n"
                f"probes={','.join(cap.probes)}\n"
                f"raw_import=PulseView File>Import>Raw binary; "
                f"8 channels; 1 byte/sample; little-endian; "
                f"{cap.rate_hz} Hz; bit0=probe1={cap.probes[0]}\n"
            )
        written[name]["txt"] = meta_path
    return written


def sigrok_show(sr_path: str) -> int:
    cli = which("sigrok-cli")
    if not cli:
        print("sigrok-cli not found; install sigrok-cli to inspect .sr files",
              file=sys.stderr)
        return 2
    show = run([cli, "-i", sr_path, "--show"])
    sys.stdout.write(show.stdout)
    sys.stderr.write(show.stderr)
    return show.returncode


def sigrok_decode(sr_path: str, pattern: str) -> int:
    cli = which("sigrok-cli")
    if not cli:
        print("sigrok-cli not found", file=sys.stderr)
        return 2
    if pattern == "uart":
        cmd = [cli, "-i", sr_path, "-P", f"uart:rx=RX:baudrate={UART_BAUD}",
               "-A", "uart"]
    elif pattern == "i2c":
        cmd = [cli, "-i", sr_path, "-P", "i2c:sda=SDA:scl=SCL", "-A", "i2c"]
    else:
        cmd = [cli, "-i", sr_path, "-O", "ascii:width=80"]
    print("+", " ".join(cmd))
    proc = run(cmd)
    sys.stdout.write(proc.stdout)
    sys.stderr.write(proc.stderr)
    return proc.returncode


def open_pulseview(sr_path: str, extra: Optional[List[str]] = None) -> subprocess.Popen:
    pv = which("pulseview")
    if not pv:
        raise FileNotFoundError("pulseview not on PATH")
    cmd = [pv, "-c", "-D", "-i", os.path.abspath(sr_path)]
    if extra:
        cmd.extend(extra)
    print("+", " ".join(cmd))
    return subprocess.Popen(cmd)


def screenshot_pulseview(sr_path: str, png_path: str, wait_s: float = 4.0) -> int:
    """Launch PulseView under the current DISPLAY (or xvfb) and capture the window."""
    if not which("pulseview"):
        print("pulseview not on PATH", file=sys.stderr)
        return 2
    os.makedirs(os.path.dirname(os.path.abspath(png_path)) or ".", exist_ok=True)
    env = os.environ.copy()
    xvfb = None
    if not env.get("DISPLAY"):
        if not which("Xvfb"):
            print("no DISPLAY and no Xvfb; cannot screenshot PulseView", file=sys.stderr)
            return 2
        xvfb = subprocess.Popen(
            ["Xvfb", ":99", "-screen", "0", "1600x900x24", "-ac"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        env["DISPLAY"] = ":99"
        time.sleep(0.4)
    try:
        proc = subprocess.Popen(
            ["pulseview", "-c", "-D", "-i", os.path.abspath(sr_path)],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        time.sleep(wait_s)
        if which("xdotool"):
            subprocess.run(
                ["xdotool", "search", "--sync", "--class", "PulseView",
                 "windowmove", "0", "0", "windowsize", "1600", "900"],
                env=env, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            time.sleep(0.5)
        grab = None
        if which("import"):
            grab = run(["import", "-window", "root", png_path], env=env)
        elif which("scrot"):
            grab = run(["scrot", png_path], env=env)
        else:
            print("need ImageMagick `import` or `scrot` for screenshots", file=sys.stderr)
            proc.terminate()
            return 2
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
        if grab.returncode != 0 or not os.path.isfile(png_path):
            print(f"screenshot failed: {grab.stderr}", file=sys.stderr)
            return 1
        if which("mogrify"):
            subprocess.run(["mogrify", "-trim", "+repage", png_path], check=False)
        print(f"screenshot  {png_path}  ({os.path.getsize(png_path)} bytes)")
        return 0
    finally:
        if xvfb is not None:
            xvfb.terminate()
            try:
                xvfb.wait(timeout=2)
            except subprocess.TimeoutExpired:
                xvfb.kill()


def main() -> int:
    p = argparse.ArgumentParser(
        description="Simulated LAT3 LA → PulseView .sr (no hardware)")
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--pattern", choices=("uart", "i2c", "counter", "walking", "all"),
                   default="all")
    p.add_argument("--rate", type=float, default=SAMPLE_RATE_HZ,
                   help="sample rate Hz (default 200e6)")
    p.add_argument("--out-dir", default="canned")
    p.add_argument("--from-lat3", metavar="FILE",
                   help="convert a LAT3 header+payload dump to .sr")
    p.add_argument("--sr", metavar="FILE", help="explicit .sr path (with --from-lat3)")
    p.add_argument("--decode", action="store_true",
                   help="run sigrok-cli protocol decoders on generated files")
    p.add_argument("--open", action="store_true",
                   help="launch PulseView on the first generated .sr")
    p.add_argument("--screenshot", metavar="PNG",
                   help="capture PulseView (uses DISPLAY, or Xvfb :99)")
    args = p.parse_args()
    args.rate = int(args.rate)

    if args.self_test:
        return self_test()

    if args.from_lat3:
        cap = capture_from_lat3(args.from_lat3, rate_hz=args.rate)
        sr_path = args.sr or os.path.splitext(args.from_lat3)[0] + ".sr"
        write_sr(sr_path, cap.samples, rate_hz=cap.rate_hz, probes=cap.probes)
        print(f"converted {args.from_lat3} -> {sr_path}  nsamples={len(cap.samples)}")
        if args.decode:
            return sigrok_show(sr_path)
        return 0

    written = generate(args.pattern, args.out_dir)
    rc = 0
    if args.decode:
        for name, paths in written.items():
            show_rc = sigrok_show(paths["sr"])
            dec_rc = sigrok_decode(paths["sr"], name)
            rc = rc or show_rc or dec_rc
    first_sr = next(iter(written.values()))["sr"]
    if args.screenshot:
        rc = rc or screenshot_pulseview(first_sr, args.screenshot)
    if args.open:
        try:
            open_pulseview(first_sr)
        except FileNotFoundError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2
    return rc


if __name__ == "__main__":
    sys.exit(main())
