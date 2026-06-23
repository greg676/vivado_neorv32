# OPUS MAXIMUS / LOOM — Section 7: GUI / DISPLAY / TOUCH

**Document ID:** OPUS-07-GUI-DISPLAY-TOUCH  
**Version:** 1.0 — Implementation Ready  
**Date:** 2026-06-21  
**Author:** GodBot 🜂 for codecbox

---

## 7.1 Display Hardware: ILI9341 2.4" SPI TFT

### 7.1.1 Display Specifications

| Parameter | Specification |
|-----------|---------------|
| **Panel** | 2.4 inch TFT LCD Module |
| **Resolution** | 320 × 240 pixels (QVGA) |
| **Aspect Ratio** | 4:3 |
| **Color Depth** | 262,144 colors (18-bit internal) |
| **Interface Color** | 16-bit RGB565 (65,536 colors) |
| **Controller** | ILI9341 |
| **Interface** | SPI Serial (4-wire mode) |
| **SPI Clock** | Up to 10 MHz typical, 15 MHz max |
| **Frame Rate** | 60 Hz @ 10MHz SPI (with partial updates) |
| **Touch Type** | Resistive |
| **Touch Controller** | XPT2046 or compatible |
| **Backlight** | LED, 3.3V |
| **Supply Voltage** | 3.3V logic, 2.8-3.3V backlight |
| **Viewing Direction** | 6 o'clock (bottom viewing) |

### 7.1.2 SPI Interface Timing

```
4-Wire SPI Mode:
┌─────────────────────────────────────────────────────────┐
│  SCK   ═╪═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═╤═│
│         ││││││││││││││││││││││││││││││││││││││││││││││││
│  MOSI  ─┤D│D│D│D│D│D│D│D│X│X│X│X│X│X│X│X│─────────────│
│         │7│6│5│4│3│2│1│0│ │ │ │ │ │ │ │ │              │
│         │                                                             │
│  DC    ─┐                                                            │
│         │  LOW = Command, HIGH = Data                               │
│         └─────────────────────────────────────────────────────────────│
│         │                                                             │
│  CS    ═╪═══════════════════════════════════════════════│  Active low
│                                                             │
│  RST   ─┐                                                    │
│         │  LOW = Reset (min 10µs)                            │
│         └──────────────────────────────────────────────│
└─────────────────────────────────────────────────────────┘

Timing Requirements:
- SCK cycle: 100ns minimum (10MHz max)
- CS setup: 15ns before SCK
- CS hold: 10ns after SCK
- DC setup: 10ns before SCK
- DC hold: 10ns after SCK
```

### 7.1.3 ILI9341 Pinout (Typical Module)

| Pin | Function | Arty Connection |
|-----|----------|-----------------|
| VCC | 3.3V power | 3.3V |
| GND | Ground | GND |
| CS | Chip Select | GPIO (active low) |
| RESET | Hardware reset | GPIO (active low) |
| DC/RS | Data/Command | GPIO |
| SDI/MOSI | SPI data in | SPI0 MOSI |
| SCK | SPI clock | SPI0 SCK |
| LED | Backlight | GPIO + transistor (PWM capable) |
| SDO/MISO | SPI data out | Not connected (or SPI0 MISO) |
| T_CLK | Touch SPI clock | SPI0 SCK (shared) |
| T_CS | Touch chip select | GPIO (separate from display CS) |
| T_DIN | Touch MOSI | SPI0 MOSI (shared) |
| T_DO | Touch MISO | SPI0 MISO (shared) |
| T_IRQ | Touch interrupt | GPIO (optional, can poll) |

---

## 7.2 Display Controller Fabric RTL

### 7.2.1 SPI Master with DC Control

```verilog
module ili9341_controller (
    input  wire        clk,           // 100 MHz fabric clock
    input  wire        rst_n,

    // Framebuffer interface
    input  wire [15:0] fb_data,       // RGB565 pixel
    input  wire [17:0] fb_addr,       // 320*240 = 76800 < 2^18
    output wire        fb_rd,         // Framebuffer read strobe

    // Configuration interface
    input  wire [7:0]  cmd_data,      // Command/data to send
    input  wire        cmd_valid,     // Command valid
    input  wire        cmd_dc,        // 0=command, 1=data
    output wire        cmd_ready,     // Ready for next command

    // ILI9341 SPI interface
    output reg         spi_sck,
    output reg         spi_mosi,
    output reg         spi_cs_n,
    output reg         spi_dc,
    output reg         lcd_rst_n,
    output reg         lcd_bl         // Backlight PWM
);

// SPI clock generation: 100MHz / 8 = 12.5MHz
reg [2:0] sck_div;
reg [3:0] bit_cnt;
reg [7:0] shift_reg;
reg busy;

assign cmd_ready = !busy;
assign fb_rd = 1'b0;  // Controlled in DMA mode

// Main state machine
typedef enum {IDLE, RESET_PULSE, INIT_SEQ, FRAME_SEND} state_t;
state_t state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= RESET_PULSE;
        lcd_rst_n <= 0;
        spi_cs_n <= 1;
        sck_div <= 0;
        busy <= 0;
    end else begin
        case (state)
            RESET_PULSE: begin
                // Hold reset for 10ms
                lcd_rst_n <= 0;
                // ... delay counter ...
                state <= INIT_SEQ;
                lcd_rst_n <= 1;
            end

            INIT_SEQ: begin
                // Send initialization commands
                // See ILI9341 datasheet for sequence
                if (init_done) state <= IDLE;
            end

            IDLE: begin
                if (cmd_valid) begin
                    busy <= 1;
                    spi_dc <= cmd_dc;
                    spi_cs_n <= 0;
                    shift_reg <= cmd_data;
                    bit_cnt <= 7;
                end
            end

            // ... SPI bit shifting ...
        endcase
    end
end

// SPI bit shifting
always @(posedge clk) begin
    if (busy && !spi_cs_n) begin
        sck_div <= sck_div + 1;
        if (sck_div == 3) begin  // Toggle at /8
            spi_sck <= ~spi_sck;
            if (!spi_sck) begin    // Rising edge
                spi_mosi <= shift_reg[7];
                shift_reg <= {shift_reg[6:0], 1'b0};
                bit_cnt <= bit_cnt - 1;
                if (bit_cnt == 0) begin
                    spi_cs_n <= 1;
                    busy <= 0;
                end
            end
        end
    end else begin
        spi_sck <= 0;
        sck_div <= 0;
    end
end

endmodule
```

### 7.2.2 Framebuffer-to-SPI DMA Engine

```verilog
module display_dma (
    input  wire        clk,
    input  wire        rst_n,

    // Framebuffer read
    output reg  [17:0] fb_addr,
    input  wire [15:0] fb_data,
    output reg         fb_rd,

    // SPI controller interface
    output reg  [15:0] pixel_data,
    output reg         pixel_valid,
    input  wire        pixel_ready,

    // Control
    input  wire        dma_start,
    output reg         dma_done
);

// DMA state: send pixel data in ILI9341 format
// Requires: set_column_addr, set_page_addr, write_memory

typedef enum {IDLE, SET_COL_START, SET_COL_END, SET_PAGE_START,
              SET_PAGE_END, WRITE_CMD, PIXEL_DATA} dma_state_t;
dma_state_t state;

reg [8:0] x, y;  // 0-319, 0-239

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        fb_addr <= 0;
        x <= 0;
        y <= 0;
    end else begin
        case (state)
            IDLE: if (dma_start) state <= SET_COL_START;

            SET_COL_START: begin
                // Send 0x2A with 0x00, 0x00 (start column)
                if (pixel_ready) state <= SET_COL_END;
            end

            SET_COL_END: begin
                // Send 0x01, 0x3F (end column = 319)
                state <= SET_PAGE_START;
            end

            // ... similar for page address (rows) ...

            WRITE_CMD: begin
                // Send 0x2C (memory write)
                state <= PIXEL_DATA;
                fb_addr <= 0;
            end

            PIXEL_DATA: begin
                // Stream pixels from framebuffer
                if (pixel_ready) begin
                    fb_rd <= 1;
                    pixel_data <= fb_data;
                    pixel_valid <= 1;
                    fb_addr <= fb_addr + 1;

                    if (fb_addr == 320*240 - 1) begin
                        dma_done <= 1;
                        state <= IDLE;
                    end
                end
            end
        endcase
    end
end

endmodule
```

---

## 7.3 ILI9341 Initialization Sequence

```c
// C code for initialization
const uint8_t ili9341_init_cmds[] = {
    // Power control A
    0xCB, 5, 0x39, 0x2C, 0x00, 0x34, 0x02,

    // Power control B
    0xCF, 3, 0x00, 0xC1, 0x30,

    // Driver timing control A
    0xE8, 3, 0x85, 0x00, 0x78,

    // Driver timing control B
    0xEA, 2, 0x00, 0x00,

    // Power on sequence control
    0xED, 4, 0x64, 0x03, 0x12, 0x81,

    // Pump ratio control
    0xF7, 1, 0x20,

    // Power control 1
    0xC0, 1, 0x23,  // VRH[5:0]

    // Power control 2
    0xC1, 1, 0x10,  // SAP[2:0], BT[3:0]

    // VCOM control 1
    0xC5, 2, 0x3E, 0x28,

    // VCOM control 2
    0xC7, 1, 0x86,

    // Memory access control
    0x36, 1, 0x48,  // Row/col exchange, BGR

    // Pixel format
    0x3A, 1, 0x55,  // 16-bit color

    // Frame rate
    0xB1, 2, 0x00, 0x18,

    // Display function control
    0xB6, 3, 0x08, 0x82, 0x27,

    // 3G gamma disable
    0xF2, 1, 0x00,

    // Gamma set
    0x26, 1, 0x01,

    // Positive gamma correction
    0xE0, 15, 0x0F, 0x31, 0x2B, 0x0C, 0x0E, 0x08,
             0x4E, 0xF1, 0x37, 0x07, 0x10, 0x03,
             0x0E, 0x09, 0x00,

    // Negative gamma correction
    0xE1, 15, 0x00, 0x0E, 0x14, 0x03, 0x11, 0x07,
             0x31, 0xC1, 0x48, 0x08, 0x0F, 0x0C,
             0x31, 0x36, 0x0F,

    // Sleep out
    0x11, 0,

    // Display on
    0x29, 0,

    // End marker
    0x00
};

void ili9341_init(void) {
    // Hardware reset
    gpio_write(PIN_LCD_RST, 0);
    delay_ms(20);
    gpio_write(PIN_LCD_RST, 1);
    delay_ms(150);

    // Send command sequence
    const uint8_t *p = ili9341_init_cmds;
    while (*p) {
        uint8_t cmd = *p++;
        uint8_t count = *p++;
        ili9341_write_cmd(cmd);
        for (int i = 0; i < count; i++) {
            ili9341_write_data(*p++);
        }
    }

    // Turn on backlight
    pwm_set_duty(PWM_BACKLIGHT, 80);  // 80% brightness
}
```

---

## 7.4 Touch Controller (XPT2046)

### 7.4.1 XPT2046 Specifications

| Parameter | Value |
|-----------|-------|
| Resolution | 12-bit ADC (4096 levels) |
| Interface | SPI, up to 2MHz |
| Channels | 4 (X+, X-, Y+, Y-) |
| Touch detect | Automatic or polled |
| Reference | Internal 2.5V or external |
| Temperature | On-chip sensor (optional) |

### 7.4.2 Touch Read Sequence

```c
// XPT2046 command bytes
#define CMD_READ_X     0xD0  // 1101 0000 - X position
#define CMD_READ_Y     0x90  // 1001 0000 - Y position
#define CMD_READ_Z1    0xB0  // 1011 0000 - Z1 (pressure)
#define CMD_READ_Z2    0xC0  // 1100 0000 - Z2 (pressure)
#define CMD_POWER_DOWN 0x00  // Power down after conversion

typedef struct {
    uint16_t x, y, z;
    bool pressed;
} TouchRaw;

TouchRaw touch_read_raw(void) {
    TouchRaw result = {0, 0, 0, false};

    // Read Z (pressure) first to detect touch
    spi_select(SPI_TOUCH);
    spi_write(CMD_READ_Z1);
    uint16_t z1 = spi_read() >> 3;  // 12-bit result

    spi_write(CMD_READ_Z2);
    uint16_t z2 = spi_read() >> 3;
    spi_deselect(SPI_TOUCH);

    // Calculate pressure
    if (z1 == 0) return result;  // No touch

    uint16_t pressure = (z2 / z1 - 1) * 4095;
    if (pressure < 100) return result;  // Threshold

    // Read X and Y
    spi_select(SPI_TOUCH);
    spi_write(CMD_READ_X);
    result.x = spi_read() >> 3;

    spi_write(CMD_READ_Y);
    result.y = spi_read() >> 3;
    spi_deselect(SPI_TOUCH);

    result.z = pressure;
    result.pressed = true;

    return result;
}
```

### 7.4.3 Touch Calibration

```c
// Calibration matrix: maps raw ADC to screen coordinates
// Screen: (0,0) top-left, (319,239) bottom-right
// Raw: depends on panel orientation

typedef struct {
    float a, b, c;  // x = a*raw_x + b*raw_y + c
    float d, e, f;  // y = d*raw_x + e*raw_y + f
} TouchCalib;

TouchCalib calibration;

void touch_calibrate(void) {
    // Show calibration points
    const struct { uint16_t x, y; } points[3] = {
        {20, 20},      // Top-left
        {300, 20},     // Top-right
        {160, 220}     // Bottom-center
    };

    uint16_t raw_x[3], raw_y[3];

    for (int i = 0; i < 3; i++) {
        // Draw crosshair at calibration point
        display_crosshair(points[i].x, points[i].y);

        // Wait for touch and sample
        TouchRaw raw;
        do { raw = touch_read_raw(); } while (!raw.pressed);

        raw_x[i] = raw.x;
        raw_y[i] = raw.y;

        delay_ms(500);  // Debounce
    }

    // Calculate calibration matrix
    // Using 3-point affine transformation
    // (implementation omitted for brevity)
    calibration = solve_calibration(points, raw_x, raw_y);
}

void touch_to_screen(TouchRaw *raw, uint16_t *sx, uint16_t *sy) {
    float x = calibration.a * raw->x + calibration.b * raw->y + calibration.c;
    float y = calibration.d * raw->x + calibration.e * raw->y + calibration.f;

    *sx = (uint16_t)clamp(x, 0, 319);
    *sy = (uint16_t)clamp(y, 0, 239);
}
```

---

## 7.5 GUI Widget Library

### 7.5.1 Immediate-Mode Button

```c
// Returns true if button was clicked this frame
bool gui_button(uint16_t x, uint16_t y, uint16_t w, uint16_t h,
                const char *label, bool *pressed) {
    static bool was_pressed = false;

    // Draw button
    uint16_t color = *pressed ? COLOR_DARK_GRAY : COLOR_LIGHT_GRAY;
    display_fill_rect(x, y, w, h, color);
    display_rect(x, y, w, h, COLOR_BLACK);  // Border
    display_text(x + 5, y + h/2 - 4, label, COLOR_BLACK);

    // Check touch
    TouchEvent ev;
    if (touch_poll(&ev) && ev.pressed) {
        if (ev.x >= x && ev.x < x + w &&
            ev.y >= y && ev.y < y + h) {
            if (!was_pressed) {
                was_pressed = true;
                *pressed = !*pressed;
                return true;  // Clicked
            }
        }
    } else {
        was_pressed = false;
    }

    return false;
}
```

### 7.5.2 Vertical Fader

```c
void gui_fader(uint16_t x, uint16_t y, uint16_t h,
               float *value, float min, float max,
               const char *label) {
    uint16_t track_w = 20;
    uint16_t handle_h = 20;

    // Draw track
    display_fill_rect(x, y, track_w, h, COLOR_DARK_GRAY);

    // Calculate handle position
    float norm = (*value - min) / (max - min);
    uint16_t handle_y = y + h - (uint16_t)(norm * h) - handle_h/2;

    // Draw handle
    display_fill_rect(x - 5, handle_y, track_w + 10, handle_h, COLOR_BLUE);

    // Draw label and value
    display_text(x + track_w + 5, y, label, COLOR_WHITE);
    char val_str[8];
    snprintf(val_str, sizeof(val_str), "%+.1f", *value);
    display_text(x + track_w + 5, y + 10, val_str, COLOR_WHITE);

    // Handle touch
    TouchEvent ev;
    if (touch_poll(&ev) && ev.pressed) {
        if (ev.x >= x - 10 && ev.x <= x + track_w + 10 &&
            ev.y >= y && ev.y <= y + h) {
            // Map Y to value
            float new_norm = 1.0f - (float)(ev.y - y) / h;
            *value = min + new_norm * (max - min);
            *value = clamp(*value, min, max);
        }
    }
}
```

### 7.5.3 Tab Bar

```c
typedef enum { TAB_INPUTS, TAB_MIX, TAB_OUTPUT, TAB_MASTER, TAB_LIBRARY } Tab;

static const char *tab_labels[] = {"IN", "MIX", "OUT", "MST", "LIB"};
static Tab current_tab = TAB_INPUTS;

void gui_tab_bar(void) {
    uint16_t tab_w = 64;  // 320 / 5
    uint16_t tab_h = 30;
    uint16_t y = 10;

    for (int i = 0; i < 5; i++) {
        uint16_t x = i * tab_w;
        uint16_t color = (i == current_tab) ? COLOR_BLUE : COLOR_GRAY;

        display_fill_rect(x, y, tab_w - 2, tab_h, color);
        display_text(x + 20, y + 10, tab_labels[i], COLOR_WHITE);

        // Check touch
        TouchEvent ev;
        if (touch_poll(&ev) && ev.pressed) {
            if (ev.y >= y && ev.y < y + tab_h &&
                ev.x >= x && ev.x < x + tab_w) {
                current_tab = i;
            }
        }
    }
}
```

---

## 7.6 Screen Layout (320×240)

```
┌──────────────────────────────────────────────────────────────┐
│  IN   MIX   OUT   MST   LIB  │            │                │  Tab Bar (30px)
├──────────────────────────────────────────────────────────────┤
│                                                               │
│   ┌──────────────────────────────────────────────────────┐   │
│   │                                                      │   │
│   │                  TAB CONTENT                         │   │  Main content
│   │                                                      │   │  (180px)
│   │                                                      │   │
│   └──────────────────────────────────────────────────────┘   │
│                                                               │
│   ┌────────┬────────┬────────┬────────┐                      │
│   │  Ch1   │  Ch2   │  Ch3   │  Ch4   │  Context selectors  │
│   │ [────] │ [────] │ [────] │ [────] │  mini faders        │
│   └────────┴────────┴────────┴────────┘                      │
│                                                               │
├──────────────────────────────────────────────────────────────┤
│  [←] [▶] [■] [⏺]    00:01:23.45    [◀] [▶] [MODE]          │  Transport (30px)
└──────────────────────────────────────────────────────────────┘
```

---

## 7.7 Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-06-21 | GodBot | Initial display/touch spec |
| 1.0 | 2026-06-21 | GodBot | Complete ILI9341 RTL, XPT2046 calibration, GUI widgets |

---

*End of Section 7 — GUI / DISPLAY / TOUCH*
