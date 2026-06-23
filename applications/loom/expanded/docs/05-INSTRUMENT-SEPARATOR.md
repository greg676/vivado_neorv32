# OPUS MAXIMUS / LOOM — Section 5: INSTRUMENT SEPARATOR (DUET)

**Document ID:** OPUS-05-INSTRUMENT-SEPARATOR  
**Version:** 1.0 — Research Subproject Specification  
**Date:** 2026-06-21  
**Author:** GodBot 🜂 for codecbox

---

## 5.1 Overview

The Instrument Separator is LOOM's crown jewel — a real-time implementation of the DUET algorithm that separates up to 5 instruments from a stereo room microphone pair.

**Key Constraints:**
- Input: Stereo microphone pair with phase discrimination
- Output: Up to 5 individual instrument streams
- Latency: < 25ms (acceptable for recording, not live monitoring)
- Processing: FPGA fabric with CPU-assist for clustering

---

## 5.2 The DUET Algorithm

### 5.2.1 Theory

DUET (Degenerate Unmixing Estimation Technique) exploits **sparse signal representation** in the time-frequency domain:

1. In the STFT domain, most time-frequency bins contain energy from only ONE source (sparsity assumption)
2. Each source has a characteristic **spatial signature**: level difference (α) and delay (δ) between stereo channels
3. Clustering these signatures separates the sources

### 5.2.2 Mathematical Foundation

For stereo mix x = [x₁, x₂]ᵀ:
```
x₁(t) = Σ sᵢ(t)              (sum of sources in left channel)
x₂(t) = Σ aᵢ·sᵢ(t - δᵢ)      (delayed/attenuated in right channel)

In STFT domain:
X₁(ω,τ) = Σ Sᵢ(ω,τ)
X₂(ω,τ) = Σ aᵢ·e^(-jωδᵢ)·Sᵢ(ω,τ)

For a bin dominated by source i:
X₂/X₁ ≈ aᵢ·e^(-jωδᵢ)

Therefore:
α = |X₂/X₁|     (amplitude ratio, level difference)
δ = -arg(X₂/X₁)/ω  (phase-derived delay)
```

### 5.2.3 Algorithm Steps

```
1. STFT
   ┌─────────┐
   │  L, R   │──▶ Window (Hann) ──▶ FFT ──▶ L(ω,τ), R(ω,τ)
   └─────────┘

2. For each TF bin, compute:
   ┌─────────────────┐
   │ α = |R/L|     │  Amplitude ratio (0.1 to 10 typical)
   │ δ = -∠(R/L)/ω │  Delay (-20ms to +20ms typical)
   └─────────────────┘

3. Build 2D histogram over (α, δ):
   ┌─────────────────────────────────────┐
   │                                     │
   │   α                                 │
   │   │   ○        ○                    │
   │  10│      ○            ○           │
   │   │    ○      ○                     │
   │   │         ○              ○       │
   │ 0.1│                                │
   │   └──────────────────────▶ δ       │
   │    -20ms              +20ms        │
   │                                     │
   │   Peaks = source locations          │
   └─────────────────────────────────────┘

4. Cluster and assign each bin to nearest source

5. Apply masks, inverse STFT per source
```

---

## 5.3 FPGA Implementation Strategy

### 5.3.1 Hardware/Software Partition

| Task | Implementation | Reason |
|------|---------------|--------|
| STFT (FFT) | Xilinx FFT IP | Heavy DSP, standard block |
| Per-bin α/δ | Fabric HLS | Parallel per-bin, streaming |
| Histogram binning | Fabric | High throughput |
| Peak finding | NEORV32 | Low rate, decision logic |
| Mask application | Fabric | Streaming, high throughput |
| ISTFT (IFFT) | Xilinx FFT IP | Same as FFT |

### 5.3.2 Data Flow

```
Stereo Input ──▶ Dual FFT (L,R) ──▶ Magnitude/Phase ──▶ α/δ Calculation
        │                                                        │
        │                                                        ▼
        │                                              ┌─────────────────┐
        │                                              │ Histogram BRAM  │
        │                                              │ (α bins × δ bins)│
        │                                              └────────┬────────┘
        │                                                       │
        │                                                       ▼
        │                                              ┌─────────────────┐
        │                                              │ NEORV32 reads   │
        │                                              │ finds peaks     │
        │                                              └────────┬────────┘
        │                                                       │
        │                                                       ▼
        │                                              ┌─────────────────┐
        │                                              │ Peak positions  │
        │                                              │ written back    │
        │                                              └────────┬────────┘
        │                                                       │
        ▼                                                       ▼
Mask Generation ◀── Cluster assignment ──▶ Mask BRAM
        │
        ▼
ISTFT per source ──▶ Separated outputs (up to 5 channels)
```

---

## 5.4 Detailed Block Specifications

### 5.4.1 STFT Block

```verilog
module stft_engine (
    input  wire        clk,
    input  wire        rst_n,
    // Input: time-domain samples
    input  wire signed [23:0] sample_in,
    input  wire        sample_valid,
    // Output: FFT bins
    output reg  [31:0] fft_real [0:1023],
    output reg  [31:0] fft_imag [0:1023],
    output reg         frame_complete
);

// Uses Xilinx FFT IP:
// - Transform length: 1024 points
// - Data format: fixed-point, 24-bit
// - Scaling: unconditional scaling (divide by 1024)
// - Implementation: pipelined streaming I/O

// Window: Hann window, 1024 coefficients in ROM
// Overlap: 50% (512 new samples per frame)

endmodule
```

### 5.4.2 α/δ Calculator (HLS C++)

```cpp
// HLS source for per-bin calculation
#include "hls_math.h"

void alpha_delta_calc(
    hls::stream<fixed32>& L_real,
    hls::stream<fixed32>& L_imag,
    hls::stream<fixed32>& R_real,
    hls::stream<fixed32>& R_imag,
    hls::stream<alpha_delta_pair>& out,
    int fft_size
) {
    #pragma HLS INTERFACE s_axilite port=fft_size
    #pragma HLS INTERFACE axis port=L_real
    #pragma HLS INTERFACE axis port=L_imag
    #pragma HLS INTERFACE axis port=R_real
    #pragma HLS INTERFACE axis port=R_imag
    #pragma HLS INTERFACE axis port=out

    for (int k = 0; k < fft_size; k++) {
        #pragma HLS PIPELINE II=1

        // Read inputs
        fixed32 Lr = L_real.read();
        fixed32 Li = L_imag.read();
        fixed32 Rr = R_real.read();
        fixed32 Ri = R_imag.read();

        // Compute R/L as complex division
        fixed32 denom = Lr*Lr + Li*Li;
        fixed32 ratio_r = (Rr*Lr + Ri*Li) / denom;
        fixed32 ratio_i = (Ri*Lr - Rr*Li) / denom;

        // α = magnitude of ratio
        fixed32 alpha = hls::sqrt(ratio_r*ratio_r + ratio_i*ratio_i);

        // δ = -phase(ratio) / ω
        // ω = 2πk / (fft_size * sample_period)
        fixed32 phase = hls::atan2(ratio_i, ratio_r);
        fixed32 delta = -phase * fft_size / (2 * M_PI * k + 0.001f);

        // Output pair
        alpha_delta_pair result = {alpha, delta};
        out.write(result);
    }
}
```

### 5.4.3 Histogram Accumulator

```
Histogram dimensions:
- α bins: 64 (log-spaced, 0.1 to 10)
- δ bins: 64 (linear, -20ms to +20ms)
- Total: 4096 bins × 16-bit count = 8KB BRAM

For each TF bin:
    1. Compute α, δ
    2. Convert to bin indices:
       α_idx = log2(α) × scale + offset
       δ_idx = (δ + 20ms) × scale
    3. Increment histogram[α_idx][δ_idx]
```

### 5.4.4 CPU Clustering Algorithm

```c
// NEORV32 firmware
void find_peaks_in_histogram(uint16_t *hist, int alpha_bins, int delta_bins,
                             peak_t *peaks, int max_peaks) {
    // Simple peak finding: local maxima above threshold
    int peak_count = 0;

    for (int a = 1; a < alpha_bins - 1; a++) {
        for (int d = 1; d < delta_bins - 1; d++) {
            uint16_t val = hist[a * delta_bins + d];
            uint16_t threshold = 100;  // Minimum peak height

            if (val > threshold &&
eighbors) {
                // Store peak
                peaks[peak_count].alpha_idx = a;
                peaks[peak_count].delta_idx = d;
                peaks[peak_count].count = val;
                peak_count++;

                if (peak_count >= max_peaks) break;
            }
        }
    }
}
```

---

## 5.5 Latency Analysis

| Stage | Latency (samples) | Latency (ms @ 48kHz) |
|-------|------------------|----------------------|
| Frame buffering (50% overlap) | 1024 | 21.3 |
| FFT (pipelined) | 1024 | 21.3 |
| α/δ + histogram | 256 | 5.3 |
| CPU clustering | ~1 frame | 21.3 |
| Mask + IFFT | 1024 | 21.3 |
| **Total** | **~1536** | **~32ms** |

**Optimization:** Use 512-point FFT for 10.7ms latency, or accept 32ms for 1024-point.

---

## 5.6 Resource Estimate (Per Separator)

| Component | DSP48 | BRAM (36Kb) | LUTs |
|-----------|-------|-------------|------|
| FFT (1024pt) | 12 | 4 | 1500 |
| IFFT (1024pt) | 12 | 4 | 1500 |
| α/δ calculator | 8 | 0 | 800 |
| Histogram | 0 | 1 | 400 |
| Mask engine | 4 | 2 | 600 |
| **Total** | **36** | **11** | **4800** |

Three separators (for 3 mic pairs): **108 DSP48, 33 BRAM, 14.4K LUTs**

---

## 5.7 Mode Switch Implementation

### 5.7.1 Studio Mode
- DSP Core running: 6 pipes × 6 modules
- Separators: Idle (clock gated)
- DSP allocation: 8 slices to DSP Core

### 5.7.2 Separation Mode
- DSP Core: Bypassed (passthrough only)
- Separators: Active (up to 3 instances)
- DSP allocation: 108 slices to Separators

### 5.7.3 Switching
```c
// Switch mode via register
typedef enum { MODE_STUDIO, MODE_SEPARATION } SystemMode;

void set_mode(SystemMode mode) {
    if (mode == MODE_SEPARATION) {
        // 1. Fade audio to silence
        // 2. Wait for audio frame boundary
        // 3. Disable DSP core, enable separators
        // 4. Configure separator for mic pair selection
        // 5. Fade audio back in
    }
}
```

---

## 5.8 Python Reference Implementation

```python
# models/separator/duet.py

import numpy as np
from scipy.signal import stft, istft
from scipy.cluster.vq import kmeans2

class DUETSeparator:
    def __init__(self, nfft=1024, hop_length=None, n_sources=5):
        self.nfft = nfft
        self.hop_length = hop_length or nfft // 2
        self.n_sources = n_sources

    def separate(self, stereo_signal, fs):
        """Separate stereo mixture into sources"""
        L, R = stereo_signal[:, 0], stereo_signal[:, 1]

        # STFT
        _, _, L_stft = stft(L, fs, nperseg=self.nfft,
                            noverlap=self.nfft//2)
        _, _, R_stft = stft(R, fs, nperseg=self.nfft,
                            noverlap=self.nfft//2)

        # Compute α and δ for each TF bin
        ratio = R_stft / (L_stft + 1e-10)
        alpha = np.abs(ratio)
        delta = -np.angle(ratio) / (2 * np.pi * np.fft.fftfreq(self.nfft, 1/fs)[:, None])

        # Mask invalid values
        valid = (alpha > 0.1) & (alpha < 10) & (np.abs(delta) < 0.02)

        # Build histogram
        alpha_bins = np.logspace(-1, 1, 64)
        delta_bins = np.linspace(-0.02, 0.02, 64)

        hist, _, _ = np.histogram2d(
            alpha[valid].flatten(),
            delta[valid].flatten(),
            bins=[alpha_bins, delta_bins]
        )

        # Find peaks (cluster centers)
        # Simplified: use k-means on (α, δ) pairs
        features = np.column_stack([
            alpha[valid].flatten(),
            delta[valid].flatten()
        ])

        centroids, labels = kmeans2(features, self.n_sources, minit='points')

        # Build masks and separate
        sources = []
        for i in range(self.n_sources):
            mask = np.zeros_like(L_stft)
            # Assign bins to nearest centroid
            # ... (mask building logic)

            source_stft = L_stft * mask
            _, source_waveform = istft(source_stft, fs,
                                       nperseg=self.nfft,
                                       noverlap=self.nfft//2)
            sources.append(source_waveform)

        return sources
```

---

## 5.9 Development Roadmap

| Phase | Task | Duration | Success Criteria |
|-------|------|----------|----------------|
| 1 | Python DUET on test recordings | 2 weeks | Separates drums/bass/guitar |
| 2 | Fixed-point analysis | 1 week | Define Q-formats |
| 3 | HLS α/δ block | 2 weeks | Matches Python bit-accurate |
| 4 | FFT integration | 1 week | End-to-end flow |
| 5 | CPU clustering | 1 week | Real-time histogram reading |
| 6 | Full integration | 2 weeks | Real-time separation on FPGA |

---

## 5.10 Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-06-21 | GodBot | Initial DUET specification |
| 1.0 | 2026-06-21 | GodBot | Complete with HLS code, latency analysis, resource estimates |

---

*End of Section 5 — INSTRUMENT SEPARATOR*
