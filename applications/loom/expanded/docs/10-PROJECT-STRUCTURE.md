# OPUS MAXIMUS / LOOM — Section 10: PROJECT STRUCTURE

**Document ID:** OPUS-10-PROJECT-STRUCTURE  
**Version:** 1.0 — Implementation Ready  
**Date:** 2026-06-21  
**Author:** GodBot 🜂 for codecbox

---

## 10.1 Directory Tree

```
loom/
├── docs/                          # Design documentation (this set)
│   ├── 00-VISION.md
│   ├── 01-PRODUCT-SPEC.md
│   ├── 02-SYSTEM-ARCHITECTURE.md
│   ├── 03-FPGA-AUDIO-FABRIC.md
│   ├── 04-DSP-MODULE-LIBRARY.md
│   ├── 05-INSTRUMENT-SEPARATOR.md
│   ├── 06-CONTROL-PLANE.md
│   ├── 07-GUI-DISPLAY-TOUCH.md
│   ├── 08-STORAGE-RECORDING.md
│   ├── 09-RESOURCE-BUDGET.md
│   ├── 10-PROJECT-STRUCTURE.md
│   ├── 11-BUILD-PLAN.md
│   └── images/                    # Diagrams, screenshots
│       └── system_block_diagram.png
│
├── hardware/                      # FPGA hardware design
│   ├── vivado/                    # Vivado project files
│   │   ├── loom.xpr               # Project file
│   │   ├── loom.tcl               # Project creation script
│   │   ├── constraints/
│   │   │   └── loom.xdc           # Pin constraints, timing
│   │   ├── bd/                    # Block design (if used)
│   │   │   └── design_1.tcl
│   │   └── tcl/
│   │       ├── build_bitstream.tcl
│   │       └── program_device.tcl
│   │
│   ├── rtl/                       # Verilog source
│   │   ├── dsp_core/              # Software-defined DSP
│   │   │   ├── dsp_core.v
│   │   │   ├── dsp_sequencer.v
│   │   │   ├── dsp_mac_lane.v
│   │   │   └── dsp_coeff_ram.v
│   │   │
│   │   ├── tdm_io/                # Audio codec interface
│   │   │   ├── tdm_rx.v
│   │   │   ├── tdm_tx.v
│   │   │   └── tdm_clk_gen.v
│   │   │
│   │   ├── display_ctrl/          # ILI9341 controller
│   │   │   ├── ili9341_controller.v
│   │   │   ├── display_dma.v
│   │   │   └── spi_master.v
│   │   │
│   │   ├── touch_ctrl/            # XPT2046 controller
│   │   │   └── xpt2046_controller.v
│   │   │
│   │   ├── audio_dma/             # Audio-DDR3 DMA
│   │   │   └── audio_dma.v
│   │   │
│   │   ├── neorv32/               # CPU wrapper
│   │   │   └── neorv32_wrapper.v
│   │   │
│   │   └── top/                   # Top-level
│   │       ├── loom_top.v
│   │       └── system_reset.v
│   │
│   ├── hls/                       # High-level synthesis
│   │   ├── separator/
│   │   │   ├── alpha_delta.cpp
│   │   │   ├── histogram.cpp
│   │   │   └── mask_gen.cpp
│   │   │
│   │   └── reverb/
│   │       └── convolution_reverb.cpp
│   │
│   └── ip/                        # Xilinx IP configurations
│       ├── clk_wiz_0/             # Clock generation
│       ├── mig_7series_0/         # DDR3 controller
│       ├── xfft_0/                # FFT for separator
│       └── xlconstant_0.xci       # Constants
│
├── firmware/                      # NEORV32 firmware
│   ├── Makefile
│   ├── linker/
│   │   └── loom.ld                # Linker script
│   │
│   ├── src/
│   │   ├── main.c                 # Entry point
│   │   │
│   │   ├── app/                   # Application layer
│   │   │   ├── gui.c
│   │   │   ├── gui.h
│   │   │   ├── transport.c
│   │   │   ├── transport.h
│   │   │   ├── project.c
│   │   │   ├── project.h
│   │   │   ├── tabs/
│   │   │   │   ├── tab_inputs.c
│   │   │   │   ├── tab_mix.c
│   │   │   │   ├── tab_output.c
│   │   │   │   ├── tab_master.c
│   │   │   │   └── tab_library.c
│   │   │   │
│   │   │   └── widgets/
│   │   │       ├── button.c
│   │   │       ├── fader.c
│   │   │       ├── meter.c
│   │   │       └── knob.c
│   │   │
│   │   ├── services/              # Business logic
│   │   │   ├── mixer.c
│   │   │   ├── mixer.h
│   │   │   ├── recorder.c
│   │   │   ├── recorder.h
│   │   │   ├── separator_ctrl.c
│   │   │   └── separator_ctrl.h
│   │   │
│   │   ├── hal/                     # Hardware abstraction
│   │   │   ├── hal_dsp.c
│   │   │   ├── hal_dsp.h
│   │   │   ├── hal_display.c
│   │   │   ├── hal_display.h
│   │   │   ├── hal_touch.c
│   │   │   ├── hal_touch.h
│   │   │   ├── hal_codec.c
│   │   │   ├── hal_codec.h
│   │   │   ├── hal_sdcard.c
│   │   │   ├── hal_sdcard.h
│   │   │   ├── hal_ddr.c
│   │   │   └── hal_ddr.h
│   │   │
│   │   └── startup/
│   │       └── crt0.S               # Boot assembly
│   │
│   └── lib/                         # Third-party libraries
│       ├── neorv32/                 # RISC-V core BSP
│       │   ├── neorv32.h
│       │   └── ...
│       └── fatfs/                   # FatFs file system
│           ├── ff.c
│           ├── ff.h
│           ├── diskio.c
│           └── ffconf.h
│
├── models/                          # Golden reference models
│   ├── dsp_modules/                 # Bit-accurate DSP
│   │   ├── __init__.py
│   │   ├── fixedpoint.py
│   │   ├── gain.py
│   │   ├── eq.py
│   │   ├── compressor.py
│   │   ├── limiter.py
│   │   ├── gate.py
│   │   ├── delay.py
│   │   └── pan.py
│   │
│   ├── separator/                     # DUET algorithm
│   │   ├── duet.py
│   │   ├── stft.py
│   │   ├── clustering.py
│   │   └── test_recordings/
│   │       └── stereo_test.wav
│   │
│   ├── test/
│   │   ├── generate_vectors.py
│   │   ├── verify_rtl.py
│   │   └── compare_wav.py
│   │
│   └── requirements.txt
│
├── test/                              # Testbenches & tests
│   ├── hardware/
│   │   ├── dsp_core_tb/
│   │   │   ├── dsp_core_tb.v
│   │   │   └── run_sim.sh
│   │   ├── tdm_tb/
│   │   │   └── tdm_tb.v
│   │   └── display_tb/
│   │       └── display_tb.v
│   │
│   ├── firmware/
│   │   ├── test_hal.c
│   │   └── test_dsp.c
│   │
│   └── golden_vectors/
│       ├── gain_in.hex
│       ├── gain_out.hex
│       └── gain_coeff.hex
│
├── tools/                             # Build & utility scripts
│   ├── build_hardware.sh
│   ├── build_firmware.sh
│   ├── program_fpga.sh
│   ├── program_flash.sh
│   ├── generate_golden.py
│   ├── calibrate_touch.py
│   ├── export_wav.py
│   └── project.profile.json           # Hardware-debug MCP profile
│
├── sim/                               # Simulation working dir
│   └── work/
│
├── build/                             # Build outputs (gitignored)
│   ├── hardware/
│   │   ├── bitstream.bit
│   │   ├── bitstream.bin
│   │   └── loom.runs/
│   └── firmware/
│       ├── loom.elf
│       ├── loom.hex
│       └── loom.bin
│
├── docs-generated/                    # Auto-generated docs
│   └── register_map.html
│
├── CHANGELOG.md
├── LICENSE
└── README.md
```

---

## 10.2 Key Files Reference

### 10.2.1 Documentation

| File | Purpose |
|------|---------|
| `docs/*.md` | Complete design specification (12 sections) |
| `docs/images/*` | Block diagrams, waveforms, UI mockups |

### 10.2.2 Hardware RTL

| File | Description |
|------|-------------|
| `loom_top.v` | Top-level module, instantiates everything |
| `dsp_core.v` | Main DSP engine |
| `ili9341_controller.v` | Display controller |
| `tdm_rx.v` / `tdm_tx.v` | CS42448 interface |

### 10.2.3 Firmware

| File | Description |
|------|-------------|
| `main.c` | Startup, main loop |
| `gui.c` | Immediate-mode GUI framework |
| `hal_dsp.c` | DSP core driver |
| `hal_display.c` | ILI9341 driver |
| `hal_codec.c` | CS42448 I²C driver |

### 10.2.4 Models

| File | Description |
|------|-------------|
| `fixedpoint.py` | Q-format utilities |
| `dsp_modules/*.py` | Golden reference implementations |
| `duet.py` | Separation algorithm reference |

---

## 10.3 Build Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        BUILD FLOW                                │
│                                                                 │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐                  │
│  │ RTL Src  │───▶│ Vivado   │───▶│ Bitstream│                  │
│  │          │    │ Synthesis│    │ .bit     │                  │
│  └──────────┘    │ P&R      │    └────┬─────┘                  │
│                  └──────────┘         │                         │
│                                     ▼                         │
│                            ┌──────────────┐                   │
│                            │ Program FPGA │                   │
│                            │ via JTAG     │                   │
│                            └──────────────┘                   │
│                                                                 │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐                  │
│  │ C Src    │───▶│ GCC      │───▶│ .hex     │                  │
│  │          │    │ RISC-V   │    │ Firmware │                  │
│  └──────────┘    │          │    └────┬─────┘                  │
│                  └──────────┘         │                         │
│                                     ▼                         │
│                            ┌──────────────┐                   │
│                            │ Flash via    │                   │
│                            │ OpenOCD      │                   │
│                            └──────────────┘                   │
│                                                                 │
│  ┌──────────┐    ┌──────────┐                                  │
│  │ Python   │───▶│ Test     │                                  │
│  │ Models   │    │ Vectors  │                                  │
│  └──────────┘    └────┬─────┘                                  │
│                      │                                         │
│                      ▼                                         │
│               ┌──────────────┐                                 │
│               │ Verify RTL   │                                 │
│               │ Matches      │                                 │
│               │ Golden       │                                 │
│               └──────────────┘                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 10.4 Version Control

### 10.4.1 .gitignore

```
# Vivado
*.cache/
*.runs/
*.sim/
*.hw/
*.ip_user_files/
*.str
vivado*.jou
vivado*.log

# Build outputs
build/
*.bit
*.bin
*.elf
*.hex

# Python
__pycache__/
*.pyc
.venv/

# Simulation
sim/work/
*.vcd
*.wdb

# IDE
.vscode/
.idea/
*.swp
*~
```

### 10.4.2 Git Workflow

```bash
# Feature branch workflow
git checkout -b feature/dsp-core
git commit -m "Add DSP core sequencer"
git push origin feature/dsp-core
# Open PR, review, merge
```

---

## 10.5 MCP Hardware Debug Profile

```json
{
    "profile": {
        "name": "loom-hardware-debug",
        "target": "arty-a7-100t",
        "debugger": {
            "type": "openocd",
            "interface": "jlink",
            "target": "neorv32"
        },
        "memory_map": {
            "boot_rom": "0x00000000-0x00007FFF",
            "iram": "0x00008000-0x0000FFFF",
            "dram": "0x00010000-0x00017FFF",
            "ddr3": "0x40000000-0x4FFFFFFF"
        },
        "peripherals": {
            "dsp_core": "0x60000000",
            "tdm_io": "0x60001000",
            "audio_dma": "0x60002000",
            "display": "0x60003000",
            "touch": "0x60004000",
            "i2c": "0x60005000",
            "spi": "0x60006000"
        },
        "golden_vectors": {
            "path": "test/golden_vectors/",
            "format": "hex"
        },
        "diff_command": "python3 models/test/verify_rtl.py --golden {golden} --actual {actual}"
    }
}
```

---

## 10.6 Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-06-21 | GodBot | Initial project structure |
| 1.0 | 2026-06-21 | GodBot | Complete directory tree, build flow, MCP profile |

---

*End of Section 10 — PROJECT STRUCTURE*
