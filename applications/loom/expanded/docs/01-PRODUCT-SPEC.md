# OPUS MAXIMUS / LOOM — Section 1: PRODUCT SPECIFICATION

**Document ID:** OPUS-01-PRODUCT-SPEC  
**Version:** 1.0 — Implementation Ready  
**Date:** 2026-06-21  
**Author:** GodBot 🜂 for codecbox  
**Target:** Arty A7-100T (XC7A100T-1CSG324C)

---

## 1.1 Physical Product Specification

### 1.1.1 Envelope

| Parameter | Specification |
|-----------|-------------|
| Form Factor | Handheld to small-pedal size |
| Target Dimensions | 120mm × 80mm × 30mm (dev), 100mm × 70mm × 25mm (production) |
| Weight | < 300g (production target) |
| Enclosure | Aluminum or ruggedized plastic |
| Mounting | Rubber feet, optional 1/4-20 thread for camera mounts |

### 1.1.2 Display Subsystem

| Parameter | Specification |
|-----------|-------------|
| Panel | 2.4 inch TFT LCD Module |
| Resolution | 320 × 240 pixels (QVGA) |
| Color Depth | 16-bit RGB565 (65,536 colors) |
| Controller | ILI9341 |
| Interface | SPI Serial, 4-wire mode |
| SPI Clock | Up to 10 MHz (configurable, higher with level shifting) |
| Touch Type | Resistive |
| Touch Controller | XPT2046 or equivalent |
| Touch Interface | SPI (can share with display) |
| Input Method | Stylus pen (pressure-based, precise) |
| Viewing Angle | ~160° (typical for TFT) |
| Backlight | LED, controllable via GPIO/PWM |

**SPI Pin Requirements:**
```
Display SPI:
  - SCK  (SPI Clock)
  - MOSI (Data to display)
  - MISO (Data from display - optional for status reads)
  - CS   (Chip Select, active low)
  - DC   (Data/Command select)
  - RST  (Reset, active low - can be tied to system reset)

Touch SPI:
  - SCK  (shared or separate)
  - MOSI (shared or separate)
  - MISO (touch data out)
  - CS   (separate from display CS)
  - IRQ  (optional - touch interrupt, or polled)
```

### 1.1.3 Audio Interface (CS42448 Codec)

| Parameter | Specification |
|-----------|-------------|
| ADC Inputs | 6 channels (via TDM) |
| DAC Outputs | 8 channels (via TDM) |
| Resolution | 24-bit |
| Sample Rates | 44.1kHz, 48kHz, 96kHz (48kHz baseline) |
| Interface | TDM (Time Division Multiplexing), I²C control |
| MCLK Options | 11.2896MHz (44.1k), 12.288MHz (48k), 24.576MHz (96k) |
| Control | I²C address 0x48 |

### 1.1.4 Physical Connectors

| Connector | Type | Function |
|-----------|------|----------|
| INPUT 1-3 | Combo XLR/TRS | Mic/line inputs (balanced) |
| INPUT 4-6 | TRS | Line inputs (stereo pairs = 3+4, 5+6) |
| OUTPUT 1-2 | TRS | Main stereo output |
| OUTPUT 3-8 | TRS | Monitor/aux outputs (4 additional) |
| HEADPHONES | 1/4" TRS | Stereo headphone with volume |
| SD CARD | MicroSD slot | Storage, push-push or push-pull |
| USB-C | USB-C port | Power + data (charging + firmware update) |
| DEBUG | 2×5 0.1" header | JTAG for SEGGER J-Link |

### 1.1.5 Power

| Parameter | Specification |
|-----------|-------------|
| Input | USB-C PD (5V/3A, 9V/2A) or 5.5mm barrel (5-12V) |
| Battery | 2S Li-Ion (7.4V nominal), 3000mAh target |
| Battery Life | 6 hours continuous recording |
| Charging | USB-C PD, ~2 hours full charge |
| Power Consumption | ~2W typical, ~4W peak |

---

## 1.2 Core Capabilities

### 1.2.1 Recording

| Feature | Specification |
|---------|---------------|
| Simultaneous Recording | Up to 6 channels |
| Format | 24-bit PCM WAV |
| Sample Rate | 48kHz baseline, 96kHz optional |
| Storage | MicroSD (FAT32/exFAT, up to 1TB cards) |
| Track Limit | Limited by SD card space, not arbitrary limit |
| Bitrate | 6ch × 24-bit × 48kHz = 6.912 Mbps = 864 KB/s |
| Recording Time | ~80 hours on 256GB card (6ch) |

### 1.2.2 Overdubbing (Dub Mode)

| Feature | Specification |
|---------|---------------|
| Playback Tracks | Up to 8 channels from SD (previous takes) |
| Record Tracks | Up to 6 new channels simultaneously |
| Sync | Sample-accurate via shared 48kHz clock |
| Monitor Mix | Live mix of playback + input with latency < 5ms |

### 1.2.3 Real-Time DSP (Per Channel)

| Effect | Implementation | Notes |
|--------|----------------|-------|
| Input Gain | Software-defined DSP | -∞ to +20dB |
| Pan | Constant-power law | L/R placement in stereo field |
| EQ | 5-band parametric | Low/High shelf + 3x peaking |
| Compressor | RMS detector + gain reduction | Threshold, ratio, attack, release |
| Gate | Threshold + hysteresis | For noise reduction |
| Limiter | Peak limiter | True peak, lookahead |
| Delay | Short delay line | Up to 500ms, with feedback |

### 1.2.4 Mastering Chain

| Feature | Specification |
|---------|---------------|
| Master EQ | 4-band parametric |
| Master Compressor | Multi-band capable |
| Master Limiter | Brickwall, -0.1dBFS |
| Reverb | Convolution reverb (HLS accelerator) |
| Export | 16/24-bit, 44.1/48/96kHz WAV |

---

## 1.3 GUI Structure — The Five Tabs

### 1.3.1 Tab 1: INPUTS

**Purpose:** Configure input sources and arm tracks for recording

**Screen Elements:**
```
┌─────────────────────────────────────────────────┐
│ [IN] [MX] [OUT] [MST] [LIB] │                │  Tab bar
├─────────────────────────────────────────────────┤
│ Ch1 │ Ch2 │ Ch3 │ Ch4 │ Ch5 │ Ch6 │          │  Channel strips (horizontal scroll)
├─────┴─────┴─────┴─────┴─────┴─────┴──────────┤
│ [ARM]  [INPUT: TDM Slot 1]  [GAIN: +12dB]   │  Channel 1 detail
│ [SRC: MIC]  [48V: ON]  [PAD: OFF]          │
├─────────────────────────────────────────────────┤
│                 WAVEFORM PREVIEW              │
└─────────────────────────────────────────────────┘
```

**Controls per Channel:**
- Arm/Disarm record button (red circle when armed)
- Input source select (TDM slot, analog input)
- Gain fader (-∞ to +60dB)
- 48V phantom power toggle (XLR inputs only)
- Pad toggle (-20dB)
- Source type (Mic/Line/Inst)
- Real-time level meter

### 1.3.2 Tab 2: MIX

**Purpose:** Configure DSP modules per channel

**Screen Elements:**
```
┌─────────────────────────────────────────────────┐
│ [IN] [MX] [OUT] [MST] [LIB] │                │
├─────────────────────────────────────────────────┤
│ Channel 1: [GAIN] [EQ] [COMP] [GATE] [DELAY] │  Module slots
├─────────────────────────────────────────────────┤
│                                                 │
│   ┌─────────────────────────────┐             │
│   │ EQ: LOW  MID1  MID2  MID3  HIGH        │  Active module editor
│   │ F:  80Hz 500Hz 2kHz  5kHz  12kHz       │
│   │ G:  +3dB  -2dB  +4dB  -1dB  +2dB       │
│   │ Q:  0.7   1.2   2.0   1.5   0.8        │
│   └─────────────────────────────┘             │
│                                                 │
│   [+ Add Module] [Bypass All] [Copy to Ch2]   │
└─────────────────────────────────────────────────┘
```

**Module Chain:** Up to 6 modules per channel, user-selectable order

**Available Modules:**
1. INPUT_GAIN — initial gain staging
2. EQ_5BAND — parametric EQ
3. COMPRESSOR — dynamics
4. GATE — noise gate
5. DELAY — short delay
6. PAN — stereo positioning
7. BUS_SEND — route to mix bus

### 1.3.3 Tab 3: OUTPUT

**Purpose:** Configure routing and monitor mix

**Screen Elements:**
```
┌─────────────────────────────────────────────────┐
│ [IN] [MX] [OUT] [MST] [LIB] │                │
├─────────────────────────────────────────────────┤
│ ROUTING MATRIX                                  │
│                                                 │
│        OUT1  OUT2  OUT3  OUT4  OUT5  OUT6  OUT7  OUT8
│ Ch1    [X]   [ ]   [ ]   [ ]   [ ]   [ ]   [ ]   [ ]
│ Ch2    [ ]   [X]   [ ]   [ ]   [ ]   [ ]   [ ]   [ ]
│ Ch3    [X]   [X]   [ ]   [ ]   [ ]   [ ]   [ ]   [ ]
│ ...                                            │
│                                                 │
│ MONITOR MIX: [Main] [Cue] [Direct]              │
│ MONITOR LVL:  [────────────●────]  -12dB       │
└─────────────────────────────────────────────────┘
```

**Routing Options:**
- Direct: Input → Output (passthrough)
- Mix: Channel → Master → Output
- Cue: Pre-fader monitor for performers

### 1.3.4 Tab 4: MASTERING

**Purpose:** Final polish and export

**Screen Elements:**
```
┌─────────────────────────────────────────────────┐
│ [IN] [MX] [OUT] [MST] [LIB] │                │
├─────────────────────────────────────────────────┤
│ MASTER CHAIN:                                   │
│                                                 │
│ [1] [EQ] [COMP] [REVERB] [LIMITER]             │
│                                                 │
│ REVERB: PLATE  [SIZE:●───────]  [MIX:───●──] │
│                                                 │
│ EXPORT:                                         │
│ Format: [24-bit WAV ▼]  Sample: [48kHz ▼]     │
│ [BOUNCE TO SD]  [BOUNCE ALL]                  │
└─────────────────────────────────────────────────┘
```

### 1.3.5 Tab 5: LIBRARY

**Purpose:** Project management and file operations

**Screen Elements:**
```
┌─────────────────────────────────────────────────┐
│ [IN] [MX] [OUT] [MST] [LIB] │                │
├─────────────────────────────────────────────────┤
│ PROJECTS:              [+ New] [Import]        │
│ ┌─────────────────────────────────────────────┐│
│ │ ▶ Session_2026_06_21_001    6 tracks     ││
│ │   Session_2026_06_20_004    12 tracks    ││
│ │   Rehearsal_001             4 tracks     ││
│ └─────────────────────────────────────────────┘│
│                                                 │
│ SD CARD: 45GB free / 256GB total               │
│ [Format] [Eject] [Export USB]                 │
└─────────────────────────────────────────────────┘
```

---

## 1.4 Transport Control (Always Visible)

```
┌─────────────────────────────────────────────────┐
│ [←]  [▶/⏸]  [■]  [⏺]  [⏱ 00:01:23.45]  [🔘🔘🔘🔘]│
│Rewind  Play   Stop  Rec      Timecode        Ctx│
└─────────────────────────────────────────────────┘
```

**Context Selectors (🔘):**
- Select which 4 channels the mini-faders control
- Quickly adjust gain/EQ on specific channels without switching tabs

---

## 1.5 Operating Modes

### 1.5.1 STUDIO MODE (Default)

| Aspect | Behavior |
|--------|----------|
| DSP | Full per-channel real-time processing |
| Separation | Disabled |
| GUI | All 5 tabs active |
| Record | Standard multitrack recording |
| Monitor | Post-DSP monitoring |

### 1.5.2 SEPARATION MODE

| Aspect | Behavior |
|--------|----------|
| DSP | Routine EQ disabled; fabric reallocated to separators |
| Separation | DUET algorithm active on up to 3 stereo pairs |
| GUI | Only separation config popup active; other tabs hidden/greyed |
| Record | Separated streams go directly to tracks |
| Monitor | Pre-separation for alignment, post-separation for preview |

**Separation Config Popup:**
```
┌─────────────────────────────────────────┐
│ SEPARATION MODE         [X]            │
├─────────────────────────────────────────┤
│ Mic Pair 1: [TDM 1+2 ▼]               │
│ Sources detected: 4                   │
│ [▶ Preview Separation]                │
│                                         │
│ [START RECORDING → 4 STEMS]            │
└─────────────────────────────────────────┘
```

---

## 1.6 Performance Specifications

| Metric | Target | Minimum |
|--------|--------|---------|
| THD+N | < -80dB | < -70dB |
| Dynamic Range | > 100dB | > 90dB |
| Latency (ADC→DAC) | < 5ms | < 10ms |
| Latency (separation) | < 25ms | < 50ms |
| Frequency Response | 20Hz-20kHz ±0.5dB | ±1dB |
| Crosstalk | < -80dB | < -70dB |
| Clock Jitter | < 1ns RMS | < 5ns RMS |

---

## 1.7 Compliance & Standards

| Standard | Status |
|----------|--------|
| FCC Part 15 Class B | Required for US sale |
| CE Marking | Required for EU sale |
| RoHS 3 | Required for components |
| USB-IF Certification | Recommended for USB-C |
| SD Card Compliance | Required for SD logo |

---

## 1.8 Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-06-21 | GodBot | Initial product spec |
| 1.0 | 2026-06-21 | GodBot | Complete with ILI9341 display, connector pinouts, mode specs |

---

*End of Section 1 — PRODUCT SPECIFICATION*
