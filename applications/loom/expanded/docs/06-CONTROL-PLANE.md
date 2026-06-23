# OPUS MAXIMUS / LOOM — Section 6: CONTROL PLANE / NEORV32 FIRMWARE

**Document ID:** OPUS-06-CONTROL-PLANE  
**Version:** 1.0 — Implementation Ready  
**Date:** 2026-06-21  
**Author:** GodBot 🜂 for codecbox

---

## 6.1 Overview

The Control Plane is built around the **NEORV32 RISC-V soft-core processor**. It manages all non-real-time tasks while the FPGA Audio Fabric handles sample processing.

**Key Responsibilities:**
- GUI rendering to framebuffer
- Touch input handling
- Transport state machine
- DSP patch/coefficient management
- CS42448 codec configuration
- SD card file I/O (FatFs)
- DDR3 buffer management
- Instrument separator clustering

---

## 6.2 NEORV32 Configuration

### 6.2.1 Core Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| ISA | RV32IMC | Base 32-bit + Multiply + Compressed |
| Clock | 100 MHz | Same as fabric |
| DMIPS | ~50 | Adequate for control tasks |
| Code Memory | 32KB BRAM | Instruction memory |
| Data Memory | 32KB BRAM | Stack/heap |
| External RAM | 256MB DDR3 | Buffers, framebuffer |

### 6.2.2 Peripherals Enabled

| Peripheral | Purpose | Interface |
|------------|---------|-----------|
| UART0 | Debug console | 115200 baud |
| SPI0 | SD card + TFT display | ~10 MHz |
| I²C0 | CS42448 codec | 400 kHz |
| GPIO | Buttons, LEDs, reset signals | Memory-mapped |
| DMA | Audio streaming to/from fabric | Memory-mapped |
| Custom | Display controller bridge | Memory-mapped |

### 6.2.3 Memory Map

```
0x0000_0000 - 0x0000_7FFF : Boot ROM (32KB)
0x0000_8000 - 0x0000_FFFF : Instruction RAM (32KB)
0x0001_0000 - 0x0001_7FFF : Data RAM (32KB)
0x4000_0000 - 0x4FFF_FFFF : DDR3 (256MB window)
0x6000_0000 - 0x6FFF_FFFF : Peripherals (256MB)

Peripheral Detail:
0x6000_0000 : DSP Core Control
0x6000_1000 : TDM I/O
0x6000_2000 : Audio DMA
0x6000_3000 : Display Controller (ILI9341)
0x6000_4000 : Touch Controller (XPT2046)
0x6000_5000 : I²C (CS42448)
0x6000_6000 : SPI (SD Card)
0x6000_7000 : System Control
0x6000_8000 : UART0
```

---

## 6.3 Firmware Architecture

### 6.3.1 Layered Structure

```
┌─────────────────────────────────────────────────────────────┐
│                    APPLICATION LAYER                         │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│  │  GUI Tabs    │ │  Transport   │ │  Project Mgr │        │
│  │  - Inputs    │ │  - Play      │ │  - Save      │        │
│  │  - Mix       │ │  - Record    │ │  - Load      │        │
│  │  - Output    │ │  - Stop      │ │  - Export    │        │
│  │  - Master    │ │  - Seek      │ └──────────────┘        │
│  │  - Library   │ └──────────────┘                         │
│  └──────────────┘                                            │
├─────────────────────────────────────────────────────────────┤
│                    SERVICES LAYER                              │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│  │ Mixer Svc    │ │ Recorder Svc │ │ Separator    │        │
│  │ - Patch mgmt │ │ - WAV I/O    │ │ Controller   │        │
│  │ - Routing    │ │ - Ring buf   │ │ - Clustering │        │
│  └──────────────┘ └──────────────┘ └──────────────┘        │
├─────────────────────────────────────────────────────────────┤
│                    HAL (DRIVER) LAYER                          │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│  │ DSP Core HAL │ │ Display HAL  │ │ Touch HAL    │        │
│  │ - Reg access │ │ - SPI bridge │ │ - SPI bridge │        │
│  │ - Coeff load │ │ - FB mgmt    │ │ - Calibrate  │        │
│  ├──────────────┤ ├──────────────┤ ├──────────────┤        │
│  │ Codec HAL    │ │ SD Card HAL  │ │ DDR HAL      │        │
│  │ - I²C cmds   │ │ - SPI + FF   │ │ - DMA setup  │        │
│  └──────────────┘ └──────────────┘ └──────────────┘        │
├─────────────────────────────────────────────────────────────┤
│                    BSP / LIBRARY LAYER                         │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│  │ NEORV32 BSP  │ │ FatFs        │ │ libfixmath   │        │
│  │ - Startup    │ │ - File system│ │ - Fixed pt   │        │
│  │ - IRQ        │ │              │ │ - DSP calc   │        │
│  └──────────────┘ └──────────────┘ └──────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

---

## 6.4 HAL Specifications

### 6.4.1 DSP Core HAL

```c
// hal_dsp.h
#ifndef HAL_DSP_H
#define HAL_DSP_H

#include <stdint.h>

// Base address
#define DSP_BASE        0x60000000

// Register offsets
#define DSP_PROG        0x0000   // Program memory (36 words)
#define DSP_COEFF       0x0100   // Coefficient memory (256 words)
#define DSP_STATE       0x0200   // State memory (384 words)
#define DSP_CTRL        0x0300   // Control register
#define DSP_STATUS      0x0304   // Status register

// Control bits
#define DSP_CTRL_RESET  (1 << 0)
#define DSP_CTRL_ENABLE (1 << 1)
#define DSP_CTRL_COMMIT (1 << 2) // Commit coefficient shadow regs

// Module opcodes
typedef enum {
    OP_NOP = 0x00,
    OP_GAIN = 0x01,
    OP_PAN = 0x02,
    OP_EQ_5BAND = 0x03,
    OP_COMPRESSOR = 0x06,
    OP_DELAY = 0x09,
    OP_BUS_SEND = 0x0A
} DspOpcode;

// Program slot structure
typedef struct {
    uint8_t opcode;
    uint8_t coeff_idx;
    uint8_t state_idx;
    uint8_t flags;
} DspSlot;

// Functions
void dsp_init(void);
void dsp_reset(void);
void dsp_enable(void);
void dsp_write_program(uint8_t pipe, uint8_t slot, DspSlot *config);
void dsp_write_coeff(uint8_t idx, uint32_t value);
void dsp_commit(void);

// Module helpers
void dsp_set_gain(uint8_t pipe, float gain_db);
void dsp_set_eq_band(uint8_t pipe, uint8_t band, float freq, float q, float gain_db);

#endif
```

```c
// hal_dsp.c
#include "hal_dsp.h"

volatile uint32_t *dsp_regs = (void*)DSP_BASE;

void dsp_write_coeff(uint8_t idx, uint32_t value) {
    dsp_regs[DSP_COEFF/4 + idx] = value;
}

void dsp_set_gain(uint8_t pipe, float gain_db) {
    // Convert dB to linear Q1.31
    float linear = powf(10.0f, gain_db / 20.0f);
    uint32_t gain_q31 = (uint32_t)(linear * 0x7FFFFFFF);

    // Write coefficient
    dsp_write_coeff(pipe * 16 + 0, gain_q31);

    // Update program slot for this pipe
    DspSlot slot = {
        .opcode = OP_GAIN,
        .coeff_idx = pipe * 16,
        .state_idx = 0,
        .flags = 0
    };
    dsp_write_program(pipe, 0, &slot);
}
```

### 6.4.2 Display HAL (ILI9341)

```c
// hal_display.h
#ifndef HAL_DISPLAY_H
#define HAL_DISPLAY_H

#include <stdint.h>

#define DISPLAY_WIDTH   320
#define DISPLAY_HEIGHT  240
#define DISPLAY_BPP     16      // RGB565

#define FB_SIZE         (DISPLAY_WIDTH * DISPLAY_HEIGHT * 2)  // 150KB

// Framebuffer in DDR3
#define FB_BASE_ADDR    0x40300000

void display_init(void);
void display_set_pixel(uint16_t x, uint16_t y, uint16_t color);
void display_fill_rect(uint16_t x, uint16_t y, uint16_t w, uint16_t h, uint16_t color);
void display_update(void);  // Trigger SPI DMA transfer

// Colors (RGB565)
#define COLOR_BLACK     0x0000
#define COLOR_WHITE     0xFFFF
#define COLOR_RED       0xF800
#define COLOR_GREEN     0x07E0
#define COLOR_BLUE      0x001F

#endif
```

```c
// hal_display.c
#include "hal_display.h"

// ILI9341 command codes
#define ILI9341_SWRESET     0x01
#define ILI9341_SLPOUT      0x11
#define ILI9341_DISPON      0x29
#define ILI9341_CASET       0x2A
#define ILI9341_PASET       0x2B
#define ILI9341_RAMWR       0x2C
#define ILI9341_PIXFMT      0x3A

// SPI register base
#define SPI_BASE            0x60006000

void display_write_cmd(uint8_t cmd) {
    // DC low = command
    // Write to SPI
}

void display_write_data(uint8_t data) {
    // DC high = data
    // Write to SPI
}

void display_init(void) {
    // Hardware reset
    // Write initialization sequence per ILI9341 datasheet
    display_write_cmd(ILI9341_SWRESET);
    delay_ms(150);

    display_write_cmd(ILI9341_PIXFMT);
    display_write_data(0x55);  // 16-bit color

    display_write_cmd(ILI9341_SLPOUT);
    delay_ms(10);

    display_write_cmd(ILI9341_DISPON);
}

void display_set_pixel(uint16_t x, uint16_t y, uint16_t color) {
    volatile uint16_t *fb = (void*)FB_BASE_ADDR;
    fb[y * DISPLAY_WIDTH + x] = color;
}
```

### 6.4.3 Touch HAL (XPT2046)

```c
// hal_touch.h
#ifndef HAL_TOUCH_H
#define HAL_TOUCH_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint16_t x;     // Screen X (0-319)
    uint16_t y;     // Screen Y (0-239)
    uint16_t z;     // Pressure (0-4095)
    bool pressed;
} TouchEvent;

void touch_init(void);
bool touch_poll(TouchEvent *event);
void touch_calibrate(void);  // Run calibration routine

#endif
```

### 6.4.4 Codec HAL (CS42448)

```c
// hal_codec.h
#ifndef HAL_CODEC_H
#define HAL_CODEC_H

#include <stdint.h>

#define CS42448_ADDR     0x48  // 7-bit I2C address

// Register addresses
#define CS42448_ID       0x01
#define CS42448_PWR_CTL  0x02
#define CS42448_FUNC_MODE 0x03
#define CS42448_IF_FMT   0x04
#define CS42448_ADC_CTL  0x05
#define CS42448_DAC_CTL  0x06
#define CS42448_MCLK_DIV 0x07

void codec_init(void);
void codec_set_volume(uint8_t channel, uint8_t volume);  // 0-255
void codec_mute(bool mute);

#endif
```

```c
// hal_codec.c
#include "hal_codec.h"
#include "hal_i2c.h"

void codec_init(void) {
    // Reset sequence
    codec_write_reg(CS42448_PWR_CTL, 0xFF);  // Power down all
    delay_ms(10);

    // Configure for TDM mode
    codec_write_reg(CS42448_IF_FMT, 0x36);   // TDM, 24-bit

    // Configure ADC/DAC
    codec_write_reg(CS42448_ADC_CTL, 0x00);  // All ADCs enabled
    codec_write_reg(CS42448_DAC_CTL, 0x00);  // All DACs enabled

    // Release power
    codec_write_reg(CS42448_PWR_CTL, 0x00);  // Power up all
}

void codec_write_reg(uint8_t reg, uint8_t value) {
    uint8_t buf[2] = {reg, value};
    i2c_write(CS42448_ADDR << 1, buf, 2);
}
```

---

## 6.5 GUI Framework

### 6.5.1 Immediate-Mode Widget System

```c
// gui.h
#ifndef GUI_H
#define GUI_H

#include "hal_display.h"
#include "hal_touch.h"

typedef enum {
    TAB_INPUTS,
    TAB_MIX,
    TAB_OUTPUT,
    TAB_MASTER,
    TAB_LIBRARY,
    TAB_COUNT
} GuiTab;

void gui_init(void);
void gui_run(void);      // Main loop
void gui_draw(void);     // Single frame render
void gui_handle_touch(TouchEvent *ev);

// Widgets
void gui_button(uint16_t x, uint16_t y, uint16_t w, uint16_t h,
                const char *label, bool *pressed);
void gui_fader(uint16_t x, uint16_t y, uint16_t h,
               float *value, float min, float max);
void gui_tab_bar(void);
void gui_transport_bar(void);

#endif
```

```c
// gui.c
#include "gui.h"

static GuiTab current_tab = TAB_INPUTS;
static uint32_t last_frame_time = 0;

void gui_run(void) {
    while (1) {
        // Poll touch
        TouchEvent ev;
        if (touch_poll(&ev)) {
            gui_handle_touch(&ev);
        }

        // Draw frame at 30 FPS
        uint32_t now = get_time_ms();
        if (now - last_frame_time >= 33) {
            gui_draw();
            display_update();
            last_frame_time = now;
        }

        // Service background tasks
        transport_tick();
    }
}

void gui_draw(void) {
    // Clear background
    display_fill_rect(0, 0, DISPLAY_WIDTH, DISPLAY_HEIGHT, COLOR_BLACK);

    // Draw tab bar
    gui_tab_bar();

    // Draw transport (always visible)
    gui_transport_bar();

    // Draw active tab content
    switch (current_tab) {
        case TAB_INPUTS:    tab_inputs_draw(); break;
        case TAB_MIX:       tab_mix_draw(); break;
        case TAB_OUTPUT:    tab_output_draw(); break;
        case TAB_MASTER:    tab_master_draw(); break;
        case TAB_LIBRARY:   tab_library_draw(); break;
    }
}
```

---

## 6.6 Build System

### 6.6.1 Directory Structure

```
firmware/
├── Makefile
├── linker/
│   └── loom.ld           # Linker script
├── src/
│   ├── main.c
│   ├── app/
│   │   ├── gui.c
│   │   ├── transport.c
│   │   └── project.c
│   ├── services/
│   │   ├── mixer.c
│   │   ├── recorder.c
│   │   └── separator.c
│   ├── hal/
│   │   ├── dsp.c
│   │   ├── display.c
│   │   ├── touch.c
│   │   ├── codec.c
│   │   ├── sdcard.c
│   │   └── ddr.c
│   └── startup/
│       └── crt0.S
└── lib/
    ├── neorv32/          # BSP
    └── fatfs/            # File system
```

### 6.6.2 Makefile

```makefile
# Makefile

RISCV_PREFIX = riscv32-unknown-elf-
CC = $(RISCV_PREFIX)gcc
LD = $(RISCV_PREFIX)ld
OBJCOPY = $(RISCV_PREFIX)objcopy

CFLAGS = -march=rv32imc -mabi=ilp32 -O2 -Wall
CFLAGS += -I./lib/neorv32 -I./lib/fatfs
CFLAGS += -I./src/hal -I./src/services -I./src/app

LDFLAGS = -T linker/loom.ld -nostdlib

SRCS = $(wildcard src/*.c src/**/*.c)
OBJS = $(SRCS:.c=.o)

TARGET = loom_firmware

all: $(TARGET).hex

$(TARGET).elf: $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

$(TARGET).hex: $(TARGET).elf
	$(OBJCOPY) -O ihex $< $@

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

flash: $(TARGET).hex
	# Use OpenOCD to flash
	openocd -f interface/jlink.cfg -f target/neorv32.cfg \
	    -c "program $< verify reset exit"

clean:
	rm -f $(OBJS) $(TARGET).elf $(TARGET).hex

.PHONY: all flash clean
```

---

## 6.7 Debug Strategy

### 6.7.1 SEGGER J-Link Setup

```bash
# Connect J-Link to Arty JTAG header (2x5 pin)
# Pinout: TCK, TMS, TDI, TDO, TRST, VTref, GND

# Start OpenOCD
openocd -f interface/jlink.cfg -f target/neorv32.cfg

# In another terminal:
telnet localhost 4444
> halt
> reg                  # Show registers
> step                 # Single step
> bp 0x80000000 4      # Breakpoint at main
> resume
```

### 6.7.2 GDB Debug

```bash
# Terminal 1: OpenOCD
openocd -f interface/jlink.cfg -f target/neorv32.cfg

# Terminal 2: GDB
riscv32-unknown-elf-gdb loom_firmware.elf
(gdb) target remote localhost:3333
(gdb) load
(gdb) break main
(gdb) continue
```

---

## 6.8 Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-06-21 | GodBot | Initial control plane spec |
| 1.0 | 2026-06-21 | GodBot | Complete HAL specs, GUI framework, build system |

---

*End of Section 6 — CONTROL PLANE*
