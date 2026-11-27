# PulseView eval from a simulated LAT3 device

No Ft+, no FPGA. This directory pretends to be `la_capture_top` on USB:
it emits the same **LAT3** dump the host tool in
[../ft601-capture](../ft601-capture/README.md) reads (PR #4 / #5), then
writes a sigrok v2 session PulseView can open.

```
simulated 8-ch samples → LAT3 header + packed payload → .sr / .raw
```

## Protocol (from `host/ft601-capture`)

Dump is 8 little-endian words then packed samples:

| word | meaning |
|---|---|
| 0 | MAGIC `0x3354414C` (`LAT3`) |
| 1 | VERSION `1` |
| 2 | STATUS (source, channel, edge, triggered, overflow, aborted, immediate) |
| 3 | `NSAMPLES` |
| 4 | `TRIG_POS` (or `0xFFFFFFFF`) |
| 5 | overflow count |
| 6 | drop count |
| 7 | configured post-trigger count |

Four 8-bit samples per 32-bit word, oldest in the LSB. Channel 0 is bit 0,
which is sigrok `probe1`. Default sample rate is **200 MHz**.

`.lat3` is that full USB stream (header + payload). `.raw` is unpacked
bytes, one sample per byte, for PulseView **File → Import → Raw binary**
(8 channels, 1 byte/unit, little-endian, 200 MHz). `.sr` is a zip with
`version`=`2`, INI `metadata`, and `logic-1-1`.

## How to run

```bash
make selftest          # no PulseView required
make canned            # uart.sr i2c.sr counter.sr walking.sr + .lat3/.raw
python3 eval_pulseview.py --pattern uart --open
python3 eval_pulseview.py --from-lat3 canned/uart.lat3 --sr /tmp/uart.sr
```

Optional (Debian/Ubuntu):

```bash
sudo apt-get install -y pulseview sigrok-cli xvfb
make decode            # UART + I2C annotations via sigrok-cli
make screenshot        # PulseView under Xvfb → canned/pulseview-uart.png
```

Open a canned session:

```bash
pulseview -c -D -i canned/uart.sr
# then Add decoder → UART, rx=RX, 1000000 baud
pulseview -c -D -i canned/i2c.sr
# then Add decoder → I2C, SDA=SDA, SCL=SCL
```

Canned UART is 8N1 **1 Mbaud** on `RX` (`Hello UART\n`). Canned I2C is a
**400 kHz** write to address `0x50` with data `Hi`. Counter / walking match
the on-FPGA test patterns (source 0 / 1).

Convert a hardware dump later: the capture tool writes payload-only today.
Wrap it with a LAT3 header (or pass `--from-lat3` once the dump includes the
header) and this exporter still applies.
