# FT601 245 loopback simulation

Icarus Verilog (`iverilog` / `vvp`) test of the 32-bit 245 FIFO master against a
PHY-like model. No Vivado, no bitstream, no flash.

```bash
make -C platforms/alchitry-platinum-v2/sim/ft601
```

`+vcd` dumps `tb_ft601_loopback.vcd`.

## What it checks

- `ft_reset` is high after “DONE”; fabric `rst_ft` releases on `ft_clk` (PR #9 policy).
- PHY drives **RXF# / TXE#** as registered empty/full flags.
- DATA/BE appear **one clock after OE#** (turnaround); RD# pops only while DATA is driven.
- Monitor: no OE#+WR#, no RD# without OE#, no FPGA drive during OE#, one-clock WR#, OE# before RD#.
- Loopback of committed vectors (counter, walking-one, xor) and BE=`0x3` echo.
- TXE# backpressure: fill the PHY TX FIFO, then drain.

## Host-reusable vectors

`make vectors` (also a dependency of `make run`) writes little-endian `.bin` and
one-word-per-line `.hex` under `vectors/`. After a PASS, `vectors/sim_echo.bin`
is the FPGA echo of `counter.bin` (same bytes).

On the bench, with the loopback bitstream in **RAM only**:

```bash
python3 ../../host/ft601-loopback/ft601_loopback.py \
  --vector platforms/alchitry-platinum-v2/sim/ft601/vectors/counter.bin \
  --bytes 256
```

(From `host/ft601-loopback` use `--vector ../../sim/ft601/vectors/counter.bin`.)

The C tool accepts the same `--vector PATH`.
