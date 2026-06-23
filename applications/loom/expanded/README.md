# OPUS MAXIMUS / LOOM
## FPGA Multitrack Recorder with Instrument Separation

**Complete Master Design Document Set**  
**Version 1.0 — Implementation Ready**  
**Date:** 2026-06-21  
**Author:** GodBot 🜂 for codecbox

---

## What This Is

The complete architectural specification for LOOM — a standalone FPGA-based multitrack audio recorder with real-time instrument separation using the DUET algorithm.

Target: Arty A7-100T (XC7A100T) with CS42448 codec, ILI9341 2.4" SPI display + resistive touch

---

## Document Set

| # | Document | Description | Pages |
|---|----------|-------------|-------|
| 00 | [VISION](docs/00-VISION.md) | Product vision, user personas | ~8 |
| 01 | [PRODUCT-SPEC](docs/01-PRODUCT-SPEC.md) | Hardware specs, GUI design | ~20 |
| 02 | [SYSTEM-ARCHITECTURE](docs/02-SYSTEM-ARCHITECTURE.md) | Clocks, memory maps, reset | ~18 |
| 03 | [FPGA-AUDIO-FABRIC](docs/03-FPGA-AUDIO-FABRIC.md) | TDM I/O, DSP core RTL | ~24 |
| 04 | [DSP-MODULE-LIBRARY](docs/04-DSP-MODULE-LIBRARY.md) | Module specs, golden models | ~12 |
| 05 | [INSTRUMENT-SEPARATOR](docs/05-INSTRUMENT-SEPARATOR.md) | DUET algorithm, HLS blocks | ~15 |
| 06 | [CONTROL-PLANE](docs/06-CONTROL-PLANE.md) | NEORV32 firmware, HAL | ~18 |
| 07 | [GUI-DISPLAY-TOUCH](docs/07-GUI-DISPLAY-TOUCH.md) | ILI9341, XPT2046, widgets | ~20 |
| 08 | [STORAGE-RECORDING](docs/08-STORAGE-RECORDING.md) | DMA, FatFs, WAV format | ~18 |
| 09 | [RESOURCE-BUDGET](docs/09-RESOURCE-BUDGET.md) | FPGA resources, power | ~8 |
| 10 | [PROJECT-STRUCTURE](docs/10-PROJECT-STRUCTURE.md) | Directory tree, build flow | ~10 |
| 11 | [BUILD-PLAN](docs/11-BUILD-PLAN.md) | 5-stage development plan | ~12 |

**Total:** ~4,966 lines, ~200KB, 12 sections

---

## Quick Start

### For Hardware Engineers
Start with:
1. [02-SYSTEM-ARCHITECTURE](docs/02-SYSTEM-ARCHITECTURE.md) — Clock domains, memory map
2. [03-FPGA-AUDIO-FABRIC](docs/03-FPGA-AUDIO-FABRIC.md) — RTL structures, TDM I/O
3. [07-GUI-DISPLAY-TOUCH](docs/07-GUI-DISPLAY-TOUCH.md) — ILI9341 controller RTL

### For Firmware Engineers
Start with:
1. [06-CONTROL-PLANE](docs/06-CONTROL-PLANE.md) — HAL specifications
2. [07-GUI-DISPLAY-TOUCH](docs/07-GUI-DISPLAY-TOUCH.md) — Touch calibration, widgets
3. [08-STORAGE-RECORDING](docs/08-STORAGE-RECORDING.md) — FatFs integration

### For DSP/Algorithm Engineers
Start with:
1. [04-DSP-MODULE-LIBRARY](docs/04-DSP-MODULE-LIBRARY.md) — Module specifications
2. [05-INSTRUMENT-SEPARATOR](docs/05-INSTRUMENT-SEPARATOR.md) — DUET algorithm
3. [models/](../models/) — Python golden reference implementations

---

## The One Big Decision

**Don't use Partial Reconfiguration for the DSP.**

The DSP runs at 100 MHz, audio at 48 kHz → 2,083 cycles per sample. One DSP48 slice can process the entire 6-channel mixer. "Swapping modules" becomes writing coefficient tables to BRAM (microseconds), not reloading bitstreams (milliseconds).

Architecture: One time-multiplexed DSP core + specialty accelerators (DUET, reverb). See [Section 3](docs/03-FPGA-AUDIO-FABRIC.md).

---

## Key Specifications

| Feature | Specification |
|---------|---------------|
| Inputs | 6 channels via CS42448 (24-bit, 48kHz) |
| Outputs | 8 channels via CS42448 |
| Display | 2.4" ILI9341, 320×240, SPI + resistive touch |
| DSP | Software-defined, 6 pipes × 6 modules |
| Separation | DUET algorithm, up to 5 sources per stereo pair, 3 pairs max |
| Storage | MicroSD (FAT32/exFAT) |
| CPU | NEORV32 RISC-V (RV32IMC) @ 100 MHz |

---

## Build Stages

```
Stage 0: Foundation      — UART, display, touch, audio passthrough
Stage 1: DSP Core        — Single pipe, one module, golden model match
Stage 2: Studio Mode     — 6 pipes, full modules, recording, dubbing
Stage 3: Mastering       — Reverb, project save/load, export
Stage 4: Separation      — DUET algorithm, real-time separation
Stage 5: Productization  — Custom PCB, enclosure, manufacturing
```

See [Section 11](docs/11-BUILD-PLAN.md) for complete milestones.

---

## Repository Structure

```
opus_maximus_expanded/
├── docs/              # This document set (12 sections)
├── hardware/          # RTL, constraints, Vivado (to be created)
├── firmware/          # NEORV32 C code (to be created)
├── models/            # Python golden models (to be created)
├── test/              # Testbenches, golden vectors (to be created)
└── tools/             # Build scripts, utilities (to be created)
```

---

## Next Actions

1. **Create directory structure** per Section 10
2. **Set up Vivado project** with NEORV32
3. **Verify J-Link** connects to Arty
4. **Get UART "Hello World"** working
5. **Stage 0:** Display test pattern, touch coordinates, audio passthrough

---

## License

TBD — This is a personal R&D project.

---

*End of README*
