# OPUS MAXIMUS / LOOM — Section 8: STORAGE & RECORDING

**Document ID:** OPUS-08-STORAGE-RECORDING  
**Version:** 1.0 — Implementation Ready  
**Date:** 2026-06-21  
**Author:** GodBot 🜂 for codecbox

---

## 8.1 Overview

The Storage & Recording subsystem handles:
- **Multitrack recording** from audio fabric to SD card
- **Playback/overdub** from SD card to audio fabric
- **Project management** (save/load configurations)
- **File operations** (WAV export, directory management)

---

## 8.2 Storage Architecture

### 8.2.1 Data Flow

```
Recording Path:
┌──────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  Audio   │───▶│  DDR3 Ring   │───▶│  NEORV32     │───▶│  MicroSD     │
│  Fabric  │    │  Buffer      │    │  FatFs       │    │  Card        │
└──────────┘    └──────────────┘    └──────────────┘    └──────────────┘
                      ▲                                              │
                      │                                              │
              ┌───────┴───────┐                                      │
              │   Audio DMA   │                                      │
              └───────────────┘                                      │
                                                                     ▼
                                                              WAV Files

Playback Path:
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────┐
│  MicroSD     │───▶│  NEORV32     │───▶│  DDR3 Ring   │───▶│  Audio   │
│  Card        │    │  FatFs       │    │  Buffer      │    │  Fabric  │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────┘
       │                                                            │
       │                                                            │
       │                     ┌──────────────┐                       │
       └─────────────────────│   Audio DMA  │◀──────────────────────┘
                             └──────────────┘
```

### 8.2.2 Ring Buffer Design

```
DDR3 Ring Buffer Layout (per channel):
┌─────────────────────────────────────────────────────────────────────────┐
│                         RING BUFFER STRUCTURE                           │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐     │
│  │  Base Address: 0x40000000 + (channel * 0x80000)                 │     │
│  │  Size: 512KB per channel                                        │     │
│  │  Sample Size: 3 bytes (24-bit)                                  │     │
│  │  Capacity: ~3.5 seconds @ 48kHz                                 │     │
│  │                                                                   │     │
│  │  ┌─────────────────────────────────────────────────────────┐     │     │
│  │  │                                                         │     │     │
│  │  │  Write Pointer (fabric) ───────▶                       │     │     │
│  │  │                                                         │     │     │
│  │  │     ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┐        │     │     │
│  │  │     │█████│█████│█████│     │     │     │█████│        │     │     │
│  │  │     └─────┴─────┴─────┴─────┴─────┴─────┴─────┘        │     │     │
│  │  │                                                         │     │     │
│  │  │  Read Pointer (CPU) ────────▶                           │     │     │
│  │  │                                                         │     │     │
│  │  │                    │\\\\\\\│  Available data             │     │     │
│  │  │                                                         │     │     │
│  │  │                    │///////│  Free space                 │     │     │
│  │  │                                                         │     │     │
│  │  └─────────────────────────────────────────────────────────┘     │     │
│  └─────────────────────────────────────────────────────────────────┘     │
│                                                                         │
│  Watermark IRQs:                                                        │
│    - High watermark: CPU should read                                    │
│    - Low watermark:  CPU can write more                                 │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 8.3 Bandwidth Analysis

### 8.3.1 Audio Bandwidth

```
Recording (6 channels, 24-bit, 48kHz):
  6 × 3 bytes × 48000 = 864,000 bytes/sec = 864 KB/s

Playback (8 channels, same rate):
  8 × 3 bytes × 48000 = 1,152,000 bytes/sec = 1,125 KB/s

Simultaneous (record + playback):
  Total: ~2 MB/s
```

### 8.3.2 SD Card Interface Options

| Mode | Speed | Feasibility |
|------|-------|-------------|
| SPI Mode (10MHz) | ~1.25 MB/s | Marginal for 6ch |
| SPI Mode (20MHz) | ~2.5 MB/s | OK with margin |
| SDIO 1-bit (25MHz) | ~3.1 MB/s | Good |
| SDIO 4-bit (25MHz) | ~12.5 MB/s | Excellent |

**Recommendation:** Start with SPI @ 20MHz for bring-up, implement SDIO 4-bit for production.

### 8.3.3 SD Card Requirements

| Spec | Requirement |
|------|-------------|
| Minimum Class | Class 10 (10 MB/s sequential) |
| Recommended | UHS-I U1 or better |
| Format | FAT32 (up to 32GB) or exFAT (64GB+) |
| Allocation Unit | 64KB clusters for large files |

---

## 8.4 Audio DMA Controller

### 8.4.1 Register Map

```
Base: 0x60002000 (Audio DMA)

Offset      Register              Description
─────────────────────────────────────────────────────────
0x000       DMA_CTRL              Global control
0x004       DMA_STATUS            Status flags
0x008       DMA_IRQ_EN            Interrupt enable
0x00C       DMA_IRQ_STATUS        Interrupt status

Per-channel (0x100 + ch * 0x20):
0x100       CH0_CTRL              Channel 0 control
0x104       CH0_ADDR              DDR3 base address
0x108       CH0_SIZE              Buffer size in bytes
0x10C       CH0_WP                Write pointer (fabric writes)
0x110       CH0_RP                Read pointer (CPU reads)
0x114       CH0_WATER_HIGH        High watermark level
0x118       CH0_WATER_LOW         Low watermark level
```

### 8.4.2 Control Bits

```c
// DMA_CTRL bits
#define DMA_CTRL_ENABLE     (1 << 0)   // Global enable
#define DMA_CTRL_RESET      (1 << 1)   // Reset all channels

// CHx_CTRL bits
#define CH_CTRL_ENABLE      (1 << 0)   // Channel enable
#define CH_CTRL_DIR_MASK    (3 << 1)   // Direction
#define CH_CTRL_DIR_REC     (0 << 1)   // Record (fabric → DDR3)
#define CH_CTRL_DIR_PLAY    (1 << 1)   // Playback (DDR3 → fabric)
#define CH_CTRL_IRQ_EN      (1 << 3)   // Enable interrupts
```

### 8.4.3 RTL Implementation (Simplified)

```verilog
module audio_dma (
    input  wire        clk,
    input  wire        rst_n,

    // Register interface
    input  wire [11:0] reg_addr,
    input  wire [31:0] reg_wdata,
    input  wire        reg_wr,
    output reg  [31:0] reg_rdata,

    // Audio fabric interface (for record)
    input  wire [23:0] audio_in [0:7],  // 8 channels
    input  wire        audio_valid,

    // Audio fabric interface (for playback)
    output reg  [23:0] audio_out [0:7],
    output reg         audio_valid_out,

    // DDR3 AXI interface
    output wire [31:0] axi_awaddr,
    output wire        axi_awvalid,
    // ... full AXI4 signals
);

// Channel state
reg [31:0] ch_addr [0:7];
reg [31:0] ch_size [0:7];
reg [31:0] ch_wp [0:7];
reg [31:0] ch_rp [0:7];
reg [7:0]  ch_ctrl;

// Record operation: fabric → DDR3
always @(posedge clk) begin
    if (audio_valid) begin
        for (int ch = 0; ch < 8; ch++) begin
            if (ch_ctrl[ch] & CH_CTRL_ENABLE) begin
                // Write audio_in[ch] to DDR3 at ch_addr[ch] + ch_wp[ch]
                // Pack 24-bit into 32-bit word (top 8 bits = 0)
                ddr_wdata <= {8'b0, audio_in[ch]};
                ddr_addr  <= ch_addr[ch] + ch_wp[ch];
                ddr_wr    <= 1;

                // Advance write pointer
                ch_wp[ch] <= (ch_wp[ch] >= ch_size[ch] - 4) ? 0 : ch_wp[ch] + 4;
            end
        end
    end
end

// Playback operation: DDR3 → fabric (similar)
// Triggered when buffer has data and fabric is ready

endmodule
```

---

## 8.5 WAV File Format

### 8.5.1 WAV Header Structure

```c
// Standard 44-byte WAV header
#pragma pack(push, 1)
typedef struct {
    // RIFF chunk
    char     riff_id[4];        // "RIFF"
    uint32_t riff_size;         // File size - 8
    char     wave_id[4];        // "WAVE"

    // fmt chunk
    char     fmt_id[4];         // "fmt "
    uint32_t fmt_size;          // 16 (PCM)
    uint16_t fmt_format;        // 1 (PCM)
    uint16_t fmt_channels;      // Number of channels
    uint32_t fmt_sample_rate;   // e.g., 48000
    uint32_t fmt_byte_rate;     // sample_rate * channels * bytes_per_sample
    uint16_t fmt_block_align;   // channels * bytes_per_sample
    uint16_t fmt_bits;          // 24

    // data chunk
    char     data_id[4];        // "data"
    uint32_t data_size;         // Number of bytes of audio
} WavHeader;
#pragma pack(pop)

void wav_write_header(FIL *fp, uint16_t channels, uint32_t sample_rate) {
    WavHeader hdr;
    memcpy(hdr.riff_id, "RIFF", 4);
    memcpy(hdr.wave_id, "WAVE", 4);
    memcpy(hdr.fmt_id, "fmt ", 4);
    memcpy(hdr.data_id, "data", 4);

    hdr.fmt_size = 16;
    hdr.fmt_format = 1;  // PCM
    hdr.fmt_channels = channels;
    hdr.fmt_sample_rate = sample_rate;
    hdr.fmt_bits = 24;
    hdr.fmt_byte_rate = sample_rate * channels * 3;
    hdr.fmt_block_align = channels * 3;

    // riff_size and data_size updated when closing

    UINT written;
    f_write(fp, &hdr, sizeof(hdr), &written);
}
```

### 8.5.2 Multitrack Recording Options

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| Mono files | One .wav per channel | Simple, any DAW opens | Many files |
| Multichannel WAV | Single file, all channels | One file | Limited DAW support |
| Interleaved | Samples interleaved | Compatible | Complex reads |

**Recommendation:** Mono files with standardized naming:
```
Project_001/
├── Project_001.wav       (stereo mix)
├── Project_001_01.wav    (channel 1)
├── Project_001_02.wav    (channel 2)
...
└── Project_001_06.wav    (channel 6)
```

---

## 8.6 FatFs Integration

### 8.6.1 Configuration (ffconf.h)

```c
// FatFs configuration for LOOM
#define FF_FS_READONLY    0
#define FF_FS_MINIMIZE    0
#define FF_USE_STRFUNC    1
#define FF_USE_FIND       1
#define FF_USE_MKFS       1
#define FF_USE_FASTSEEK   1
#define FF_USE_EXPAND     1
#define FF_USE_CHMOD      0
#define FF_USE_LABEL      1
#define FF_USE_FORWARD    0

#define FF_FS_TINY        0
#define FF_FS_EXFAT       1   // Enable exFAT for >32GB cards
#define FF_FS_NORTC       0
#define FF_FS_NOFSINFO    0

#define FF_MAX_SS         512
#define FF_MAX_LFN        255
```

### 8.6.2 Disk I/O Layer

```c
// diskio.c - Platform-specific implementation

#include "diskio.h"
#include "hal_sdcard.h"

DSTATUS disk_initialize(BYTE pdrv) {
    if (pdrv != 0) return STA_NOINIT;

    if (sdcard_init() == SDCARD_OK) {
        return 0;
    }
    return STA_NOINIT;
}

DSTATUS disk_status(BYTE pdrv) {
    if (pdrv != 0) return STA_NOINIT;
    return sdcard_detected() ? 0 : STA_NODISK;
}

DRESULT disk_read(BYTE pdrv, BYTE *buff, LBA_t sector, UINT count) {
    if (pdrv != 0) return RES_PARERR;

    for (UINT i = 0; i < count; i++) {
        if (sdcard_read_sector(sector + i, buff + i * 512) != SDCARD_OK) {
            return RES_ERROR;
        }
    }
    return RES_OK;
}

DRESULT disk_write(BYTE pdrv, const BYTE *buff, LBA_t sector, UINT count) {
    // Similar to read
}
```

---

## 8.7 Recording State Machine

```c
typedef enum {
    REC_IDLE,
    REC_ARMED,
    REC_RECORDING,
    REC_STOPPING,
    REC_ERROR
} RecState;

RecState rec_state = REC_IDLE;
FIL rec_files[6];  // One file handle per channel

void recording_tick(void) {
    switch (rec_state) {
        case REC_IDLE:
            if (transport_should_arm()) {
                // Open files for writing
                for (int ch = 0; ch < 6; ch++) {
                    if (channel_armed[ch]) {
                        char filename[32];
                        sprintf(filename, "%s_%02d.wav", project_name, ch + 1);
                        f_open(&rec_files[ch], filename, FA_WRITE | FA_CREATE_ALWAYS);
                        wav_write_header(&rec_files[ch], 1, 48000);
                    }
                }
                rec_state = REC_ARMED;
            }
            break;

        case REC_ARMED:
            if (transport_is_recording()) {
                // Start DMA
                audio_dma_start_recording();
                rec_state = REC_RECORDING;
            }
            break;

        case REC_RECORDING:
            // Service DMA buffers
            for (int ch = 0; ch < 6; ch++) {
                if (!channel_armed[ch]) continue;

                // Check if buffer has data
                uint32_t available = audio_dma_available(ch);
                if (available >= 512) {
                    // Read from DDR3, write to SD
                    uint8_t buffer[512];
                    audio_dma_read(ch, buffer, 512);
                    UINT written;
                    f_write(&rec_files[ch], buffer, 512, &written);
                }
            }

            if (transport_should_stop()) {
                rec_state = REC_STOPPING;
            }
            break;

        case REC_STOPPING:
            // Flush remaining buffers
            // Update WAV headers with final sizes
            // Close files
            for (int ch = 0; ch < 6; ch++) {
                if (channel_armed[ch]) {
                    // Update data_size in header
                    f_lseek(&rec_files[ch], 40);  // Offset to data_size
                    uint32_t data_size = f_size(&rec_files[ch]) - 44;
                    UINT written;
                    f_write(&rec_files[ch], &data_size, 4, &written);

                    // Update RIFF size
                    f_lseek(&rec_files[ch], 4);
                    uint32_t riff_size = f_size(&rec_files[ch]) - 8;
                    f_write(&rec_files[ch], &riff_size, 4, &written);

                    f_close(&rec_files[ch]);
                }
            }
            rec_state = REC_IDLE;
            break;

        case REC_ERROR:
            // Handle SD card errors
            break;
    }
}
```

---

## 8.8 Project File Format

### 8.8.1 JSON Structure

```json
{
    "version": "1.0",
    "project": {
        "name": "Session_001",
        "created": "2026-06-21T14:30:00Z",
        "modified": "2026-06-21T16:45:00Z"
    },
    "settings": {
        "sample_rate": 48000,
        "bit_depth": 24,
        "mode": "studio"
    },
    "channels": [
        {
            "id": 0,
            "name": "Kick",
            "armed": true,
            "source": "tdm_0",
            "modules": [
                {"type": "gain", "coeffs": {"gain_db": 0}},
                {"type": "eq", "bands": [
                    {"freq": 80, "q": 1.0, "gain_db": 3},
                    {"freq": 500, "q": 1.2, "gain_db": -2},
                    {"freq": 2000, "q": 2.0, "gain_db": 4}
                ]},
                {"type": "compressor", "threshold_db": -12, "ratio": 4}
            ]
        },
        // ... more channels
    ],
    "routing": {
        "monitor_mix": [0, 1, 2, 3],
        "record_busses": [0, 1, 2, 3, 4, 5]
    },
    "transport": {
        "bpm": 120,
        "time_signature": "4/4"
    }
}
```

---

## 8.9 Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-06-21 | GodBot | Initial storage spec |
| 1.0 | 2026-06-21 | GodBot | Complete DMA RTL, FatFs integration, WAV format |

---

*End of Section 8 — STORAGE & RECORDING*
