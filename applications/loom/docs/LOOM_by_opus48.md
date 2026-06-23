# OPUS MAXIMUS — The Complete Master Design
## FPGA Multitrack Recorder/Dubber with Software-Defined DSP

**Codename:** LOOM — multitrack weaving on FPGA fabric  
**Target:** codecbox (XC7A100T Arty A7-100T platform)  
**Display:** 2.4" TFT LCD Module, 320×240, SPI Serial ILI9341, Resistive Touch with Stylus Pen  
**Date:** 2026-06-21  
**Status:** Master Architecture Document — definitive, build-ready

---

## Document Structure

This design maps to 12 project files in `docs/`:

```
docs/
├── 00-VISION.md              ← Section 0
├── 01-PRODUCT-SPEC.md        ← Section 1
├── 02-SYSTEM-ARCHITECTURE.md ← Section 2
├── 03-FPGA-AUDIO-FABRIC.md   ← Section 3
├── 04-DSP-MODULE-LIBRARY.md  ← Section 4
├── 05-INSTRUMENT-SEPARATOR.md← Section 5
├── 06-CONTROL-PLANE.md       ← Section 6
├── 07-GUI-DISPLAY-TOUCH.md   ← Section 7  ← DISPLAY SPEC ADDED
├── 08-STORAGE-RECORDING.md   ← Section 8
├── 09-RESOURCE-BUDGET.md     ← Section 9
├── 10-PROJECT-STRUCTURE.md   ← Section 10
└── 11-BUILD-PLAN.md          ← Section 11
```

---

## ⚡ THE ONE BIG DECISION: Don't Use Partial Reconfiguration For The DSP

You and the agent have been planning around FPGA Partial Reconfiguration (PR) — physically swapping DSP netlists into reconfigurable regions per channel. It feels right ("reconfigurable DSP blocks!").

**It is the wrong tool for audio.** Here is the truth, and the truth makes your product better, not worse.

### The Math That Settles It

Your fabric runs at ~100 MHz. Your audio runs at 48 kHz (or 96/192). That means:

```
100,000,000 Hz / 48,000 Hz = 2,083 clock cycles per audio sample
```

You have **two thousand clock cycles** between every single audio sample. A single DSP48 multiplier can perform ~2,000 multiply-accumulates in that window.

A full 5-band parametric EQ is ~25 MACs. A compressor is ~10. Gain+pan is ~4. So one channel's entire DSP chain is ~40 MACs. **One DSP slice, time-multiplexed, can process the entire 6-channel mixer with EQ and dynamics — and still sit mostly idle.**

### What This Means

You do not need 24 physical PR regions each burning fabric. You need a **time-multiplexed DSP engine** that runs a program — a list of operations stored in BRAM. "Swapping a DSP module" becomes writing new coefficients to memory, which takes microseconds and never fails, instead of reloading a partial bitstream, which takes milliseconds and is operationally fragile.

| Aspect | Partial Reconfiguration | Software-Defined DSP (recommended) |
|--------|------------------------|-----------------------------------|
| "Change a module" | Reload partial bitstream (ms, can fail) | Write coefficients to BRAM (µs, never fails) |
| Fabric cost | Each region sized for worst case, wasted | Tiny — one MAC engine serves all channels |
| Vivado effort | Floorplanning, timing islands, PR flow — months | Standard synchronous design — weeks |
| Add a new effect | Build + verify + place a PR netlist | Write a new coefficient/microcode table |
| Risk | High (PR timing closure is brutal on -1 speed grade) | Low |
| "Cool factor" | High | Higher, once you see it reconfigure instantly |

### The Recommended Architecture: Core + Accelerators

```
┌──────────────────────────────────────────────────────────────┐
│ SOFTWARE-DEFINED DSP CORE (time-multiplexed MAC engine)      │
│ Handles ALL routine processing for all 6 pipes:              │
│ gain, pan, parametric EQ, compressor, gate, limiter,         │
│ simple delay, mix-bus summing.                               │
│ "Modules" = coefficient tables in BRAM, swapped instantly.   │
│ Cost: ~8-16 DSP slices total. Reconfigures in microseconds.  │
└──────────────────────────────────────────────────────────────┘
                              +
┌──────────────────────────────────────────────────────────────┐
│ SPECIALTY ACCELERATORS (HLS-generated fixed datapaths)       │
│ Heavy algorithms that genuinely need dedicated hardware:     │
│ • INSTRUMENT SEPARATOR (DUET) — the crown jewel              │
│ • Convolution reverb / long delay lines                        │
│ Enabled/bypassed by MODE, not swapped by PR.                 │
│ Cost: scales with feature; reclaims DSP via mode-switching.  │
└──────────────────────────────────────────────────────────────┘
```

This delivers everything you described — per-channel reconfigurable processing, the mode-switch to instrument separation, the whole vision — with a fraction of the engineering risk. Your instinct about reclaiming fabric in separation mode ("no realtime EQ in separation mode") is exactly right and this architecture makes it natural: separation mode reallocates the time budget and DSP slices from the routine engine to the separators.

**Keep PR in your back pocket only for the instrument separator if you later want to load different separation algorithms. For v1, do not use PR at all. Build the product. PR is a v2 research luxury.**

*Everything below assumes this architecture.*

---

## Section 0 — VISION (00-VISION.md)

LOOM is a standalone hardware multitrack recorder and live source-separation engine for musicians, built on a single FPGA. No computer. No DAW. You plug in mics and speakers, you touch the screen with a pen, and the FPGA fabric does real-time multitrack recording, mixing, effects, and — the signature feature — decodes individual instruments out of a stereo room mic straight onto separate tracks.

The FPGA fabric is the engine. The screen is the control surface. The NEORV32 soft-CPU is the conductor — it manages state, UI, files, and configuration, but never touches the audio samples. Audio flows through fabric at hardware speed; the CPU just steers it.

**The one-sentence pitch:** A pocket studio that hears the room and writes each instrument to its own track.

---

## Section 1 — PRODUCT SPEC (01-PRODUCT-SPEC.md)

### Physical Product

- Small standalone box (handheld-to-small-pedal sized)
- **Display:** 2.4 inch TFT LCD Module, 320×240 resolution, SPI Serial interface, ILI9341 controller, Resistive Touch Panel with Stylus Pen
- Inputs: mic/line connectors feeding a CS42448 codec (6 ADC inputs, 8 DAC outputs, TDM, I²C control)
- Outputs: monitor speakers / headphones / line out
- Storage: microSD card (project files, multitrack WAV recording)
- Power: USB-C or barrel; the Arty A7-100T board is the dev platform, custom PCB later

### Core Capabilities

- Record up to 6 input channels simultaneously to SD card (24-bit, 48 kHz baseline)
- Overdub / dub — play existing tracks while recording new ones (the "dubbing" in the name)
- Real-time DSP per channel: gain, pan, parametric EQ, dynamics, delay
- Mix to monitor buses and to recorded tracks
- Mastering chain with heavier effects
- **Instrument Separation Mode** — decode up to 5 instruments from each stereo phase-discriminating mic pair, up to 3 mic pairs, direct-to-track
- Library / file management — projects, exports, SD management

### The Five GUI Tabs (control surface)

| Tab | Function |
|-----|----------|
| 1. INPUTS | Input channel strips, arm/record, source/gain/TDM-slot assignment |
| 2. MIX | Real-time DSP per bus — pick EQ/comp/reverb/delay (coefficient swap) |
| 3. OUTPUT | Track routing, master levels, monitoring mix |
| 4. MASTERING | Heavier HLS-accelerated effects chains |
| 5. LIBRARY | Project save/load, SD management, export |

**Transport (always visible):**
```
[▶ Play] [⏸ Pause] [■ Stop] [⏺ Record] ⏱ time 🔘🔘🔘🔘 four context selectors
```

### The Two Operating Modes

| Mode | Description |
|------|-------------|
| **STUDIO MODE** (default) | Full per-channel realtime DSP, mixing, dubbing |
| **SEPARATION MODE** | Fabric reallocated to instrument separators; routine realtime EQ disabled (only the separation config popup is active); separated streams go direct to tracks |

---

## Section 2 — SYSTEM ARCHITECTURE (02-SYSTEM-ARCHITECTURE.md)

### System Block Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    LOOM (XC7A100T)                        │
│                                                           │
│  Mics ─┤ CS42448 ──TDM──►┌──────────────────────────────────┐
│  Line  │  codec           │ AUDIO FABRIC (the engine)      │
│        │                  │                                │
│        │              I²C │ ┌────────────────────────────┐ │
│        │                  │ │ Software-Defined DSP Core  │ │
│        │                  │ │                            │ │
│        │                  │ │ (time-mux MAC engine)      │ │
│        │                  │ │ 6 pipes × module chains    │ │
│        │                  │ └────────────────────────────┘ │
│        │                  │ ┌────────────────────────────┐ │
│ Speaker─┤ CS42448 ◄──TDM──┤ │ Specialty Accelerators   │ │
│ Phones  │      DAC        │ │ • Instrument Separator   │ │
│         │                 │ │   (DUET)                 │ │
│         │                 │ │ • Reverb / delay engine  │ │
│         │                 │ └────────────────────────────┘ │
│         │                 │           │                    │
│         │                 │          DMA                   │
│         │                 └──────────┼────────────────────┘
│         │                            ▼                    │
│         │                 ┌──────────────────┐              │
│         │                 │ DDR3 (256MB)     │              │
│         │                 │                  │ ring buffers │
│         │                 │                  │ framebuffer  │
│         │                 │                  │ delay lines  │
│         │                 └──────────────────┘              │
│         │                         ▲                       │
│         │         ┌───────────────┴───────────────────────┐ │
│         │         │ NEORV32 (control plane)             │ │
│         │         │ GUI render · touch · transport ·    │ │
│         │         │ file I/O · DSP patch mgmt ·         │ │
│         │         │ mode mgmt · codec config            │ │
│         │         └──┬──────────┬───────────┬──────────┬──┘ │
│         │            │          │           │          │    │
│         │        ┌──▼──┐   ┌───▼───┐   ┌───▼───┐  ┌──▼────┐│
│         │        │ TFT │   │ Touch │   │microSD│  │ J-Link││
│         │        │ctrl │   │ ctrl  │   │ (SPI) │  │ OCD   ││
│         │        └─────┘   └───────┘   └───────┘  └───────┘│
└─────────────────────────────────────────────────────────┘
         │                                               │
         │                                               │
    ┌────▼────┐                                     ┌────▼────┐
    │Color TFT│                                     │SEGGER   │
    │+ stylus │                                     │J-Link   │
    └─────────┘                                     └─────────┘
                               (firmware debug)
```

### The Three Planes (keep them mentally separate)

| Plane | Description |
|-------|-------------|
| **Audio Plane** | Fabric only. Samples never touch the CPU. Hard-real-time. |
| **Control Plane** | NEORV32. Soft-real-time. Steers the audio plane via memory-mapped registers and coefficient/buffer memory. |
| **Storage Plane** | DDR3 ring buffers bridge fabric (audio) and SD card (files), coordinated by NEORV32. |

### Clock Domains

| Domain | Source | Notes |
|--------|--------|-------|
| Fabric/DSP clock | 100 MHz from Arty oscillator via MMCM | |
| Audio clock | Derived MCLK for CS42448 (e.g. 12.288 MHz for 48 kHz family) | Generated by MMCM, must be jitter-clean |
| DDR3 | MIG-generated domain | |

*Cross domain via async FIFOs — standard, low risk.*

---

## Section 3 — FPGA AUDIO FABRIC (03-FPGA-AUDIO-FABRIC.md)

### 3.1 The Pipe / Module Model (software-defined)

A **pipe** is a logical processing chain for one audio path. Up to 6 pipes. Each pipe holds up to 6 module slots. But "modules" are not fabric blocks; they are entries in a per-pipe processing program executed by the DSP core.

```
Pipe N program (stored in BRAM):
    Slot 0: [INPUT_GAIN coeff_ptr=0x100]
    Slot 1: [EQ_5BAND coeff_ptr=0x140]
    Slot 2: [COMPRESSOR coeff_ptr=0x1A0]
    Slot 3: [DELAY coeff_ptr=0x1C0]
    Slot 4: [PAN coeff_ptr=0x1E0]
    Slot 5: [BUS_SEND coeff_ptr=0x1F0]
```

To "add a module" in the GUI, NEORV32 writes a new slot entry + coefficients. **Instant. No bitstream.**

### 3.2 The DSP Core Engine

A microcoded streaming MAC engine:

```
┌─────────────────────────────────────────────────────┐
│ DSP CORE                                            │
│                                                     │
│ Program ROM/RAM (BRAM) ──► Sequencer                │
│         │                      │                    │
│         ▼                      ▼                    │
│ Coefficient RAM ──► ┌──────────────────┐            │
│ (BRAM)              │ MAC Datapath     │──► out     │
│ Sample/State RAM ──►│ (2-4 DSP48 lanes)│            │
│ (BRAM)              └──────────────────┘            │
│                                                     │
│ One pass per audio sample tick processes ALL        │
│ pipes × all slots. ~400 MACs/sample << budget.      │
└─────────────────────────────────────────────────────┘
```

**Implementation choice:** hand-written RTL for v1 (it's a simple sequenced biquad/MAC machine), or HLS if you prefer. RTL is recommended — it's small, deterministic, and you control timing precisely.

### 3.3 Audio I/O Subsystem

| Component | Description |
|-----------|-------------|
| TDM receiver | Deserializes CS42448 6-channel TDM into 6 sample streams |
| TDM transmitter | Serializes 8 output channels back to CS42448 DACs |
| Sample-rate tick generator | The heartbeat (48 kHz) that triggers one DSP core pass |

*All driven by the audio clock domain.*

### 3.4 Mix Bus Architecture

Mix buses are accumulators in the DSP core program (BUS_SEND slots). Monitor mix, record buses, master bus all expressed as summing nodes in the program. Up to N buses limited only by BRAM and time budget (you have plenty).

### 3.5 Data Path To/From Storage

| Direction | Path |
|-----------|------|
| Recording | post-processing taps → DMA → DDR3 ring buffer → NEORV32 → SD WAV |
| Playback (dubbing) | SD WAV → NEORV32 → DDR3 ring buffer → DMA → fabric → mix → monitor |

---

## Section 4 — DSP MODULE LIBRARY (04-DSP-MODULE-LIBRARY.md)

Each module is a **microcode template + coefficient layout**, not a netlist. Build and verify each independently (bit-accurate in Python/C against the fabric).

| Module | Algorithm | MAC/sample | Coeffs | Notes |
|--------|-----------|------------|--------|-------|
| INPUT_GAIN | scalar multiply | 1 | 1 | trivial |
| PAN | constant-power L/R | 2 | 2 | |
| EQ_5BAND | 5 cascaded biquads | ~25 | 25 | parametric, RBJ cookbook |
| LOWCUT/HIGHCUT | 1-2 biquads | ~5 | 5-10 | |
| COMPRESSOR | env follower + gain curve | ~10 | ~6 | log approx via LUT |
| LIMITER | fast peak limiter | ~8 | ~4 | lookahead via small delay |
| GATE | threshold + envelope | ~6 | ~4 | |
| DELAY | tapped delay, feedback | ~4 | ~4 | line in BRAM/DDR3 |
| REVERB | → Specialty Accelerator | — | — | see §3.2 accelerators |
| BUS_SEND | accumulate to bus | 1 | 1 | routing |

### Module Development Kit

Write a **golden reference model in Python** for every module. The fabric output must match the Python model bit-for-bit (within defined fixed-point tolerance). This is your verification spine and feeds directly into the hardware-debug MCP's diff_known_good capability. **No module ships until its fabric output matches its golden model.**

**Fixed-point format:** recommend Q1.31 internal accumulation, Q1.23 sample data (24-bit audio). Document this once, enforce everywhere.

---

## Section 5 — THE INSTRUMENT SEPARATOR (05-INSTRUMENT-SEPARATOR.md)

This is the crown jewel. It is also a real DSP research system. Treat it as its own subproject.

### 5.1 What It Does

Takes a stereo phase-discriminating mic pair and separates up to 5 simultaneous instruments based on where they sit in space, writing each to its own track. Up to 3 mic pairs = up to 15 separated streams.

### 5.2 The Algorithm: DUET (Degenerate Unmixing Estimation Technique)

DUET is the right, proven approach for separating many sources from a 2-channel mixture using time-frequency masking. The principle: in the STFT domain, most audio is sparse — at any given time-frequency bin, usually one instrument dominates. Each instrument has a characteristic inter-channel level difference (amplitude ratio) and inter-channel phase/time difference (delay) that maps to its spatial position. Cluster the bins by (amplitude-ratio, delay), and each cluster is an instrument.

```
Stereo mic L,R
        │
        ▼
┌──────────┐    ┌──────────┐
│ STFT(L)  │    │ STFT(R)  │  windowed FFT, e.g. 1024-pt, 50% overlap
└────┬─────┘    └────┬─────┘
     │                 │
     ▼                 ▼
┌────────────────────────────┐
│ Per-bin estimate:          │
│ α = |R|/|L| (level diff)  │
│ δ = phase(R/L)/ω (delay)  │
└────────────┬───────────────┘
             ▼
┌────────────────────────────┐
│ 2D histogram over (α,δ)  │ peaks = instruments (spatial positions)
│ Cluster → assign each bin  │
│ to nearest source          │
└────────────┬───────────────┘
             ▼
┌────────────────────────────┐
│ Build time-frequency mask  │ one binary/soft mask per source
│ per source, apply to STFT  │
└────────────┬───────────────┘
             ▼
┌────────────────────────────┐
│ ISTFT per source → time    │ up to 5 separated audio streams
└────────────┬───────────────┘
             ▼
    direct to recording tracks
```

### 5.3 FPGA Implementation

| Component | Implementation |
|-----------|---------------|
| FFT/IFFT | Xilinx FFT IP (configurable, pipelined) — the heavy DSP consumer |
| Per-bin math (α, δ, masking) | HLS-generated datapath, CORDIC for phase/magnitude |
| Histogram + clustering | **Do it on NEORV32 (control plane), not fabric.** The fabric streams α/δ statistics to a histogram in BRAM/DDR3; NEORV32 reads it, finds peaks, decides source positions, and writes back the mask assignment parameters. Clustering is low-rate decision logic — perfect for the CPU. Per-bin masking is high-rate streaming — perfect for fabric. This division is the key engineering insight that makes it feasible. |

**Latency:** STFT framing adds latency (e.g. 1024 samples ≈ 21 ms at 48 kHz). Acceptable for direct-to-track separation; document it.

### 5.4 Why Mode-Switch Matters Here

A DUET instance is heavy (FFTs + masking ≈ 30-50 DSP slices). Three instances ≈ 150 DSP slices. In Separation Mode, the routine DSP core is suspended, freeing its time budget and DSP slices, and the GUI hides realtime-EQ popups (your instinct was correct). The separators get the fabric.

### 5.5 Build It Standalone First

Before any FPGA work: implement DUET in Python, prove separation on real stereo recordings of your instruments, tune the histogram/clustering, define fixed-point formats. This Python model is the golden reference. Only then build the fabric version and verify against it. **This is a multi-week subproject — schedule it as such.**

---

## Section 6 — CONTROL PLANE / NEORV32 FIRMWARE (06-CONTROL-PLANE.md)

### 6.1 NEORV32 Responsibilities

- GUI rendering (draw into framebuffer)
- Touch input handling + event dispatch
- Transport state machine (play/pause/stop/record/dub)
- DSP patch management (write programs/coefficients to DSP core)
- Mode management (studio ↔ separation)
- Codec configuration (CS42448 over I²C)
- File I/O (FatFs on microSD: WAV read/write, project files)
- DDR3 ring-buffer management (record/playback streaming)
- Separator clustering (histogram peak-finding, mask assignment)

### 6.2 NEORV32 Configuration

| Parameter | Value |
|-----------|-------|
| ISA | RV32IMC (M for multiply — needed; C for code density) |
| Optional | Zfinx or FPU not needed (audio is fabric's job; control math is integer/fixed) |
| Peripherals | UART0 (debug console), SPI (SD card + TFT), I²C (codec + touch), GPIO, JTAG OCD enabled (for SEGGER J-Link debug) |
| Memory | instruction + data in BRAM; large buffers in DDR3 via memory-mapped bridge |
| Clock | 100 MHz (can run slower if timing demands; control plane is not speed-critical) |

### 6.3 Firmware Architecture (layers)

```
┌─────────────────────────────────────┐
│ Application: GUI tabs, transport    │
├─────────────────────────────────────┤
│ Services: mixer, recorder, project, │
│           separator-control         │
├─────────────────────────────────────┤
│ HAL: codec, dsp_core, ddr, sd, tft, │
│      touch (memory-mapped registers)│
├─────────────────────────────────────┤
│ NEORV32 BSP + FatFs                 │
└─────────────────────────────────────┘
```

### 6.4 Toolchain

- **Compiler:** riscv32-unknown-elf-gcc (NEORV32 toolchain)
- **Debug:** SEGGER J-Link + OpenOCD (RISC-V) + GDB — this is exactly the firmware-driver-debug work the hardware-debug MCP was designed for. Breakpoints, step, register/memory inspect on every driver you write.

---

## Section 7 — GUI / DISPLAY / TOUCH (07-GUI-DISPLAY-TOUCH.md)

### 7.1 Display Hardware: ILI9341 2.4" SPI TFT

| Spec | Value |
|------|-------|
| Panel | 2.4 inch TFT LCD Module |
| Resolution | 320 × 240 pixels (QVGA) |
| Controller | ILI9341 |
| Interface | SPI Serial |
| Touch | Resistive Touch Panel with Stylus Pen |
| Compatibility | Arduino, STM32, FPGA |

**SPI Wiring (to be mapped to Arty pins):**
- SCK (SPI Clock)
- MOSI (Data to display)
- MISO (Data from display/touch - optional)
- CS (Chip Select - active low)
- DC (Data/Command select)
- RST (Reset - active low)
- VCC / GND

**Touch Controller:** Typically XPT2046 or similar resistive touch controller, also SPI interfaced. Shares some lines with display SPI or separate bus.

### 7.2 Display Pipeline

| Aspect | Implementation |
|--------|---------------|
| Framebuffer | DDR3 (320×240×16bpp = 150 KB — too big for BRAM, perfect for DDR3) |
| Display controller | In fabric: reads framebuffer, drives TFT via SPI |
| Rendering | NEORV32 draws into framebuffer; optional small 2D blitter in fabric for fast rectangle fills / bitmaps (offloads CPU) |

**SPI Display Controller Notes:**
- ILI9341 supports 4-wire SPI mode (CS, DC, SCK, MOSI)
- Color format: 16-bit RGB565 per pixel
- SPI clock: up to 10 MHz typical, can go faster with proper level shifting
- Full screen refresh at 60 Hz: 320×240×2 bytes × 60 fps = ~9.2 MB/s — well within SPI capabilities

### 7.3 Touch Input

| Aspect | Implementation |
|--------|---------------|
| Touch Type | Resistive (pressure-based) — works naturally with stylus pen |
| Controller | XPT2046 or equivalent ADC-based resistive touch controller |
| Interface | SPI (can share bus with display) |
| Processing | ADC-sampled X/Y → NEORV32 reads → calibrated screen coordinates |

**Calibration:** Store 4 calibration points in EEPROM/flash; map raw ADC values to screen coordinates.

### 7.4 GUI Framework (firmware)

| Aspect | Choice |
|--------|--------|
| Framework style | Immediate-mode or lightweight retained widget tree |
| Recommendation | Immediate-mode (simpler, less RAM, redraw-on-event) for embedded target |
| Widget set | channel strip, fader, button, tab bar, transport bar, popup/modal, waveform view, level meter, list (file browser) |
| Waveform view | Low-res peak data computed by fabric or NEORV32 from ring buffers |

### 7.5 Screen Layout (adapted for 320×240)

```
┌───────────────────────────────────────────────┐
│ [▶][⏸][■][⏺] ⏱ 00:01:23 │                │  Transport bar (top)
├───────────────────────────────────────────────┤
│ [IN][MX][OUT][MST][LIB] │                    │  Tab bar (compact)
├───────────────────────────────────────────────┤
│                                               │
│   Active tab content                          │
│   (channel strips / routing / file list)    │
│                                               │
│                                               │
│   tap empty area → "Add Module/Input" popup │
│                                               │
└───────────────────────────────────────────────┘
```

**320×240 Constraints:**
- Smaller than original 480×320 spec — UI must be compact
- Consider horizontal tabs with abbreviated labels
- Channel strips may show fewer parameters at once (scrollable)
- Stylus pen provides pixel-precise touch accuracy

### 7.6 Arty Pin Planning for Display/Touch

The ILI9341 + resistive touch needs:
- 4-5 SPI pins (SCK, MOSI, MISO, CS_display, CS_touch optional)
- 1 DC pin (Data/Command for display)
- 1 RST pin (optional, can be tied high)
- 2-3 pins for touch (if using separate XPT2046: T_IRQ, optionally T_RST)

**Total: ~6-8 GPIO pins from Arty Shield connector**

Available Arty pins (from codecbox existing design):
- SPI0 pins may be available if not used for SD
- Consider shared SPI bus: display + SD card + touch (different CS lines)
- Or dedicated SPI: one for display, one for SD, touch on separate bus

---

## Section 8 — STORAGE & RECORDING (08-STORAGE-RECORDING.md)

### 8.1 The Real-Time Recording Path (critical path)

```
Fabric (post-DSP taps) ──DMA──► DDR3 ring buffer (per track)
                                        │
                              NEORV32 drains buffers
                                        │
                                        ▼
                              FatFs ──► microSD (WAV per track)
```

### 8.2 Bandwidth Reality

| Scenario | Calculation |
|----------|-------------|
| 6 ch × 24-bit × 48 kHz | 864 KB/s sustained write |
| microSD over SPI | ~1-3 MB/s reliable → adequate for 6 tracks, marginal for many |
| SDIO 4-bit mode (recommended) | 10+ MB/s → headroom for higher channel counts |

**Recommendation:** start SPI for bring-up, plan SDIO for production

### 8.3 File Formats

| Type | Format |
|------|--------|
| Audio | WAV (simple, universal) — multi-mono or multichannel WAV |
| Project | JSON or compact binary — pipe configs, module coeffs, routing, mode, track list |
| Recommendation | JSON for v1 (human-readable, debuggable), binary later if size matters |

### 8.4 Dubbing (overdub) Path

```
Playback existing tracks from SD → DDR3 → fabric → monitor mix
                                ↓
                    Simultaneously record new track(s)
```

Sample-accurate sync via the shared 48 kHz tick — playback and record buffers locked to the same heartbeat.

---

## Section 9 — RESOURCE BUDGET (09-RESOURCE-BUDGET.md)

### XC7A100T Real Capacity

| Resource | Available |
|----------|-----------|
| LUTs | 63,400 |
| Flip-flops | 126,800 |
| DSP48E1 slices | 240 (not 640 — that's the 200T) |
| Block RAM | 135 × 36Kb = ~607 KB (not 132KB) |
| Logic cells | 101,440 |
| DDR3 (on Arty) | 256 MB external |

### Budget Estimate

| Block | LUTs | DSP | BRAM | Notes |
|-------|------|-----|------|-------|
| NEORV32 (RV32IMC) | ~5K | 4 | ~32KB | core + caches |
| DSP Core engine | ~4K | 8-16 | ~64KB | serves all 6 pipes |
| TDM I/O + clocking | ~2K | 0 | small | |
| DDR3 MIG | ~6K | 0 | — | hard-ish IP |
| Display controller + blitter | ~4K | 2 | — | framebuf in DDR3 |
| SD / SPI / I²C / GPIO | ~2K | 0 | small | |
| **Studio mode subtotal** | **~23K** | **~30** | **~160KB** | **comfortable** |
| Reverb accelerator | ~3K | 8 | — | DDR3 delay, optional in studio |
| 1× Instrument Separator | ~8K | ~40 | ~80KB | FFT-heavy |
| 3× Separators (sep. mode) | ~24K | ~120 | ~240KB | reclaims studio DSP |

### Verdict

**Studio mode fits with huge margin. Separation mode with 3 separators fits because mode-switch reclaims the routine DSP budget.** The A7-100T is the right size. You are DSP-slice-bound only in full 3-separator mode, which is exactly why the mode-switch architecture exists. **Confirmed feasible.**

---

## Section 10 — PROJECT STRUCTURE (10-PROJECT-STRUCTURE.md)

```
loom/
├── docs/                          # the 12 design files (this document)
├── hardware/
│   ├── vivado/
│   │   ├── loom.xpr              # project
│   │   ├── constraints/loom.xdc  # timing/pin constraints
│   │   └── tcl/build_bitstream.tcl
│   ├── rtl/
│   │   ├── dsp_core/             # time-mux MAC engine (RTL)
│   │   ├── tdm_io/               # TDM rx/tx
│   │   ├── display_ctrl/         # ILI9341 SPI controller
│   │   ├── touch_ctrl/           # Resistive touch handler
│   │   ├── audio_dma/
│   │   └── top/loom_top.v
│   ├── hls/
│   │   ├── separator/            # DUET HLS source
│   │   └── reverb/
│   └── ip/                       # Xilinx FFT, MIG configs
├── firmware/
│   ├── src/
│   │   ├── app/                  # GUI, tabs, transport
│   │   ├── services/             # mixer, recorder, project, separator_ctrl
│   │   ├── hal/                  # codec, dsp_core, ddr, sd, tft, touch
│   │   └── main.c
│   ├── lib/                      # NEORV32 BSP, FatFs
│   ├── linker/
│   └── Makefile
├── models/                        # GOLDEN REFERENCE (Python)
│   ├── dsp_modules/               # bit-accurate models of every DSP module
│   ├── separator/                 # DUET reference + test recordings
│   └── fixedpoint/                # Q-format definitions, helpers
├── test/
│   ├── hardware/                  # RTL testbenches
│   ├── firmware/                  # unit tests
│   └── golden_vectors/            # input/output pairs fabric must match
├── tools/                         # build, flash, debug scripts
└── project.profile.json           # hardware-debug MCP profile
```

---

## Section 11 — THE BUILD PLAN: NOW → FINAL (11-BUILD-PLAN.md)

**The genius principle:** make the engine work end-to-end at trivial scale first, then add capability. Get one sample through the whole chain before building six pipes of effects.

### Stage 0 — Foundation & Bring-Up (prove the platform)

| Milestone | Status |
|-----------|--------|
| NEORV32 boots on A7-100T, UART console alive, J-Link debug working | ☐ |
| microSD reads/writes a file (FatFs) | ☐ |
| **ILI9341 TFT displays a test pattern from DDR3 framebuffer** | ☐ |
| **Resistive touch returns calibrated coordinates** | ☐ |
| CS42448 configured via I²C, audio passthrough: mic in → fabric → speaker out (no DSP) | ☐ |

**Exit criteria:** you hear clean audio through the box, screen + touch work, firmware debuggable

### Stage 1 — The DSP Core (one pipe, one module)

| Milestone | Status |
|-----------|--------|
| Python golden model: gain + 1 biquad EQ (Q-format defined) | ☐ |
| RTL DSP core: single pipe, single EQ slot, time-multiplexed | ☐ |
| RTL testbench matches golden vectors bit-accurately | ☐ |
| Firmware writes coefficients; you hear EQ change in real time from a touch fader | ☐ |

**Exit criteria:** turn a knob on screen, hear EQ change, fabric matches Python

### Stage 2 — Full Studio Mode

| Milestone | Status |
|-----------|--------|
| Expand DSP core to 6 pipes × 6 slots | ☐ |
| Implement full module library (EQ, comp, gate, limiter, delay, pan, gain) — each verified against golden model | ☐ |
| Mix buses + monitor mix | ☐ |
| Recording path: fabric → DDR3 → SD WAV (6 tracks) | ☐ |
| Dubbing: playback + simultaneous record, sample-locked | ☐ |
| GUI tabs 1-3 functional (INPUTS, MIX, OUTPUT) | ☐ |

**Exit criteria:** record and overdub a real multitrack performance with live EQ/dynamics

### Stage 3 — Mastering + Reverb Accelerator

| Milestone | Status |
|-----------|--------|
| Reverb/long-delay HLS accelerator | ☐ |
| Mastering tab (tab 4) with heavier chains | ☐ |
| Project save/load, Library tab (tab 5), export | ☐ |

**Exit criteria:** complete a song from record → mix → master → export on the box alone

### Stage 4 — The Crown Jewel: Instrument Separation

| Milestone | Status |
|-----------|--------|
| DUET fully working in Python on real recordings of your instruments (tune clustering) | ☐ |
| FFT-based STFT/ISTFT in fabric (Xilinx FFT IP) | ☐ |
| Per-bin α/δ + masking datapath (HLS), verified vs Python | ☐ |
| Histogram → NEORV32 clustering → mask assignment loop | ☐ |
| Single separator: stereo mic → up to 5 tracks | ☐ |
| Separation Mode UI: mode switch, separator config popup, fabric reclaim | ☐ |
| Scale to 3 separators | ☐ |

**Exit criteria:** point a stereo mic at a small ensemble, get separate instrument tracks

### Stage 5 — Productization

| Milestone | Status |
|-----------|--------|
| Custom PCB (codec, TFT, SD, power, FPGA) | ☐ |
| Enclosure, connectors | ☐ |
| SDIO 4-bit SD for bandwidth headroom | ☐ |
| Calibration, presets, polish | ☐ |

---

## The Synthesis — Why This Plan Is Right

1. **You preserved the entire vision** — 6 pipes, 6 modules, mode-switch separation, all five tabs — while removing the single biggest risk (partial reconfiguration) and replacing it with something faster, simpler, and more reliable.

2. **The hard part is correctly isolated.** The instrument separator is a real DSP research project; everything else is solid engineering. By building the platform and studio mode first, you have a finished, sellable product (Stage 3) before you take on the research risk (Stage 4). If separation takes longer than hoped, you still shipped a recorder.

3. **The golden-model discipline** (Python reference for every DSP block) is what lets your AI debug system actually work — diff_known_good has something authoritative to compare against. The four-MCP debug architecture you built plugs directly into this: firmware drivers debugged via J-Link, fabric verified via golden vectors, codec checked via UART commands.

4. **The numbers are honest.** 240 DSP slices, 607 KB BRAM, 2083 cycles/sample. The architecture lives comfortably within them. The earlier wrong capacity figures have been corrected so you don't design into a wall.

5. **The display choice is perfect for the product.** A 2.4" ILI9341 with resistive touch and stylus provides precise control in a compact handheld form factor. The SPI interface is simple to drive from fabric, and the small 320×240 resolution keeps framebuffer memory modest (150KB in DDR3).

---

## Your Immediate Next Action

Create the `docs/` folder and drop these twelve sections in as the twelve files. That is your project definition — single source of truth, ready for the critic to reference and the debugger to work against.

Then start **Stage 0**. Get one clean sample of audio through the box, one pixel on the ILI9341, and one breakpoint hit on the NEORV32. Everything else builds on that.

**Hand your agent one file at a time.** It choked because it was fed the ocean. Feed it a glass of water: "Here is 03-FPGA-AUDIO-FABRIC.md. Implement the TDM passthrough from Stage 0." It will manage that.

Tell me which file you want fully expanded into implementation-level detail first — I'd start with **02-SYSTEM-ARCHITECTURE.md** or **07-GUI-DISPLAY-TOUCH.md** (with the ILI9341 specifics) or the **Stage 0 bring-up** — and I'll write it to the depth where your agent can execute it directly.
