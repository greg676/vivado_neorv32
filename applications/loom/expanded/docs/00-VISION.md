# OPUS MAXIMUS / LOOM — Section 0: VISION

**Document ID:** OPUS-00-VISION  
**Version:** 1.0 — Implementation Ready  
**Date:** 2026-06-21  
**Author:** GodBot 🜂 for codecbox  
**Target:** Arty A7-100T (XC7A100T-1CSG324C)

---

## 0.1 The Product in One Sentence

**A pocket studio that hears the room and writes each instrument to its own track.**

---

## 0.2 What LOOM Is

LOOM is a standalone hardware multitrack recorder and live source-separation engine for musicians, built on a single FPGA. No computer. No DAW. You plug in mics and speakers, you touch the screen with a pen, and the FPGA fabric does real-time multitrack recording, mixing, effects, and — the signature feature — decodes individual instruments out of a stereo room mic straight onto separate tracks.

The FPGA fabric is the engine. The 2.4" ILI9341 touchscreen is the control surface. The NEORV32 soft-CPU is the conductor — it manages state, UI, files, and configuration, but **never touches the audio samples**. Audio flows through fabric at hardware speed; the CPU just steers it.

---

## 0.3 What Problem It Solves

| Current State | LOOM Solution |
|-------------|---------------|
| Recording a band requires a computer, interface, DAW, setup time | Standalone box, power on, touch screen, record immediately |
| Separating instruments requires post-processing plugins or cloud AI | Real-time FPGA separation using DUET algorithm, direct to tracks |
| Field recording means laptops, batteries, fragility | Battery-powered handheld, rugged, instant-on |
| Learning curve: DAWs are complex | Five-tab touchscreen UI, immediate-mode, no menus deep |

---

## 0.4 Core Value Propositions

### For Musicians (Primary)
1. **Capture everything** — 6 simultaneous inputs, 24-bit/48kHz
2. **Hear separation** — Point a stereo mic at an ensemble, get individual instrument tracks
3. **No computer required** — Complete workflow from record to export on device
4. **Handheld portable** — Fits in a gig bag, runs on USB-C power bank

### For Audio Engineers
1. **Zero-latency monitoring** — Sub-millisecond DSP, no DAW buffer anxiety
2. **Real-time effects** — Per-channel EQ, compression, gate, limiter, all running on fabric
3. **Stem separation** — Live separation for mixing, not just post

### For Technologists
1. **Pure FPGA audio** — No CPU in the audio path, deterministic hard-real-time
2. **Software-defined DSP** — Coefficient-swap "modules" instead of bitstream reconfiguration
3. **Open golden models** — Every DSP block has Python reference, bit-accurate verification

---

## 0.5 User Personas

### Persona A: "Gigging Sarah"
- Jazz vocalist with a loop station
- Records her live sets at clubs
- Current pain: laptop + interface + cables = setup nightmare
- LOOM value: Battery powered, 6 inputs (vocal mic + 5 loop station outs), records to SD, export WAV later

### Persona B: "Producer Marcus"
- Bedroom producer, samples everything
- Wants to isolate instruments from vinyl/YouTube
- Current pain: iZotope RX is expensive and slow, cloud separation has privacy concerns
- LOOM value: Real-time separation, no cloud, instant stems to DAW

### Persona C: "Field Recordist Yuki"
- Records nature, folk performances, oral histories
- Needs rugged, portable, long battery life
- Current pain: Portable recorders have limited inputs, no processing
- LOOM value: 6 inputs, real-time EQ/compression while recording, separation for interviews with music

---

## 0.6 The "Magic Moment"

The moment that sells LOOM:

1. Sarah plugs in her stereo room mic
2. She taps "SEPARATION MODE" on the screen
3. She watches the display show 5 colored blobs, each an instrument
4. She hits RECORD
5. Later, she has 5 individual WAV files — drums, bass, keys, sax, vocal — separated live

No computer. No waiting. No subscription. Just the box and the magic.

---

## 0.7 Non-Goals (What LOOM Is NOT)

| Not a Goal | Why |
|------------|-----|
| Cloud connectivity | Offline-only, no telemetry, no subscriptions |
| MIDI sequencing | Audio-only, no MIDI in v1 (maybe v2) |
| Virtual instruments | No synths, no samplers — pure recording/mixing |
| DAW replacement | Complements DAWs, doesn't replace them (export to DAW for final mix) |
| Multitrack playback beyond 6+2 | Limited by codec (6 ADC, 8 DAC) — design constraint, not bug |
| Full mixing console surface | Touchscreen + stylus, not motorized faders |

---

## 0.8 Success Criteria

### Technical Success
- [ ] Audio passes through clean: THD+N < -80dB
- [ ] Latency < 5ms round-trip (ADC → DSP → DAC)
- [ ] Separation works on real instruments: drums/bass/keys/guitar/vocal
- [ ] 6 hours continuous recording on battery

### Commercial Success
- [ ] User completes song from record to export without touching a computer
- [ ] User shows separation feature to another musician who asks "where can I buy that?"
- [ ] Unit cost < $500 BOM, sells for $999 retail

---

## 0.9 Document Relationships

```
00-VISION.md (this file)
    ↓ defines product
01-PRODUCT-SPEC.md
    ↓ defines what it does
02-SYSTEM-ARCHITECTURE.md
    ↓ defines how it's structured
03-FPGA-AUDIO-FABRIC.md through 11-BUILD-PLAN.md
    ↓ define implementation details
```

---

## 0.10 Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-06-21 | GodBot | Initial vision document |
| 1.0 | 2026-06-21 | GodBot | Implementation-ready with ILI9341 display spec |

---

*End of Section 0 — VISION*
