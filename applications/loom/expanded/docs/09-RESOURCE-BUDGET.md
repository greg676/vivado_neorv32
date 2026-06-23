# OPUS MAXIMUS / LOOM — Section 9: RESOURCE BUDGET

**Document ID:** OPUS-09-RESOURCE-BUDGET  
**Version:** 1.0 — Implementation Ready  
**Date:** 2026-06-21  
**Author:** GodBot 🜂 for codecbox

---

## 9.1 Target Device: XC7A100T-1CSG324C

| Resource | Available | Notes |
|----------|-----------|-------|
| **LUTs** | 63,400 | Logic cells |
| **Flip-flops** | 126,800 | Register elements |
| **DSP48E1 slices** | 240 | Multiplier-accumulator units |
| **Block RAM (36Kb)** | 135 | ~607 KB total |
| **Clock tiles** | 6 | MMCM/PLL per tile |
| **I/O pins** | 210 | Single-ended |
| **DDR3** | 256 MB | External (on Arty board) |

---

## 9.2 Resource Budget by Subsystem

### 9.2.1 Core System (Always Present)

| Block | LUTs | FFs | BRAM | DSP48 | Notes |
|-------|------|-----|------|-------|-------|
| NEORV32 (RV32IMC) | 5,000 | 4,000 | 8 | 4 | Core + caches |
| TDM RX | 200 | 300 | 0 | 0 | 6ch deserializer |
| TDM TX | 150 | 250 | 0 | 0 | 8ch serializer |
| Audio Clock Gen | 100 | 200 | 0 | 0 | MMCM wrapper |
| DDR3 MIG | 6,000 | 4,000 | 0 | 0 | Hard IP wrapper |
| System Interconnect | 800 | 600 | 0 | 0 | AXI-lite, etc. |
| **Core Subtotal** | **~12,250** | **~9,350** | **8** | **4** | |

### 9.2.2 Studio Mode (Default)

| Block | LUTs | FFs | BRAM | DSP48 | Notes |
|-------|------|-----|------|-------|-------|
| DSP Core Engine | 3,000 | 2,000 | 4 | 8 | Time-mux MAC |
| Mix Bus Matrix | 500 | 800 | 0 | 0 | 6 buses |
| Audio DMA | 800 | 600 | 2 | 0 | 8 channels |
| Display Controller | 1,500 | 1,200 | 0 | 0 | ILI9341 SPI |
| Touch Controller | 300 | 200 | 0 | 0 | XPT2046 SPI |
| SD Card Controller | 600 | 400 | 0 | 0 | SPI mode |
| I²C Controller | 200 | 150 | 0 | 0 | Codec control |
| **Studio Mode Subtotal** | **~6,900** | **~5,350** | **6** | **8** | |

### 9.2.3 Studio Mode + Reverb Accelerator (Optional)

| Block | LUTs | FFs | BRAM | DSP48 | Notes |
|-------|------|-----|------|-------|-------|
| Reverb Engine | 3,000 | 2,500 | 4 | 8 | Convolution |
| Delay Lines | 200 | 100 | 0 | 0 | DDR3 backed |
| **Reverb Subtotal** | **~3,200** | **~2,600** | **4** | **8** | |

### 9.2.4 Separation Mode (Replaces Studio DSP)

| Block | LUTs | FFs | BRAM | DSP48 | Notes |
|-------|------|-----|------|-------|-------|
| FFT Core (Xilinx) | 1,500 | 1,200 | 8 | 12 | Per separator |
| α/δ Calculator | 800 | 600 | 0 | 8 | HLS generated |
| Histogram | 400 | 300 | 1 | 0 | BRAM based |
| Mask Application | 600 | 400 | 2 | 4 | |
| IFFT Core (Xilinx) | 1,500 | 1,200 | 8 | 12 | Per separator |
| **Per-Separator Subtotal** | **~4,800** | **~3,700** | **19** | **36** | |

**3 Separators (max):**
| **3× Separator Total** | **~14,400** | **~11,100** | **57** | **108** | |

---

## 9.3 Total Resource Utilization

### 9.3.1 Studio Mode (No Reverb)

| Resource | Used | Available | Percent |
|----------|------|-----------|---------|
| LUTs | 19,150 | 63,400 | **30%** |
| FFs | 14,700 | 126,800 | **12%** |
| BRAM | 14 | 135 | **10%** |
| DSP48 | 12 | 240 | **5%** |

### 9.3.2 Studio Mode + Reverb

| Resource | Used | Available | Percent |
|----------|------|-----------|---------|
| LUTs | 22,350 | 63,400 | **35%** |
| FFs | 17,300 | 126,800 | **14%** |
| BRAM | 18 | 135 | **13%** |
| DSP48 | 20 | 240 | **8%** |

### 9.3.3 Separation Mode (3 Separators)

| Resource | Used | Available | Percent |
|----------|------|-----------|---------|
| LUTs | 26,650 | 63,400 | **42%** |
| FFs | 20,450 | 126,800 | **16%** |
| BRAM | 65 | 135 | **48%** |
| DSP48 | 112 | 240 | **47%** |

---

## 9.4 Timing Budget

### 9.4.1 Fabric Clock: 100 MHz

| Path | Constraint | Margin |
|------|------------|--------|
| DSP Core | 10 ns (100 MHz) | ~5 ns typical |
| TDM I/O | 10 ns | ~7 ns (async safe) |
| DDR3 MIG | Hard IP | Guaranteed |
| Display SPI | 10 ns | ~8 ns |

### 9.4.2 Audio Sample Processing Budget

```
100 MHz fabric / 48 kHz sample rate = 2083 cycles per sample

Budget allocation:
- DSP Core (36 operations): ~400 cycles
- Mix Bus (6 channels): ~100 cycles
- TDM I/O: ~50 cycles
- DMA housekeeping: ~100 cycles
- Total: ~650 cycles
- Margin: 2083 - 650 = 1433 cycles (~69% idle)

Conclusion: Very comfortable timing margin for audio processing.
```

### 9.4.3 Latency Budget

| Path | Latency (samples) | Latency (ms @ 48kHz) |
|------|------------------|----------------------|
| ADC → TDM RX | 1 | 0.021 |
| TDM RX → DSP Core | 1 | 0.021 |
| DSP Core (6 modules) | 6 | 0.125 |
| Mix Bus | 1 | 0.021 |
| TDM TX → DAC | 1 | 0.021 |
| **Total Round-Trip** | **~10** | **~0.2 ms** |

**Separation Mode (DUET):**
| STFT Framing | 1024 | 21.3 |
| FFT Processing | 512 | 10.7 |
| α/δ + Masking | 256 | 5.3 |
| IFFT + Overlap | 512 | 10.7 |
| **Total Latency** | **~2300** | **~48 ms** |

---

## 9.5 Power Estimation

### 9.5.1 Static Power (XC7A100T, typical)

| Component | Power | Notes |
|-----------|-------|-------|
| Static (leakage) | ~100 mW | Temperature dependent |
| DDR3 I/O | ~50 mW | Termination, drive |
| Other I/O | ~30 mW | SPI, I²C, etc. |

### 9.5.2 Dynamic Power

| Mode | Clock Freq | Toggle Rate | Power |
|------|-----------|-------------|-------|
| Idle | 100 MHz | ~5% | ~150 mW |
| Studio Mode | 100 MHz | ~25% | ~400 mW |
| Separation Mode | 100 MHz | ~60% | ~800 mW |

### 9.5.3 Total System Power

| Component | Current Draw |
|-----------|--------------|
| FPGA (max) | ~1.0 W |
| CS42448 Codec | ~150 mW |
| ILI9341 Display | ~100 mW |
| SD Card (active) | ~200 mW |
| DDR3 SDRAM | ~500 mW |
| Miscellaneous | ~150 mW |
| **Total** | **~2.1 W** |

**Battery Life (2S 3000mAh):**
- 2.1W / 7.4V = 284mA
- 3000mAh / 284mA = **~10.5 hours**

---

## 9.6 Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| DSP48 shortage in 3-separator mode | Low | High | Mode-switch architecture handles this |
| BRAM shortage | Low | Medium | DDR3 fallback for delay lines |
| Timing closure failures | Low | High | Conservative 100MHz, room for 80MHz if needed |
| SD card write speed insufficient | Medium | Medium | Implement SDIO 4-bit mode |
| DDR3 bandwidth contention | Low | Low | 256-bit @ 400MHz = 12.8 GB/s >> 2 MB/s audio |

---

## 9.7 Resource Headroom Summary

```
Resource Headroom (Studio Mode):

LUTs:     30% used, 70% available for expansion
FFs:      12% used, 88% available
BRAM:     10% used, 90% available
DSP48:    5% used, 95% available

This design has SIGNIFICANT headroom for:
- Additional DSP modules
- Enhanced GUI effects
- More complex routing
- Debug/monitoring features

The A7-100T is the right size with room to grow.
```

---

## 9.8 Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-06-21 | GodBot | Initial resource budget |
| 1.0 | 2026-06-21 | GodBot | Complete with power estimation, risk assessment, headroom analysis |

---

*End of Section 9 — RESOURCE BUDGET*
