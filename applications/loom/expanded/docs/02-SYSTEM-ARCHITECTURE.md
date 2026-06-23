# OPUS MAXIMUS / LOOM — Section 2: SYSTEM ARCHITECTURE

**Document ID:** OPUS-02-SYSTEM-ARCHITECTURE  
**Version:** 1.0 — Implementation Ready  
**Date:** 2026-06-21  
**Author:** GodBot 🜂 for codecbox  
**Target:** Arty A7-100T (XC7A100T-1CSG324C)

---

## 2.1 System Block Diagram (Full Detail)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              LOOM SYSTEM ARCHITECTURE                            │
│                              XC7A100T-1CSG324C (A7-100T)                         │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                         CLOCK DOMAIN 100 MHz                                │   │
│  │                    (From Arty 100 MHz oscillator via MMCM)                  │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                    │                                             │
│                                    ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                         AUDIO FABRIC (100 MHz domain)                     │   │
│  │                                                                           │   │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────┐   │   │
│  │  │   TDM RX     │───▶│  DSP CORE    │───▶│   TDM TX                 │   │   │
│  │  │  6 channels  │    │ Time-muxed   │    │   8 channels             │   │   │
│  │  │   48kHz      │    │ MAC engine   │    │   48kHz                  │   │   │
│  │  └──────────────┘    │ 6 pipes ×    │    └──────────────────────────┘   │   │
│  │                      │ 6 modules    │                      │               │   │
│  │                      │ per pipe     │                      │               │   │
│  │                      └──────────────┘                      │               │   │
│  │                             │                              │               │   │
│  │                      ┌──────┴──────┐                       │               │   │
│  │                      ▼             ▼                       │               │   │
│  │              ┌──────────┐   ┌──────────┐                   │               │   │
│  │              │  Mix Bus │   │ Special  │                   │               │   │
│  │              │  Matrix  │   │ Accel    │                   │               │   │
│  │              │ (6 bus)  │   │ (DUET)   │                   │               │   │
│  │              └────┬─────┘   └────┬─────┘                   │               │   │
│  │                   │              │                         │               │   │
│  │                   └──────┬───────┘                         │               │   │
│  │                          ▼                                 │               │   │
│  │                   ┌──────────────┐                         │               │   │
│  │                   │ Audio DMA    │                         │               │   │
│  │                   │ (AXI4-Stream)│                         │               │   │
│  │                   └──────┬───────┘                         │               │   │
│  └──────────────────────────┼───────────────────────────────────────────────┘   │
│                             │                                                    │
│  ┌──────────────────────────┼───────────────────────────────────────────────┐   │
│  │                    CLOCK DOMAIN DDR3 (MIG-generated)                        │   │
│  │  ┌───────────────────────┼─────────────────────────────────────────────┐ │   │
│  │  │                       ▼                                             │ │   │
│  │  │  ┌──────────────────────────────────────────────────────────────┐   │ │   │
│  │  │  │              DDR3 SDRAM Controller (MIG)                     │   │ │   │
│  │  │  │                      256 MB                                    │   │ │   │
│  │  │  │  ┌─────────────────┬─────────────────┬─────────────────┐     │   │ │   │
│  │  │  │  │ Ring Buffers    │ Framebuffer     │ Delay Lines     │     │   │ │   │
│  │  │  │  │ (record/play)   │ 320×240×16bpp   │ (reverb/DSP)    │     │   │ │   │
│  │  │  │  │ 6 × 512KB each  │ = 150KB         │ variable        │     │   │ │   │
│  │  │  │  └─────────────────┴─────────────────┴─────────────────┘     │   │ │   │
│  │  │  └──────────────────────────────────────────────────────────────┘   │ │   │
│  │  └───────────────────────────────────────────────────────────────────────┘   │
│  └───────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌───────────────────────────────────────────────────────────────────────────┐   │
│  │                      CONTROL PLANE (NEORV32, 100 MHz)                       │   │
│  │                     RV32IMC, ~20K LUTs, memory-mapped I/O                     │   │
│  │                                                                             │   │
│  │  ┌─────────────────────────────────────────────────────────────────────┐   │   │
│  │  │                    Memory Map (simplified)                            │   │   │
│  │  │  0x4000_0000 - 0x4FFF_FFFF : DDR3 (256MB window)                     │   │   │
│  │  │  0x6000_0000 - 0x6000_0FFF : DSP Core Control/Status                  │   │   │
│  │  │  0x6000_1000 - 0x6000_1FFF : TDM I/O Control                         │   │   │
│  │  │  0x6000_2000 - 0x6000_2FFF : Audio DMA Control                       │   │   │
│  │  │  0x6000_3000 - 0x6000_3FFF : Display Controller (ILI9341)            │   │   │
│  │  │  0x6000_4000 - 0x6000_4FFF : Touch Controller (XPT2046)              │   │   │
│  │  │  0x6000_5000 - 0x6000_5FFF : I²C Controller (CS42448)                │   │   │
│  │  │  0x6000_6000 - 0x6000_6FFF : SPI Controller (SD Card)                │   │   │
│  │  │  0x6000_7000 - 0x6000_7FFF : System/Mode Control                     │   │   │
│  │  └─────────────────────────────────────────────────────────────────────┘   │   │
│  │                                                                             │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │   │
│  │  │   UART0      │  │    SPI0      │  │    I²C0      │  │   GPIO       │   │   │
│  │  │ (Debug/CLI)  │  │ (SD + TFT)   │  │ (CS42448)    │  │ (Buttons/LED)│   │   │
│  │  │  115200 baud │  │  ~10MHz      │  │  400kHz      │  │              │   │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘   │   │
│  │                                                                             │   │
│  │  ┌─────────────────────────────────────────────────────────────────────┐   │   │
│  │  │                    Firmware Stack                                     │   │   │
│  │  │  Application → Services → HAL → NEORV32 BSP → Hardware               │   │   │
│  │  │                                                                     │   │   │
│  │  │  App: GUI, Transport, Project Manager                               │   │   │
│  │  │  Svc: Mixer, Recorder, Separator Control                           │   │   │
│  │  │  HAL: Codec, DSP Core, DDR, SD, TFT, Touch                          │   │   │
│  │  └─────────────────────────────────────────────────────────────────────┘   │   │
│  └───────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌───────────────────────────────────────────────────────────────────────────┐   │
│  │                         PERIPHERAL INTERFACES                               │   │
│  │                                                                             │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐        │   │
│  │  │   CS42448 CODEC  │  │   ILI9341 TFT    │  │   XPT2046 TOUCH  │        │   │
│  │  │  TDM: 6ch ADC    │  │  320×240 RGB565  │  │  Resistive + Pen │        │   │
│  │  │       8ch DAC    │  │  SPI @ 10MHz     │  │  SPI @ 2MHz      │        │   │
│  │  │  I²C @ 400kHz    │  │  DC, RST, BL     │  │  IRQ (optional)  │        │   │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘        │   │
│  │                                                                             │   │
│  │  ┌──────────────────┐  ┌──────────────────┐                                 │   │
│  │  │   MicroSD Card   │  │   SEGGER J-Link  │                                 │   │
│  │  │  SPI or SDIO     │  │  JTAG (14-pin)   │                                 │   │
│  │  │  FAT32/exFAT     │  │  Debug + Flash   │                                 │   │
│  │  └──────────────────┘  └──────────────────┘                                 │   │
│  └───────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2.2 Clock Domains and Clocking Strategy

### 2.2.1 Clock Hierarchy

```
Arty 100 MHz OSC
       │
       ▼
   ┌─────────┐
   │  MMCM   │
   │ (PLL)   │
   └────┬────┘
        │
        ├──▶ 100 MHz — Fabric/DSP Core / NEORV32
        │
        ├──▶ 12.288 MHz — MCLK for CS42448 (48kHz × 256)
        │    (Integer division: 100MHz × 192/1562.5 ≈ 12.288MHz)
        │
        └──▶ 50 MHz — SPI clocks (divided further in logic)
```

### 2.2.2 MMCM Configuration

| Clock | Frequency | Source | Jitter | Use |
|-------|-----------|--------|--------|-----|
| CLKOUT0 | 100.000 MHz | VCO / 10 | < 0.1 ps | Main fabric clock |
| CLKOUT1 | 12.288 MHz | VCO / 81.38 | < 0.5 ps | CS42448 MCLK |
| CLKOUT2 | 48.000 kHz | CLKOUT1 / 256 | derived | Audio sample tick |

**Key Constraint:** MCLK must be clean (low jitter) for audio quality. Use dedicated clock buffer (BUFG) and keep trace short.

### 2.2.3 Clock Domain Crossing

All domains cross through **async FIFOs**:

| Crossing | Method | Depth |
|----------|--------|-------|
| Audio (48kHz) → Fabric (100MHz) | Sample FIFO | 16 samples |
| Fabric → DDR3 (MIG) | AXI4-Stream FIFO | 256 beats |
| DDR3 → NEORV32 | Memory-mapped | N/A (synchronous bridge) |

---

## 2.3 The Three Planes (Detailed)

### 2.3.1 Audio Plane — Hard Real-Time

| Property | Value |
|----------|-------|
| Clock | 100 MHz |
| Deadline | 2083 cycles per sample (100MHz / 48kHz) |
| Jitter Tolerance | ±10 cycles (99.5% margin) |
| CPU Access | None — fabric only |

**Data Flow:**
```
CS42448 TDM ──▶ TDM RX ──▶ [DSP CORE: gain → EQ → comp → pan ──▶ Mix Bus]
                                                    │
                                                    ▼
                                            [Special Accel]
                                                    │
                                              DMA ◀─┘
                                                    │
                                                    ▼
                                              DDR3 Ring Buffer
```

### 2.3.2 Control Plane — Soft Real-Time

| Property | Value |
|----------|-------|
| Clock | 100 MHz (same as fabric) |
| Response Requirement | < 16ms (GUI responsiveness) |
| IRQ Latency | < 1µs (via GIC) |
| Method | Memory-mapped registers |

**NEORV32 Responsibilities:**
1. Poll touch controller or respond to touch IRQ
2. Update framebuffer in DDR3
3. Write DSP coefficients to fabric
4. Manage transport state machine
5. Service SD card FatFs
6. Configure CS42448 via I²C

### 2.3.3 Storage Plane — Buffered Streaming

| Property | Value |
|----------|-------|
| Buffer Strategy | Ring buffers in DDR3 |
| Buffer Size | 512KB per channel × 6 = 3MB |
| Buffer Latency | ~1 second at 48kHz/24-bit |
| Overflow Protection | Watermark IRQ to CPU |

**Ring Buffer Layout in DDR3:**
```
DDR3 Address Space (256MB window at 0x4000_0000):

0x4000_0000 - 0x4007_FFFF : Channel 1 Ring Buffer (512KB)
0x4008_0000 - 0x400F_FFFF : Channel 2 Ring Buffer (512KB)
0x4010_0000 - 0x4017_FFFF : Channel 3 Ring Buffer (512KB)
0x4018_0000 - 0x401F_FFFF : Channel 4 Ring Buffer (512KB)
0x4020_0000 - 0x4027_FFFF : Channel 5 Ring Buffer (512KB)
0x4028_0000 - 0x402F_FFFF : Channel 6 Ring Buffer (512KB)

0x4030_0000 - 0x4032_57FF : Framebuffer (320×240×2 = 150KB)

0x4033_0000 - 0x403F_FFFF : Delay Lines + Reverb Buffers

0x4040_0000 - 0x43FF_FFFF : Remaining for other use
```

---

## 2.4 Memory Map (Complete)

### 2.4.1 Global Memory Map

| Region | Start | End | Size | Purpose |
|--------|-------|-----|------|---------|
| Boot ROM | 0x0000_0000 | 0x0000_7FFF | 32KB | NEORV32 boot code |
| Internal RAM | 0x0000_8000 | 0x0001_7FFF | 64KB | NEORV32 data/instruction |
| Reserved | 0x0001_8000 | 0x3FFF_FFFF | - | - |
| **DDR3** | **0x4000_0000** | **0x4FFF_FFFF** | **256MB** | **Main external memory** |
| Peripherals | 0x6000_0000 | 0x6FFF_FFFF | 256MB | Memory-mapped I/O |
| Reserved | 0x7000_0000 | 0xFFFF_FFFF | - | - |

### 2.4.2 Peripheral Memory Map

| Peripheral | Base | Offset Range | Register Block |
|------------|------|--------------|----------------|
| DSP Core Control | 0x6000_0000 | 0x0000 - 0x0FFF | See §3 |
| TDM I/O Control | 0x6000_1000 | 0x1000 - 0x1FFF | See §3 |
| Audio DMA | 0x6000_2000 | 0x2000 - 0x2FFF | See §3 |
| Display Ctrl (ILI9341) | 0x6000_3000 | 0x3000 - 0x3FFF | SPI bridge |
| Touch Ctrl (XPT2046) | 0x6000_4000 | 0x4000 - 0x4FFF | SPI bridge |
| I²C (CS42448) | 0x6000_5000 | 0x5000 - 0x5FFF | I²C master |
| SPI (SD Card) | 0x6000_6000 | 0x6000 - 0x6FFF | SPI master |
| System Control | 0x6000_7000 | 0x7000 - 0x7FFF | Mode, reset, status |
| Reserved | 0x6000_8000 | 0x8000 - 0xFFFF | Future expansion |

---

## 2.5 Reset Strategy

| Reset Level | Trigger | Scope |
|-------------|---------|-------|
| Power-on Reset | External button + Power good | Entire system |
| NEORV32 Reset | JTAG or software watchdog | CPU + peripherals |
| DSP Core Reset | Software via SysCtrl reg | Audio fabric only |
| Codec Reset | I²C command or GPIO | CS42448 |
| Display Reset | Software via GPIO | ILI9341 |

**Reset Sequence:**
1. Power-on Reset asserted
2. FPGA configuration loads from SPI flash
3. NEORV32 boot ROM executes
4. Software releases DSP Core reset
5. I²C configures CS42448
6. Display initialized via SPI
7. System ready

---

## 2.6 Interrupt Hierarchy

| IRQ # | Source | Priority | Handler |
|-------|--------|----------|---------|
| 0 | Sample Tick (48kHz) | Highest | DSP sequencer (internal) |
| 1 | Audio DMA Complete | High | DMA buffer swap |
| 2 | Touch IRQ | Medium | GUI event dispatch |
| 3 | SD Card IRQ | Medium | FatFs service |
| 4 | UART RX | Low | Debug CLI |
| 5 | Software Timer | Low | GUI animations |

---

## 2.7 Power Domains (Future)

For production board:

| Domain | Voltage | Components |
|--------|---------|------------|
| Core | 1.0V | FPGA core |
| Aux | 1.8V | FPGA aux, DDR3 |
| IO | 3.3V | All external I/O |
| Analog | 3.3V/5V | CS42448, audio path |

Current Arty dev board: all 3.3V/1.0V/1.8V from board regulators.

---

## 2.8 Design Principles

1. **Determinism over performance** — Audio plane must be cycle-accurate predictable
2. **Separation of concerns** — Audio, control, storage are distinct clock domains/planes
3. **Fail-safe defaults** — If NEORV32 crashes, audio passthrough continues
4. **Upgrade path** — Module library expandable via new coefficient tables, not bitstreams
5. **Debug visibility** — Every register readable, every signal observable via JTAG

---

## 2.9 Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-06-21 | GodBot | Initial architecture |
| 1.0 | 2026-06-21 | GodBot | Complete with memory maps, clock tree, reset strategy |

---

*End of Section 2 — SYSTEM ARCHITECTURE*
