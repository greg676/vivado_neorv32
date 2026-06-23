# OPUS MAXIMUS / LOOM — Section 11: BUILD PLAN

**Document ID:** OPUS-11-BUILD-PLAN  
**Version:** 1.0 — Implementation Ready  
**Date:** 2026-06-21  
**Author:** GodBot 🜂 for codecbox

---

## 11.1 Philosophy

**The genius principle:** Make the engine work end-to-end at trivial scale first, then add capability. Get one sample through the whole chain before building six pipes of effects.

Each stage delivers a working checkpoint. If you only complete Stage 2, you still have a functional 6-channel recorder.

---

## 11.2 Stage 0 — Foundation & Bring-Up

**Duration:** 2-3 weeks  
**Goal:** Prove the platform works end-to-end

### 11.2.1 Milestones

| # | Task | Verification | Status |
|---|------|--------------|--------|
| 0.1 | NEORV32 boots, UART console | "Hello World" on serial | ☐ |
| 0.2 | SEGGER J-Link debug working | Breakpoint, single-step | ☐ |
| 0.3 | ILI9341 displays test pattern | Color bars visible | ☐ |
| 0.4 | XPT2046 touch returns coordinates | Touch recognized | ☐ |
| 0.5 | CS42448 I²C configuration | Register readback OK | ☐ |
| 0.6 | Audio passthrough (no DSP) | Clean sine wave through | ☐ |
| 0.7 | DDR3 reads/writes | Memory test passes | ☐ |
| 0.8 | microSD FATFs read/write | File creation OK | ☐ |

### 11.2.2 Deliverables

- `loom_top.v` with basic instantiation
- `hal_display.c` working
- `hal_touch.c` working
- `hal_codec.c` working
- Test pattern generator for display
- Audio passthrough RTL

### 11.2.3 Exit Criteria

> You hear clean audio through the box, screen + touch work, firmware debuggable.

---

## 11.3 Stage 1 — The DSP Core

**Duration:** 3-4 weeks  
**Goal:** Prove the software-defined DSP concept

### 11.3.1 Milestones

| # | Task | Verification | Status |
|---|------|--------------|--------|
| 1.1 | Python golden model: gain | Unit test passes | ☐ |
| 1.2 | Python golden model: 1 biquad | Unit test passes | ☐ |
| 1.3 | RTL DSP core: single pipe | Synthesizes | ☐ |
| 1.4 | RTL testbench vs golden | Bit-accurate match | ☐ |
| 1.5 | Firmware coefficient load | HAL working | ☐ |
| 1.6 | Real-time EQ change from touch | Hear EQ change | ☐ |

### 11.3.2 Deliverables

- `models/dsp_modules/eq.py` golden model
- `hardware/rtl/dsp_core/` with single-pipe implementation
- `test/hardware/dsp_core_tb/` testbench
- `hal_dsp.c` with coefficient loading

### 11.3.3 Exit Criteria

> Turn a knob on screen, hear EQ change, fabric matches Python bit-for-bit.

---

## 11.4 Stage 2 — Full Studio Mode

**Duration:** 4-6 weeks  
**Goal:** Complete multitrack recorder

### 11.4.1 Milestones

| # | Task | Verification | Status |
|---|------|--------------|--------|
| 2.1 | Expand DSP core to 6 pipes × 6 slots | All slots process | ☐ |
| 2.2 | Full module library (EQ, comp, gate, limiter, delay, pan) | Each verified | ☐ |
| 2.3 | Mix bus + monitor mix | Route to headphones | ☐ |
| 2.4 | Recording path: fabric → DDR3 → SD WAV | Recorded file plays | ☐ |
| 2.5 | Dubbing: playback + simultaneous record | Sync locked | ☐ |
| 2.6 | GUI Tab 1: INPUTS | Faders, arm buttons work | ☐ |
| 2.7 | GUI Tab 2: MIX | Module selection, editing | ☐ |
| 2.8 | GUI Tab 3: OUTPUT | Routing matrix | ☐ |

### 11.4.2 Deliverables

- Complete `hardware/rtl/dsp_core/`
- All 7 DSP modules with golden models
- `services/mixer.c` - mixer service
- `services/recorder.c` - recorder service
- `tabs/tab_inputs.c`, `tab_mix.c`, `tab_output.c`

### 11.4.3 Exit Criteria

> Record and overdub a real multitrack performance with live EQ/dynamics.

---

## 11.5 Stage 3 — Mastering + Reverb Accelerator

**Duration:** 3-4 weeks  
**Goal:** Polish and export

### 11.5.1 Milestones

| # | Task | Verification | Status |
|---|------|--------------|--------|
| 3.1 | Reverb HLS accelerator | Golden model match | ☐ |
| 3.2 | Mastering tab (Tab 4) | Chain works | ☐ |
| 3.3 | Project save/load (JSON) | Save/restore state | ☐ |
| 3.4 | Library tab (Tab 5) | File browser works | ☐ |
| 3.5 | WAV export (24-bit, 48kHz) | Exported file valid | ☐ |
| 3.6 | Import/export project | SD card transfer | ☐ |

### 11.5.2 Deliverables

- `hardware/hls/reverb/` HLS source
- `tabs/tab_master.c` - mastering tab
- `tabs/tab_library.c` - library tab
- `services/project.c` - project manager

### 11.5.3 Exit Criteria

> Complete a song from record → mix → master → export on the box alone.

---

## 11.6 Stage 4 — The Crown Jewel: Instrument Separation

**Duration:** 6-8 weeks  
**Goal:** Real-time DUET separation

### 11.6.1 Milestones

| # | Task | Verification | Status |
|---|------|--------------|--------|
| 4.1 | DUET Python on test recordings | Separates 3+ sources | ☐ |
| 4.2 | Fixed-point analysis | Define formats | ☐ |
| 4.3 | FFT IP integration (Xilinx) | Forward/inverse working | ☐ |
| 4.4 | α/δ HLS block | Matches Python | ☐ |
| 4.5 | Histogram + fabric → CPU | Data flows | ☐ |
| 4.6 | CPU clustering | Peak finding works | ☐ |
| 4.7 | Mask application | Reconstructs audio | ☐ |
| 4.8 | Single separator end-to-end | 5 sources separated | ☐ |
| 4.9 | Separation Mode UI | Mode switch works | ☐ |
| 4.10 | Scale to 3 separators | 3 mic pairs processed | ☐ |

### 11.6.2 Deliverables

- `models/separator/duet.py` working reference
- `hardware/hls/separator/` HLS blocks
- `services/separator_ctrl.c` - separation control
- Separation Mode UI

### 11.6.3 Exit Criteria

> Point a stereo mic at a small ensemble, get separate instrument tracks.

---

## 11.7 Stage 5 — Productization

**Duration:** 4-6 weeks  
**Goal:** Make it shippable

### 11.7.1 Milestones

| # | Task | Verification | Status |
|---|------|--------------|--------|
| 5.1 | Custom PCB design | Schematics complete | ☐ |
| 5.2 | PCB layout + fab | Boards received | ☐ |
| 5.3 | Bring-up custom board | Boots, passes tests | ☐ |
| 5.4 | SDIO 4-bit SD implementation | 10+ MB/s write | ☐ |
| 5.5 | Enclosure design | 3D printed prototype | ☐ |
| 5.6 | Calibration procedures | Test fixtures | ☐ |
| 5.7 | Presets (EQ, compression) | Factory settings | ☐ |
| 5.8 | Documentation | User manual | ☐ |

### 11.7.2 Deliverables

- PCB design files (KiCad or Altium)
- Mechanical enclosure CAD
- Calibration test fixtures
- User manual

### 11.7.3 Exit Criteria

> Unit ready for manufacturing.

---

## 11.8 Timeline Summary

```
Stage 0: Foundation      ████░░░░░░░░░░░░░░░░  Weeks 1-3
Stage 1: DSP Core        █████░░░░░░░░░░░░░░░  Weeks 4-7
Stage 2: Studio Mode     ███████░░░░░░░░░░░░░  Weeks 8-13
Stage 3: Mastering       █████░░░░░░░░░░░░░░░  Weeks 14-17
Stage 4: Separation      █████████░░░░░░░░░░░  Weeks 18-25
Stage 5: Productization  ███████░░░░░░░░░░░░░  Weeks 26-31

Total: ~7-8 months for MVP (Stages 0-4)
Total: ~8-9 months for product (all stages)
```

---

## 11.9 Risk Mitigation

| Risk | Stage | Mitigation |
|------|-------|------------|
| DUET doesn't separate well | 4 | Have working Python first, can ship without it |
| SD card too slow | 2 | Plan for SDIO upgrade in Stage 5 |
| FPGA resource shortage | 2 | Mode-switch architecture handles this |
| Touch calibration drift | 0 | Implement auto-recalibration |
| Codec I²C issues | 0 | Use proven PYNQ I²C setup from codecbox |

---

## 11.10 Immediate Next Actions

**This Week:**
1. Create directory structure per Section 10
2. Set up Vivado project with NEORV32
3. Verify J-Link connects to Arty
4. Get UART "Hello World" working

**Next Two Weeks:**
1. Implement ILI9341 test pattern
2. Verify XPT2046 touch reading
3. Confirm CS42448 I²C communication
4. Close Stage 0

---

## 11.11 Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-06-21 | GodBot | Initial build plan |
| 1.0 | 2026-06-21 | GodBot | Complete with milestones, deliverables, timeline, risk mitigation |

---

*End of Section 11 — BUILD PLAN*

---

# END OF OPUS MAXIMUS / LOOM MASTER DESIGN

This completes the twelve-section master architecture document for the LOOM FPGA multitrack recorder with instrument separation.

**Ready for implementation.**

*Document Set Version: 1.0*  
*Total Pages: ~12 sections, ~200 pages equivalent*  
*Status: Implementation-Ready*
