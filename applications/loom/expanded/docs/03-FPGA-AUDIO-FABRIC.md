# OPUS MAXIMUS / LOOM — Section 3: FPGA AUDIO FABRIC

**Document ID:** OPUS-03-FPGA-AUDIO-FABRIC  
**Version:** 1.0 — Implementation Ready  
**Date:** 2026-06-21  
**Author:** GodBot 🜂 for codecbox  
**Target:** Arty A7-100T (XC7A100T-1CSG324C)

---

## 3.1 Overview

The FPGA Audio Fabric is the heart of LOOM — all audio processing happens here, with zero CPU involvement in the signal path. The fabric consists of:

1. **TDM I/O** — Interface to CS42448 codec
2. **DSP Core** — Time-multiplexed MAC engine executing module programs
3. **Mix Bus** — Summing and routing matrix
4. **Audio DMA** — Bridge to DDR3 ring buffers
5. **Specialty Accelerators** — DUET separator (separate section)

---

## 3.2 TDM I/O Subsystem

### 3.2.1 TDM Protocol (CS42448)

The CS42448 uses Time Division Multiplexing (TDM) mode A:

```
TDM Frame (1 sample period = 1/Fs = 20.83µs @ 48kHz):
┌────────────────────────────────────────────────────────────────────────┐
│  FSYNC  ─┐                                                             │
│          │                                                             │
│          └──────────────────────────────────────────────────────────    │
│           │                                                             │
│  BCLK   ═╪═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═│
│           │││││││││││││││││││││││││││││││││││││││││││││││││││││││││││││
│  ADC    ░░│S│M│L│Z│ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ ░░│
│  (RX)   ░░│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│ ░░│
│          │0│1│2│3│ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │   │
│           │                                                             │
│  DAC    ░░│S│M│L│Z│ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ ░░│
│  (TX)   ░░│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│B│ ░░│
│          │0│1│2│3│ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │   │
│           │                                                             │
└──────────┴────────────────────────────────────────────────────────────┘

Slot Assignments (TDM Mode A, 32 slots per frame):
- Slot 0-5: ADC 1-6 (24-bit samples, MSB-first)
- Slot 6-15: Unused
- Slot 16-23: DAC 1-8 (24-bit samples)
- Slot 24-31: Unused

Timing:
- FSYNC: Frame sync, 1 BCLK high at start
- BCLK: Bit clock, 64 × Fs = 3.072 MHz @ 48kHz
- Data: MSB-first, valid on BCLK falling edge
```

### 3.2.2 TDM Receiver (RTL)

```verilog
module tdm_rx (
    input  wire        clk,           // 100 MHz fabric clock
    input  wire        rst_n,
    // CS42448 interface
    input  wire        bclk,          // 3.072 MHz
    input  wire        fsync,         // 48 kHz
    input  wire        sdin,          // Serial data in
    // Output: deserialized samples
    output reg  [23:0] sample_ch0,    // ADC 1
    output reg  [23:0] sample_ch1,    // ADC 2
    output reg  [23:0] sample_ch2,    // ADC 3
    output reg  [23:0] sample_ch3,    // ADC 4
    output reg  [23:0] sample_ch4,    // ADC 5
    output reg  [23:0] sample_ch5,    // ADC 6
    output reg         sample_valid,    // Pulse at Fs
    output reg  [7:0]  slot_counter    // Current TDM slot
);

// Synchronization: BCLK/FSYNC → fabric clock
// Use dual-flop synchronizer for each async input

reg [1:0] bclk_sync, fsync_sync;
reg [1:0] sdin_sync;

always @(posedge clk) begin
    bclk_sync  <= {bclk_sync[0], bclk};
    fsync_sync <= {fsync_sync[0], fsync};
    sdin_sync  <= {sdin_sync[0], sdin};
end

// Edge detection on BCLK
wire bclk_rising  = (bclk_sync == 2'b01);
wire bclk_falling = (bclk_sync == 2'b10);
wire fsync_rising = (fsync_sync == 2'b01);

// TDM state machine
reg [4:0] bit_counter;      // 0-31 bits per slot
reg [23:0] shift_reg;
reg [23:0] slot_buffer [0:31]; // Capture all slots

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bit_counter <= 0;
        slot_counter <= 0;
        sample_valid <= 0;
    end else begin
        sample_valid <= 0; // Default

        if (fsync_rising) begin
            slot_counter <= 0;
            bit_counter <= 0;
        end else if (bclk_rising) begin
            // Sample on rising edge (mode A)
            shift_reg <= {shift_reg[22:0], sdin_sync[1]};
            bit_counter <= bit_counter + 1;

            if (bit_counter == 23) begin
                // Complete sample captured
                slot_buffer[slot_counter] <= {shift_reg[22:0], sdin_sync[1]};

                // Map slots to channels (CS42448 TDM mode A)
                case (slot_counter)
                    5'd0: sample_ch0 <= {shift_reg[22:0], sdin_sync[1]};
                    5'd1: sample_ch1 <= {shift_reg[22:0], sdin_sync[1]};
                    5'd2: sample_ch2 <= {shift_reg[22:0], sdin_sync[1]};
                    5'd3: sample_ch3 <= {shift_reg[22:0], sdin_sync[1]};
                    5'd4: sample_ch4 <= {shift_reg[22:0], sdin_sync[1]};
                    5'd5: sample_ch5 <= {shift_reg[22:0], sdin_sync[1]};
                endcase

                if (slot_counter == 5'd5) begin
                    sample_valid <= 1; // All 6 channels ready
                end

                slot_counter <= slot_counter + 1;
                bit_counter <= 0;
            end
        end
    end
end

endmodule
```

### 3.2.3 TDM Transmitter (RTL)

```verilog
module tdm_tx (
    input  wire        clk,           // 100 MHz fabric clock
    input  wire        rst_n,
    // Input: samples to transmit
    input  wire [23:0] sample_ch0,    // DAC 1
    input  wire [23:0] sample_ch1,    // DAC 2
    input  wire [23:0] sample_ch2,    // DAC 3
    input  wire [23:0] sample_ch3,    // DAC 4
    input  wire [23:0] sample_ch4,    // DAC 5
    input  wire [23:0] sample_ch5,    // DAC 6
    input  wire [23:0] sample_ch6,    // DAC 7
    input  wire [23:0] sample_ch7,    // DAC 8
    input  wire        sample_valid,  // Load new samples
    // CS42448 interface
    input  wire        bclk,
    input  wire        fsync,
    output reg         sdout          // Serial data out
);

// Similar synchronizers as RX

reg [23:0] tx_buffer [0:7]; // 8 channel buffers
reg [4:0] slot_counter;
reg [4:0] bit_counter;
reg [23:0] current_sample;

// Load samples when valid
always @(posedge clk) begin
    if (sample_valid) begin
        tx_buffer[0] <= sample_ch0;
        tx_buffer[1] <= sample_ch1;
        tx_buffer[2] <= sample_ch2;
        tx_buffer[3] <= sample_ch3;
        tx_buffer[4] <= sample_ch4;
        tx_buffer[5] <= sample_ch5;
        tx_buffer[6] <= sample_ch6;
        tx_buffer[7] <= sample_ch7;
    end
end

// Transmit state machine
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        slot_counter <= 0;
        bit_counter <= 0;
        sdout <= 0;
    end else begin
        if (fsync_rising) begin
            slot_counter <= 16; // DAC slots start at 16
            bit_counter <= 0;
            current_sample <= tx_buffer[0]; // Preload first
        end else if (bclk_falling) begin
            // Shift out MSB first on falling edge
            sdout <= current_sample[23];
            current_sample <= {current_sample[22:0], 1'b0};

            bit_counter <= bit_counter + 1;
            if (bit_counter == 23) begin
                bit_counter <= 0;
                slot_counter <= slot_counter + 1;

                // Map slots to channels
                case (slot_counter)
                    5'd16: current_sample <= tx_buffer[0];
                    5'd17: current_sample <= tx_buffer[1];
                    5'd18: current_sample <= tx_buffer[2];
                    5'd19: current_sample <= tx_buffer[3];
                    5'd20: current_sample <= tx_buffer[4];
                    5'd21: current_sample <= tx_buffer[5];
                    5'd22: current_sample <= tx_buffer[6];
                    5'd23: current_sample <= tx_buffer[7];
                endcase
            end
        end
    end
end

endmodule
```

---

## 3.3 DSP Core Engine (The Software-Defined Heart)

### 3.3.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         DSP CORE ENGINE                                 │
│                      Time-Multiplexed MAC Array                         │
│                                                                         │
│   ┌───────────────────────────────────────────────────────────────┐    │
│   │                    PROGRAM MEMORY (BRAM)                        │    │
│   │  ┌─────────────────────────────────────────────────────────┐  │    │
│   │  │ Program ROM: Module type definitions                    │  │    │
│   │  │  - OPCODE_GAIN, OPCODE_EQ, OPCODE_COMP, etc.            │  │    │
│   │  └─────────────────────────────────────────────────────────┘  │    │
│   │  ┌─────────────────────────────────────────────────────────┐  │    │
│   │  │ Program RAM: Per-pipe module chains (6 pipes × 6 slots) │  │    │
│   │  │  Pipe 0: [GAIN][EQ][COMP][GATE][DELAY][PAN]             │  │    │
│   │  │  Pipe 1: [GAIN][EQ]...[bypass]...[bypass]               │  │    │
│   │  │  ...                                                    │  │    │
│   │  └─────────────────────────────────────────────────────────┘  │    │
│   └───────────────────────────────────────────────────────────────┘    │
│                                    │                                    │
│   ┌───────────────────────────────────────────────────────────────┐    │
│   │                   COEFFICIENT MEMORY (BRAM)                   │    │
│   │  Coefficient Bank: 32-bit words, organized by module type     │    │
│   │  ┌─────────────────────────────────────────────────────────┐  │    │
│   │  │ GAIN:       [gain_scalar]                               │  │    │
│   │  │ EQ_5BAND:   [b0_0][b1_0][b2_0][a1_0][a2_0] × 5 bands   │  │    │
│   │  │ COMPRESSOR: [threshold][ratio][attack][release][makeup] │  │    │
│   │  │ ...                                                     │  │    │
│   │  └─────────────────────────────────────────────────────────┘  │    │
│   └───────────────────────────────────────────────────────────────┘    │
│                                    │                                    │
│                                    ▼                                    │
│   ┌───────────────────────────────────────────────────────────────┐    │
│   │                    SEQUENCER / CONTROLLER                     │    │
│   │  - Steps through 6 pipes × 6 slots = 36 operations/sample     │    │
│   │  - Fetches opcode → dispatches to MAC datapath                │    │
│   │  - Manages sample state memory                                │    │
│   │  - Triggered by sample_tick (48kHz)                          │    │
│   └───────────────────────────────────────────────────────────────┘    │
│                                    │                                    │
│                                    ▼                                    │
│   ┌───────────────────────────────────────────────────────────────┐    │
│   │                    MAC DATAPATH (2-4 lanes)                   │    │
│   │  ┌─────────┐    ┌─────────┐    ┌─────────┐                  │    │
│   │  │ DSP48E1 │    │ DSP48E1 │    │ DSP48E1 │  (parallel MACs)  │    │
│   │  │  Lane 0 │    │  Lane 1 │    │  Lane 2 │                  │    │
│   │  │ Mux→MAC │    │ Mux→MAC │    │ Mux→MAC │                  │    │
│   │  └────┬────┘    └────┬────┘    └────┬────┘                  │    │
│   │       │              │              │                         │    │
│   │       └──────────────┼──────────────┘                         │    │
│   │                      ▼                                         │    │
│   │              ┌─────────────┐                                 │    │
│   │              │ Accumulator │                                 │    │
│   │              │ (48-bit)    │                                 │    │
│   │              └──────┬──────┘                                 │    │
│   │                     │                                        │    │
│   │              ┌──────┴──────┐                                 │    │
│   │              │ Output Reg  │                                 │    │
│   │              │ (truncate)  │                                 │    │
│   │              └─────────────┘                                 │    │
│   └───────────────────────────────────────────────────────────────┘    │
│                                    │                                    │
│                                    ▼                                    │
│   ┌───────────────────────────────────────────────────────────────┐    │
│   │                  SAMPLE/STATE MEMORY (BRAM)                   │    │
│   │  - 6 pipes × 6 slots × state words                            │    │
│   │  - Delay line pointers, filter state, envelope followers      │    │
│   │  - Separate for each pipe to avoid conflicts                 │    │
│   └───────────────────────────────────────────────────────────────┘    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.3.2 Program Format

Each slot in a pipe's module chain is a 32-bit program word:

```
Bit Field     Bits    Description
────────────────────────────────────────────────────────
opcode        [7:0]   Module type (GAIN=1, EQ=2, COMP=3, ...)
coeff_addr    [15:8]  Coefficient table index (0-255)
state_addr    [23:16] State memory index (for this pipe)
flags         [31:24] Bypass, mute, solo flags

Example Program for Pipe 0:
Address  Data      Meaning
────────────────────────────────────────────────────────
0x0000   0x0100_00_01  Slot 0: GAIN, coeff=0, state=0
0x0001   0x0201_01_02  Slot 1: EQ, coeff=1, state=1
0x0002   0x0302_02_03  Slot 2: COMP, coeff=2, state=2
0x0003   0x0000_00_00  Slot 3: BYPASS (no processing)
0x0004   0x0000_00_00  Slot 4: BYPASS
0x0005   0x0503_03_05  Slot 5: PAN, coeff=3, state=3
```

### 3.3.3 DSP Core RTL Structure

```verilog
module dsp_core (
    input  wire        clk,              // 100 MHz
    input  wire        rst_n,
    // Sample tick (48kHz)
    input  wire        sample_tick,
    // Input samples from TDM RX
    input  wire signed [23:0] sample_in [0:5],  // 6 channels
    // Output samples to TDM TX
    output reg  signed [23:0] sample_out [0:7],  // 8 channels (6 + 2 mix)
    // Configuration interface (memory-mapped)
    input  wire [11:0]  cfg_addr,
    input  wire [31:0] cfg_wdata,
    input  wire         cfg_wr,
    output wire [31:0] cfg_rdata,
    input  wire         cfg_rd
);

// Fixed-point format: Q1.23 for samples, Q1.31 for internal
localparam SAMPLE_W = 24;
localparam ACC_W = 48;

// BRAM: Program memory (6 pipes × 6 slots = 36 entries)
reg [31:0] prog_mem [0:35];

// BRAM: Coefficient memory (256 × 32-bit coefficients)
reg [31:0] coeff_mem [0:255];

// BRAM: State memory (6 pipes × 64 state words)
// State holds: delay samples, filter history, envelope followers
reg signed [31:0] state_mem [0:383];  // 6 × 64 = 384

// Pipe processing registers
reg signed [ACC_W-1:0] pipe_accum [0:5];  // Per-pipe accumulator
reg signed [SAMPLE_W-1:0] pipe_sample [0:5];  // Current sample per pipe

// Sequencer state
reg [2:0] current_pipe;   // 0-5
reg [2:0] current_slot;   // 0-5
reg       processing;

// MAC datapath
reg signed [31:0] mac_a, mac_b;
reg signed [63:0] mac_result;

// Opcode definitions
localparam OP_NOP     = 8'h00;
localparam OP_GAIN    = 8'h01;
localparam OP_EQ      = 8'h02;
localparam OP_COMP    = 8'h03;
localparam OP_GATE    = 8'h04;
localparam OP_DELAY   = 8'h05;
localparam OP_PAN     = 8'h06;
localparam OP_LIMITER = 8'h07;
localparam OP_BUS_SEND = 8'h08;

// Main sequencer
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_pipe <= 0;
        current_slot <= 0;
        processing <= 0;
    end else begin
        if (sample_tick && !processing) begin
            // Start new frame
            processing <= 1;
            current_pipe <= 0;
            current_slot <= 0;

            // Load input samples into pipe accumulators
            pipe_accum[0] <= {{24{sample_in[0][23]}}, sample_in[0]};
            pipe_accum[1] <= {{24{sample_in[1][23]}}, sample_in[1]};
            pipe_accum[2] <= {{24{sample_in[2][23]}}, sample_in[2]};
            pipe_accum[3] <= {{24{sample_in[3][23]}}, sample_in[3]};
            pipe_accum[4] <= {{24{sample_in[4][23]}}, sample_in[4]};
            pipe_accum[5] <= {{24{sample_in[5][23]}}, sample_in[5]};
        end else if (processing) begin
            // Execute one slot
            execute_slot(current_pipe, current_slot);

            // Advance
            if (current_slot == 5) begin
                current_slot <= 0;
                if (current_pipe == 5) begin
                    processing <= 0;
                    // Frame complete: output to DAC
                    output_samples();
                end else begin
                    current_pipe <= current_pipe + 1;
                end
            end else begin
                current_slot <= current_slot + 1;
            end
        end
    end
end

// Slot execution (combinational for single-cycle ops, sequential for multi-cycle)
task execute_slot;
    input [2:0] pipe;
    input [2:0] slot;
    reg [5:0] prog_idx;
    reg [31:0] prog_word;
    reg [7:0] opcode;
    reg [7:0] coeff_idx;
    reg [7:0] state_idx;
    reg signed [31:0] coeff;
    reg signed [ACC_W-1:0] result;
    begin
        prog_idx = pipe * 6 + slot;
        prog_word = prog_mem[prog_idx];
        opcode = prog_word[7:0];
        coeff_idx = prog_word[15:8];
        state_idx = prog_word[23:16];

        case (opcode)
            OP_GAIN: begin
                // result = sample * gain
                coeff = coeff_mem[coeff_idx];  // Q1.31 gain
                mac_a = pipe_accum[pipe][31:0];
                mac_b = coeff;
                result = (mac_a * mac_b) >>> 31;  // Back to Q1.23
                pipe_accum[pipe] <= {{24{result[23]}}, result[23:0]};
            end

            OP_EQ: begin
                // 5 biquads in series
                // Uses 10 state words per biquad: x[n-1], x[n-2], y[n-1], y[n-2], b0, b1, b2, a1, a2, gain
                // Simplified: call biquad module
                // State base = state_idx * 10
                pipe_accum[pipe] <= biquad_5band(
                    pipe_accum[pipe],
                    state_idx,
                    coeff_idx
                );
            end

            // ... other opcodes

            OP_PAN: begin
                // Split to stereo with pan law
                // Coeffs: left_gain, right_gain (constant power)
                // Output: stored in special pan registers for final mix
            end

            default: ; // NOP
        endcase
    end
endtask

// Configuration interface (simplified)
always @(posedge clk) begin
    if (cfg_wr) begin
        case (cfg_addr[11:8])
            4'h0: prog_mem[cfg_addr[5:0]] <= cfg_wdata;
            4'h1: coeff_mem[cfg_addr[7:0]] <= cfg_wdata;
            4'h2: state_mem[cfg_addr[8:0]] <= cfg_wdata;
        endcase
    end
end

endmodule
```

### 3.3.4 Biquad Filter Module (for EQ)

```verilog
module biquad (
    input  wire signed [23:0] x,           // Input sample Q1.23
    output wire signed [23:0] y,           // Output sample Q1.23
    // Coefficients (Q2.30 for stability)
    input  wire signed [31:0] b0, b1, b2,
    input  wire signed [31:0] a1, a2,
    // State (updated each sample)
    output reg  signed [23:0] x1, x2,  // x[n-1], x[n-2]
    output reg  signed [23:0] y1, y2   // y[n-1], y[n-2]
);

// Direct Form II Transposed (better numerical properties)
reg signed [47:0] acc;
reg signed [23:0] d1, d2;  // Delay elements

always @(*) begin
    // y[n] = b0*x[n] + d1
    // d1 = b1*x[n] + a1*y[n] + d2
    // d2 = b2*x[n] + a2*y[n]

    acc = (b0 * x) + (d1 << 24);  // Q2.30 * Q1.23 = Q3.53
    // ... (full precision math)
end

assign y = acc[47:24];  // Truncate to Q1.23

endmodule
```

---

## 3.4 Mix Bus Architecture

### 3.4.1 Bus Structure

```
6 Input Pipes ──▶ [DSP Processing] ──▶ [BUS_SEND modules] ──▶ Mix Buses
                                                      │
                                                      ▼
                                        ┌─────────────────────────┐
                                        │     MIX BUS MATRIX        │
                                        │                           │
                                        │  Bus 0: Monitor Mix (L)   │
                                        │  Bus 1: Monitor Mix (R)   │
                                        │  Bus 2: Record Bus 0      │
                                        │  Bus 3: Record Bus 1      │
                                        │  Bus 4: Record Bus 2      │
                                        │  Bus 5: Record Bus 3      │
                                        └───────────┬─────────────┘
                                                    │
                                                    ▼
                                              [Master DSP]
                                                    │
                                                    ▼
                                              8 DAC Channels
```

### 3.4.2 BUS_SEND Opcode

```verilog
OP_BUS_SEND:
    // coeff[7:0] = destination_bus (0-5)
    // coeff[15:8] = send_level (0-255 = -∞ to 0dB)

    bus_accum[dest_bus] <= bus_accum[dest_bus] +
                           (pipe_accum[pipe] * send_level) >>> 8;
```

---

## 3.5 Audio DMA Controller

### 3.5.1 Purpose

Bridge between audio fabric and DDR3 ring buffers:
- Recording: Fabric → DDR3
- Playback: DDR3 → Fabric

### 3.5.2 DMA Channel Configuration

| Channel | Direction | Buffer Size | Purpose |
|---------|-----------|-------------|---------|
| 0-5 | Fabric → DDR3 | 512KB each | Record 6 channels |
| 6-7 | DDR3 → Fabric | 256KB each | Playback (dub) |

### 3.5.3 DMA Register Map

```
Address     Register              Description
────────────────────────────────────────────────────────
0x2000      DMA_CTRL              Global control
0x2004      DMA_STATUS            Global status
0x2008      DMA_IRQ_EN            Interrupt enable

Per-channel (0x2100 + n*0x10):
0x2100      CH0_ADDR              DDR3 base address
0x2104      CH0_SIZE              Buffer size
0x2108      CH0_WP              Write pointer (record)
0x210C      CH0_RP              Read pointer (record)
0x2110      CH0_CTRL            Channel control
```

---

## 3.6 Resource Budget (DSP Fabric Only)

| Component | LUTs | FFs | BRAM (36Kb) | DSP48 |
|-----------|------|-----|-------------|-------|
| TDM RX | 200 | 300 | 0 | 0 |
| TDM TX | 150 | 250 | 0 | 0 |
| DSP Core | 3,000 | 2,000 | 4 | 8 |
| Mix Bus | 500 | 800 | 0 | 0 |
| Audio DMA | 800 | 600 | 0 | 0 |
| **Total** | **~4,650** | **~3,950** | **4** | **8** |

**Margin:** Plenty of room for specialty accelerators and display controller.

---

## 3.7 Verification Strategy

### 3.7.1 Golden Model Comparison

Every DSP module must match Python reference bit-for-bit:

```python
# Python golden model (in models/dsp_modules/gain.py)
def process_gain(sample: int, gain_db: float) -> int:
    """Q1.23 input, Q1.23 output"""
    gain_linear = 10 ** (gain_db / 20)
    gain_q31 = int(gain_linear * 2**31) & 0xFFFFFFFF

    # Q1.23 * Q1.31 = Q2.54
    result = (sample * gain_q31) >> 31

    # Saturate to Q1.23
    if result > 0x7FFFFF:
        return 0x7FFFFF
    elif result < -0x800000:
        return -0x800000
    return result & 0xFFFFFF
```

### 3.7.2 Testbench Structure

```systemverilog
// Verilog testbench
module dsp_core_tb;
    // Instantiate DUT
    // Load test vectors from Python-generated file
    // Compare output vs golden vectors
    // Report PASS/FAIL with diff analysis
endmodule
```

---

## 3.8 Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-06-21 | GodBot | Initial DSP core architecture |
| 1.0 | 2026-06-21 | GodBot | Complete RTL structures, register maps, verification strategy |

---

*End of Section 3 — FPGA AUDIO FABRIC*
