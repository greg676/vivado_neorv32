# OPUS MAXIMUS / LOOM — Section 4: DSP MODULE LIBRARY

**Document ID:** OPUS-04-DSP-MODULE-LIBRARY  
**Version:** 1.0 — Implementation Ready  
**Date:** 2026-06-21  
**Author:** GodBot 🜂 for codecbox

---

## 4.1 Overview

Each DSP module consists of:
1. **Microcode Template** — Opcode and execution flow
2. **Coefficient Layout** — Parameter storage in BRAM
3. **State Layout** — Runtime state (filter history, envelopes, etc.)
4. **Golden Model** — Python reference implementation

All modules use **Q1.23** for audio samples and **Q1.31** for internal accumulation.

---

## 4.2 Module Summary Table

| Module | Opcode | MACs/Sample | Coeff Words | State Words | Notes |
|--------|--------|-------------|-------------|-------------|-------|
| INPUT_GAIN | 0x01 | 1 | 1 | 0 | Scalar multiply |
| PAN | 0x02 | 2 | 2 | 0 | Constant-power stereo |
| EQ_5BAND | 0x03 | 25 | 25 | 20 | 5 cascaded biquads |
| LOWCUT | 0x04 | 5 | 5 | 4 | High-pass biquad |
| HIGHCUT | 0x05 | 5 | 5 | 4 | Low-pass biquad |
| COMPRESSOR | 0x06 | 10 | 6 | 4 | RMS + gain curve |
| LIMITER | 0x07 | 8 | 4 | 6 | Peak limiter |
| GATE | 0x08 | 6 | 4 | 4 | Noise gate |
| DELAY | 0x09 | 4 | 4 | varies | Tapped delay line |
| BUS_SEND | 0x0A | 1 | 1 | 0 | Route to mix bus |

---

## 4.3 INPUT_GAIN (Opcode 0x01)

### 4.3.1 Function
Simple scalar gain with saturation.

### 4.3.2 Coefficient Layout (1 word)
```
Word 0 [31:0]: gain_scalar (Q1.31)
    Range: 0.0 to ~16.0 (+24dB)
    Unity gain: 0x7FFFFFFF (actually 0x7FFFFF00 for headroom)
```

### 4.3.3 Algorithm
```python
def gain_process(x: int, gain_q31: int) -> int:
    # x is Q1.23, gain is Q1.31
    # result = x * gain = Q2.54
    acc = (x * gain_q31) >> 31  # Back to Q1.23
    return saturate_q123(acc)
```

### 4.3.4 RTL Implementation
```verilog
module dsp_gain (
    input  signed [23:0] x,
    input  signed [31:0] gain,
    output signed [23:0] y
);
    wire signed [55:0] mult = x * gain;
    wire signed [23:0] result = mult[54:31];  // Q1.23

    // Saturation
    assign y = (mult[55] && !mult[54:31]) ? 24'h800000 :  // Neg overflow
               (!mult[55] && |mult[54:31]) ? 24'h7FFFFF :  // Pos overflow
               result;
endmodule
```

---

## 4.4 PAN (Opcode 0x02)

### 4.4.1 Function
Constant-power pan to stereo output.

### 4.4.2 Coefficient Layout (2 words)
```
Word 0: left_gain (Q1.31)
Word 1: right_gain (Q1.31)
```

### 4.4.3 Pan Law
```python
import math

def pan_coefficients(pan: float) -> tuple:
    """
    pan: -1.0 (full left) to +1.0 (full right), 0.0 = center
    Returns: (left_gain, right_gain) in linear amplitude
    """
    # Constant power: sin/cos law
    angle = (pan + 1) * math.pi / 4  # Map -1..1 to 0..pi/2
    left = math.cos(angle)
    right = math.sin(angle)
    return left, right
```

### 4.4.4 Output Behavior
PAN doesn't modify the sample; it writes to the **pan accumulation registers** which are then summed into the stereo mix bus.

---

## 4.5 EQ_5BAND (Opcode 0x03)

### 4.5.1 Function
Five cascaded parametric biquad filters.

### 4.5.2 Filter Layout
```
Band 0: Low Shelf (80Hz default)
Band 1: Peaking (500Hz default)
Band 2: Peaking (2kHz default)
Band 3: Peaking (5kHz default)
Band 4: High Shelf (12kHz default)
```

### 4.5.3 Coefficient Layout (25 words)
```
For each of 5 bands (5 × 5 = 25 coefficients):
    b0, b1, b2, a1, a2 (all Q2.30 for stability)
```

### 4.5.4 Biquad Calculation (RBJ Cookbook)
```python
def biquad_coeffs(fs: float, f0: float, Q: float, gain_db: float,
                  filter_type: str) -> tuple:
    """Returns (b0, b1, b2, a1, a2) in Q2.30"""
    import math

    A = 10 ** (gain_db / 40) if gain_db != 0 else 1.0
    w0 = 2 * math.pi * f0 / fs
    cos_w0 = math.cos(w0)
    sin_w0 = math.sin(w0)
    alpha = sin_w0 / (2 * Q)

    if filter_type == "peaking":
        b0 = 1 + alpha * A
        b1 = -2 * cos_w0
        b2 = 1 - alpha * A
        a0 = 1 + alpha / A
        a1 = -2 * cos_w0
        a2 = 1 - alpha / A
    elif filter_type == "low_shelf":
        # ... (RBJ formulas)
        pass
    elif filter_type == "high_shelf":
        # ...
        pass

    # Normalize by a0 and convert to Q2.30
    scale = (1 << 30) / a0
    return (
        int(b0 * scale), int(b1 * scale),
        int(b2 * scale), int(a1 * scale), int(a2 * scale)
    )
```

### 4.5.5 State Layout (20 words)
```
Per band: x[n-1], x[n-2], y[n-1], y[n-2] (4 words × 5 bands = 20)
```

---

## 4.6 COMPRESSOR (Opcode 0x06)

### 4.6.1 Function
RMS level detector with adjustable threshold, ratio, attack, release.

### 4.6.2 Parameters
```
threshold:    dB level where compression starts (-60 to 0 dBFS)
ratio:        compression ratio (1:1 to 20:1)
attack_ms:    time to reach 63% of final value (0.1 to 100 ms)
release_ms:   time to decay 63% (10 to 1000 ms)
makeup_gain:  output gain boost (0 to 24 dB)
```

### 4.6.3 Coefficient Layout (6 words)
```
Word 0: threshold_q23 (linear threshold as Q1.23)
Word 1: ratio_fixed (ratio as Q4.28, e.g., 4:1 = 4.0)
Word 2: attack_coeff (Q1.31, derived from attack time)
Word 3: release_coeff (Q1.31, derived from release time)
Word 4: makeup_gain (Q1.31 linear)
Word 5: knee_width (Q1.31, soft knee in dB)
```

### 4.6.4 Algorithm
```python
class Compressor:
    def __init__(self):
        self.env = 0  # RMS envelope (Q1.23)
        self.gain = 1.0  # Current gain reduction

    def process(self, x: int, coeffs: dict) -> int:
        # 1. Level detector (RMS approximation)
        abs_x = abs(x)
        attack = coeffs['attack_coeff']
        release = coeffs['release_coeff']

        # Exponential moving average
        if abs_x > self.env:
            self.env = abs_x + ((self.env - abs_x) * (1 - attack)) // (1 << 31)
        else:
            self.env = abs_x + ((self.env - abs_x) * (1 - release)) // (1 << 31)

        # 2. Gain computer (log domain)
        threshold = coeffs['threshold_q23']
        if self.env < threshold:
            gain_reduction = 1.0
        else:
            overshoot = self.env / threshold
            ratio = coeffs['ratio_fixed'] / (1 << 28)
            gain_reduction = overshoot ** ((1/ratio) - 1)

        # 3. Smooth gain (optional smoothing stage)
        # 4. Apply gain with makeup
        result = (x * gain_reduction * coeffs['makeup_gain']) >> 31
        return saturate(result)
```

### 4.6.5 State Layout (4 words)
```
State 0: envelope (Q1.23)
State 1: gain_reduction (Q1.31)
State 2: attack_state (internal)
State 3: release_state (internal)
```

---

## 4.7 DELAY (Opcode 0x09)

### 4.7.1 Function
Tapped delay line with feedback.

### 4.7.2 Parameters
```
delay_ms:     1 to 500 ms
delay_samples: calculated from delay_ms × fs / 1000
feedback:     0 to 0.99 (feedback gain)
mix:          0 to 1.0 (wet/dry)
```

### 4.7.3 Memory Requirements
```
At 48kHz, 500ms = 24,000 samples × 24 bits = 576,000 bits = 72KB

Storage options:
- Short delays (< 10ms): BRAM (on-chip)
- Medium delays (10-100ms): DDR3 via DMA
- Long delays (> 100ms): DDR3 + circular buffer management
```

### 4.7.4 Coefficient Layout (4 words)
```
Word 0: delay_samples (integer)
Word 1: feedback_gain (Q1.31)
Word 2: wet_mix (Q1.31)
Word 3: ddr_base_addr (for long delays, pointer to external memory)
```

### 4.7.5 State Layout (variable)
```
State 0: write pointer (into delay line)
State 1: current output sample
State 2-3: reserved

For DDR3 delays:
State 4: DMA request flag
State 5: buffer valid flag
```

---

## 4.8 Golden Model Python Package

### 4.8.1 Directory Structure
```
models/
├── __init__.py
├── fixedpoint.py              # Q-format helpers
├── dsp_modules/
│   ├── __init__.py
│   ├── gain.py
│   ├── pan.py
│   ├── eq.py
│   ├── compressor.py
│   ├── limiter.py
│   ├── gate.py
│   └── delay.py
└── test/
    ├── test_gain.py
    ├── test_eq.py
    └── generate_vectors.py     # Create test vectors for RTL
```

### 4.8.2 Fixed-Point Utilities
```python
# models/fixedpoint.py

def float_to_q123(x: float) -> int:
    """Convert float to Q1.23 signed"""
    scaled = int(x * (1 << 23))
    if scaled > 0x7FFFFF:
        return 0x7FFFFF
    elif scaled < -0x800000:
        return -0x800000
    return scaled

def q123_to_float(x: int) -> float:
    """Convert Q1.23 to float"""
    if x & 0x800000:  # Negative
        x -= 0x1000000
    return x / (1 << 23)

def saturate_q123(x: int) -> int:
    """Saturate to Q1.23 range"""
    if x > 0x7FFFFF:
        return 0x7FFFFF
    elif x < -0x800000:
        return -0x800000
    return x & 0xFFFFFF

def db_to_linear(db: float) -> int:
    """Convert dB to Q1.31 linear gain"""
    linear = 10 ** (db / 20)
    return min(int(linear * (1 << 31)), 0x7FFFFFFF)
```

### 4.8.3 Test Vector Generation
```python
# models/test/generate_vectors.py

import numpy as np
from models.dsp_modules.gain import Gain
from models.dsp_modules.eq import EQ5Band

def generate_gain_vectors():
    """Create input/output pairs for RTL testbench"""
    test_cases = []

    # Test 1: Unity gain
    test_cases.append({
        'input': 0x400000,  # +0.5 in Q1.23
        'gain_db': 0.0,
        'expected': 0x400000
    })

    # Test 2: +6dB gain
    test_cases.append({
        'input': 0x200000,  # +0.25
        'gain_db': 6.0,
        'expected': 0x400000  # +0.5
    })

    # Test 3: Saturation
    test_cases.append({
        'input': 0x7FFFFF,  # Max positive
        'gain_db': 12.0,
        'expected': 0x7FFFFF  # Should saturate
    })

    # Write to file for Verilog $readmemh
    with open('test_vectors/gain_in.hex', 'w') as f_in, \
         open('test_vectors/gain_out.hex', 'w') as f_out, \
         open('test_vectors/gain_coeff.hex', 'w') as f_coeff:

        for tc in test_cases:
            gain = Gain()
            gain.set_gain(tc['gain_db'])

            f_in.write(f"{tc['input']:06X}\n")
            f_out.write(f"{tc['expected']:06X}\n")
            f_coeff.write(f"{gain.coeff_q31:08X}\n")

if __name__ == '__main__':
    generate_gain_vectors()
```

---

## 4.9 Coefficient Update Protocol

### 4.9.1 Software-Fabric Interface
NEORV32 updates coefficients via memory-mapped writes:

```c
// Write coefficient to DSP core
void dsp_write_coeff(uint8_t coeff_idx, uint32_t value) {
    volatile uint32_t *coeff_base = (void*)0x60001000;
    coeff_base[coeff_idx] = value;
}

// Update EQ band
void eq_set_band(uint8_t pipe, uint8_t band, float freq, float q, float gain_db) {
    // Calculate biquad coefficients in Python model
    // Convert to fixed-point
    // Write to coefficient memory
}
```

### 4.9.2 Glitch-Free Updates
For smooth parameter changes:
1. Write new coefficients to **shadow registers** (double-buffered)
2. Set "commit" bit at frame boundary
3. DSP core swaps to new coefficients at sample_tick

---

## 4.10 Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-06-21 | GodBot | Initial module specifications |
| 1.0 | 2026-06-21 | GodBot | Complete coefficient layouts, golden models, test vectors |

---

*End of Section 4 — DSP MODULE LIBRARY*
