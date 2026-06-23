# NeoRV32 I2C (TWI) Manual — codec-ft601 Project

**Date:** 2026-06-12 | **Firmware:** v25 (working) | **Author:** CodecBot

---

## 1. Hardware Layer — The TWI Controller

### 1.1 VHDL Architecture (`neorv32_twi.vhd`)

The NeoRV32 TWI is an I²C **host-mode-only** controller. Key internals:

- **Two registers:** `CTRL` (config/status) at offset 0, `DCMD` (data/command) at offset 4
- **TX FIFO + RX FIFO:** Commands/data written to DCMD go into TX FIFO. Received data (ACK + byte) goes into RX FIFO. FIFO depth is set by `IO_TWI_FIFO` generic (power of 2, min 1).
- **Clock generator:** `f_SCL = f_main / (4 × prescaler × (1 + CDIV))` where prescaler ∈ {2,4,8,64,128,1024,2048,4096} selected by PRSC[2:0], and CDIV is 0-15.
- **Bus engine FSM:** IDLE → START → TRANSMISSION → STOP/IDLE. Four non-overlapping clock phases per SCL cycle.
- **Tristate I/O:** SDA/SCL can only be actively driven LOW (open-drain). External pull-ups required.
- **Clock stretching:** Optional, enabled by `TWI_CTRL_CLKSTR` bit. When enabled, engine halts if device holds SCL low.

### 1.2 Register Map

| Register | Offset | Key Bits |
|----------|--------|----------|
| `CTRL` | `0xfff90000` | EN(0), PRSC(3:1), CDIV(7:4), CLKSTR(8), FIFO_SIZE(18:15), SENSE_SCL(27), SENSE_SDA(28), TX_FULL(29), RX_AVAIL(30), BUSY(31) |
| `DCMD` | `0xfff90004` | DATA(7:0), ACK(8), CMD(10:9) |

### 1.3 DCMD Commands

| CMD[10:9] | Operation | Description |
|-----------|-----------|-------------|
| `00` | NOP | No operation |
| `01` | START | Generate (repeated) START condition |
| `10` | STOP | Generate STOP condition |
| `11` | RTX | Transmit+receive: send DATA[7:0], receive byte into RX FIFO. ACK[8] = host ACK (1=ACK, 0=NACK) |

### 1.4 Bus Line Sensing

`TWI_CTRL_SENSE_SCL` (bit 27) and `TWI_CTRL_SENSE_SDA` (bit 28) read the actual bus state. Both should read HIGH (1) when idle. If either is LOW, the bus is stuck — check pull-ups.

---

## 2. Software Driver (`neorv32_twi.c` / `neorv32_twi.h`)

### 2.1 Key Functions

```c
// Check if TWI synthesized
int neorv32_twi_available(void);

// Configure: prsc (0-7), cdiv (0-15), clkstr (0/1)
void neorv32_twi_setup(int prsc, int cdiv, int clkstr);

// Get FIFO depth (power of 2)
int neorv32_twi_get_fifo_depth(void);

// Enable/disable
void neorv32_twi_enable(void);
void neorv32_twi_disable(void);

// Bus state
int neorv32_twi_sense_scl(void);  // 1=high, 0=low
int neorv32_twi_sense_sda(void);

// Busy check
int neorv32_twi_busy(void);  // 0=idle, 1=busy

// Read from RX FIFO: returns -1 (no data), 0 (device ACK), 1 (device NACK)
int neorv32_twi_get(uint8_t *data);

// BLOCKING transfer: send byte, wait for response
// mack=0: host sends NACK, mack=1: host sends ACK
// Returns 0 (device ACK) or 1 (device NACK)
int neorv32_twi_transfer(uint8_t *data, int mack);

// BLOCKING start/stop
void neorv32_twi_generate_start(void);
void neorv32_twi_generate_stop(void);

// NON-BLOCKING versions (don't wait for TX FIFO space)
void neorv32_twi_send_nonblocking(uint8_t data, int mack);
void neorv32_twi_generate_start_nonblocking(void);
void neorv32_twi_generate_stop_nonblocking(void);
```

### 2.2 Clock Speed Examples (f_main = 160 MHz)

| PRSC | Prescaler | CDIV | f_SCL | Use Case |
|------|-----------|------|-------|----------|
| 0 | 2 | 0 | 20 MHz | Too fast for most devices |
| 2 | 8 | 0 | 5 MHz | Fast-mode devices |
| 3 | 64 | 5 | ~104 kHz | Standard-mode (100 kHz) |
| 6 | 2048 | 15 | ~1.2 kHz | Debug / safe fallback |

Formula: `f_SCL = 160,000,000 / (4 × prescaler × (1 + CDIV))`

---

## 3. I2C Protocol — CORRECT Sequences

### 3.1 I2C Write (Single Register)

```
START → addr|W → ACK? → reg → ACK? → data → ACK? → STOP
```

**Correct implementation:**
```c
static int i2c_write(uint8_t addr, uint8_t reg, uint8_t val) {
    int nack = 0;
    uint8_t d;
    neorv32_twi_generate_start();
    d = addr << 1;        nack |= neorv32_twi_transfer(&d, 0);
    d = reg;              nack |= neorv32_twi_transfer(&d, 0);
    d = val;              nack |= neorv32_twi_transfer(&d, 0);
    neorv32_twi_generate_stop();
    twi_rx_drain();  // drain RX FIFO
    return nack ? -1 : 0;
}
```

### 3.2 I2C Read (Single Register) — THE CRITICAL ONE

**❌ WRONG (v24 and earlier):**
```
START → addr|W → reg → STOP → START → addr|R → 0xFF(host ACK) → STOP
```
Problems: STOP between phases kills the transaction. Host ACK on last byte tells device "send more."

**✅ CORRECT (v25, per I2C spec §3.1.8 and official `twi_flash_read_word`):**
```
START → addr|W → reg → REPEATED-START → addr|R → 0xFF(host NACK) → STOP
```

**Correct implementation:**
```c
static uint8_t i2c_read(uint8_t addr, uint8_t reg) {
    uint8_t d;
    // Phase 1: Write register address
    neorv32_twi_generate_start();
    d = addr << 1;
    if (neorv32_twi_transfer(&d, 0)) { neorv32_twi_generate_stop(); twi_rx_drain(); return 0xFF; }
    d = reg;
    if (neorv32_twi_transfer(&d, 0)) { neorv32_twi_generate_stop(); twi_rx_drain(); return 0xFF; }
    // Phase 2: REPEATED-START + read (NO STOP between phases!)
    neorv32_twi_generate_start();  // ← REPEATED-START
    d = (addr << 1) | 1;
    if (neorv32_twi_transfer(&d, 0)) { neorv32_twi_generate_stop(); twi_rx_drain(); return 0xFF; }
    // Read data — host NACK (mack=0) = "last byte, stop sending"
    d = 0xFF;
    neorv32_twi_transfer(&d, 0);  // mack=0 = host NACK
    uint8_t val = d;
    neorv32_twi_generate_stop();
    twi_rx_drain();
    return val;
}
```

### 3.3 Why REPEATED-START Matters

The I2C spec defines a "combined format" read:
1. Host sends START + device address (W) + register address
2. Host sends REPEATED-START (Sr) — SCL stays low, SDA goes high then low while SCL is high
3. Host sends device address (R) + reads data

A STOP between steps 1 and 2 tells the device "transaction over." The device resets its state machine. The subsequent START is a new transaction where the device has no context of which register was requested.

### 3.4 Host ACK/NACK Rules

| Phase | mack value | Meaning |
|-------|-----------|---------|
| Address byte (W or R) | 0 (NACK) | Host never ACKs address bytes — device ACKs |
| Writing data to device | 0 (NACK) | Host doesn't ACK — device ACKs receipt |
| Reading data (not last byte) | 1 (ACK) | "Send me more data" |
| Reading data (last byte) | 0 (NACK) | "Stop sending" |

### 3.5 RX FIFO Drain

After every transaction, drain the RX FIFO. Each `neorv32_twi_transfer()` pushes the received byte+ACK into the RX FIFO. If not drained, stale data corrupts subsequent reads.

```c
static void twi_rx_drain(void) {
    uint8_t dummy;
    while (neorv32_twi_get(&dummy) != -1) { /* discard */ }
}
```

---

## 4. Common Pitfalls

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Alternating 0x00/0xFF on reads | STOP between write and read phases | Use REPEATED-START |
| Register reads return 0xFF | Device NACK on address | Check bus pull-ups, clock speed |
| First few registers read OK, rest garbage | RX FIFO not drained | Call `twi_rx_drain()` after each transaction |
| Bus stuck (SCL or SDA low) | Device holding bus, missing pull-ups | Check `neorv32_twi_sense_scl/sda()`, add pull-ups |
| `neorv32_uart0_printf` doesn't format hex | No width specifiers supported | Use `phex(byte)` / `phex32(uint32_t)` helpers |
| UART input not working | Using `char_received()` instead of `char_received_get()` | Always use `_get()` variant to consume byte |

---

## 5. Our Hardware Configuration

### 5.1 Pin Map (neorv_basic / ptv2_basic.xdc)

| Signal | FPGA Pin | Br Pin | Notes |
|--------|----------|--------|-------|
| SCL | B20 | — | I2C clock, PULLUP enabled in XDC |
| SDA | C14 | — | I2C data, PULLUP enabled in XDC |
| MCLK | D16 | — | 12.288 MHz audio master clock |
| SCLK | A19 | — | TDM bit clock (from clk_gen_0) |
| LRCLK | A18 | — | TDM frame clock (from clk_gen_0) |
| SDOUT (codec→FPGA) | D21 | — | TDM serial data from ADC |
| SDIN (FPGA→codec) | A21 | — | TDM serial data to DAC |

### 5.2 I2C Devices on Bus

| Address | Device | Function |
|---------|--------|----------|
| 0x48 | CS42448 | Audio codec (TDM) |
| 0x60 | Si5351A | Clock generator (not yet configured) |

### 5.3 Current Clock Config (v25)

- PRSC=6 (prescaler=2048), CDIV=15 → f_SCL ≈ 1.2 kHz (safe debug speed)
- For production: PRSC=3 (prescaler=64), CDIV=5 → f_SCL ≈ 104 kHz

---

## 6. Debug Console Commands (v25)

```
sys              — Show system info (clock, memory)
i2c raw          — Show TWI_CTRL register, FIFO depth, bus state
i2c scan         — Scan all 128 addresses, report ACKs
i2c read A R     — Read register R from device A (e.g. i2c read 0x48 0x01)
i2c write A R V  — Write value V to register R on device A
codec init       — Full CS42448 TDM initialization
codec dump       — Dump all CS42448 registers (0x01-0x1B)
clk on/off       — Enable/disable audio clocks (GPIO5)
gpio r N         — Read GPIO pin N
gpio w N V       — Write GPIO pin N = V
gpio dump        — Show all GPIO states
help             — Command list
```

---

## 7. Reference Sources

- **TWI VHDL:** `neorv32_twi.vhd` in NeoRV32 IP source
- **TWI Datasheet:** `docs/datasheet/soc_twi.adoc` in NeoRV32 repo
- **Driver source:** `sw/lib/source/neorv32_twi.c`
- **Driver header:** `sw/lib/include/neorv32_twi.h`
- **Official example:** `sw/example/demo_twi/main.c` (TWI bus explorer)
- **Bootloader reference:** `sw/bootloader/hal/source/twi_flash.c` (correct read sequence)
- **I2C Specification:** NXP UM10204, §3.1.8 "Combined formats"
- **CS42448 Datasheet:** `docs/CS42448_F5.pdf`
