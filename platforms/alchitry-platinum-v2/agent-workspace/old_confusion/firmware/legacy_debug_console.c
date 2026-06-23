// v28 — SPI commands added (W25Q64/ILI9341/XPT2046/SD)
// v27 — 16-bit I2C writes for CS42448 (Arty-style init)
// The CS42448 uses 16-bit registers. Each write is:
//   START → addr|W → reg_addr → data_H → data_L → STOP
//
// Arty working init (from cs42448_init.py):
//   RST=0 for 10ms, RST=1 for 5ms
//   0x01 read = 0x0004 (chip ID)
//   0x02 = 0x0000 (power up all)
//   0x03 = 0xF001 (TDM, slave, one-line)
//   0x06 = 0x0077 (8 slots)
//   0x07 = 0xE400 (ADC mux)
//   0x08-0x0A = 0x0000 (PGA unity)
//   0x0B = 0x0000 (DAC unmute)
//   0x18-0x1F = 0x0000 (DAC vol 0dB)
//
#include <neorv32.h>
#include <string.h>

#define CMD_LEN 80
char cmd_buf[CMD_LEN];
uint8_t cmd_pos = 0;

static uint8_t tokenize(char *line, char **tokens, uint8_t max_tok) {
    uint8_t n = 0; char *p = line;
    while (*p && n < max_tok) { while (*p==' '||*p=='\t') p++; if (!*p) break; tokens[n++]=p; while (*p&&*p!=' '&&*p!='\t') p++; if (*p) *p++='\0'; }
    return n;
}

static void phex(uint8_t v) { const char *h="0123456789ABCDEF"; neorv32_uart0_putc(h[v>>4]); neorv32_uart0_putc(h[v&0xF]); }
static void phex16(uint16_t v) { phex(v>>8); phex(v&0xFF); }
static void phex32(uint32_t v) { for (int i=28;i>=0;i-=4) phex((v>>i)&0xF); }

static void twi_rx_drain(void) {
    uint8_t dummy;
    while (neorv32_twi_get(&dummy) != -1) { /* discard */ }
}

// ── I2C helpers ───────────────────────────────────────────────

// 8-bit write
static int i2c_write8(uint8_t addr, uint8_t reg, uint8_t val) {
    int nack = 0; uint8_t d;
    neorv32_twi_generate_start();
    d = addr << 1;        nack |= neorv32_twi_transfer(&d, 0);
    d = reg;              nack |= neorv32_twi_transfer(&d, 0);
    d = val;              nack |= neorv32_twi_transfer(&d, 0);
    neorv32_twi_generate_stop();
    twi_rx_drain();
    return nack ? -1 : 0;
}

// 16-bit write (for CS42448 registers)
// Sends: START → addr|W → reg_addr → data_high → data_low → STOP
static int i2c_write16(uint8_t addr, uint8_t reg, uint16_t val) {
    int nack = 0; uint8_t d;
    neorv32_twi_generate_start();
    d = addr << 1;        nack |= neorv32_twi_transfer(&d, 0);
    d = reg;              nack |= neorv32_twi_transfer(&d, 0);
    d = val >> 8;        nack |= neorv32_twi_transfer(&d, 0);  // high byte
    d = val & 0xFF;      nack |= neorv32_twi_transfer(&d, 0);  // low byte
    neorv32_twi_generate_stop();
    twi_rx_drain();
    return nack ? -1 : 0;
}

// 16-bit read (for CS42448 registers)
// Sends: START → addr|W → reg_addr → REPEATED-START → addr|R → read_H → read_L → STOP
static uint16_t i2c_read16(uint8_t addr, uint8_t reg) {
    uint8_t d; uint16_t val = 0;
    // Write phase
    neorv32_twi_generate_start();
    d = addr << 1;
    if (neorv32_twi_transfer(&d, 0)) { neorv32_twi_generate_stop(); twi_rx_drain(); return 0xFFFF; }
    d = reg;
    if (neorv32_twi_transfer(&d, 0)) { neorv32_twi_generate_stop(); twi_rx_drain(); return 0xFFFF; }
    // Read phase — REPEATED-START
    neorv32_twi_generate_start();
    d = (addr << 1) | 1;
    if (neorv32_twi_transfer(&d, 0)) { neorv32_twi_generate_stop(); twi_rx_drain(); return 0xFFFF; }
    // Read high byte — host ACK (more coming)
    d = 0xFF;
    neorv32_twi_transfer(&d, 1);  // host ACK
    val = ((uint16_t)d) << 8;
    // Read low byte — host NACK (last byte)
    d = 0xFF;
    neorv32_twi_transfer(&d, 0);  // host NACK
    val |= d;
    neorv32_twi_generate_stop();
    twi_rx_drain();
    return val;
}

// 8-bit read (for single-byte registers)
static uint8_t i2c_read8(uint8_t addr, uint8_t reg) {
    uint8_t d;
    neorv32_twi_generate_start();
    d = addr << 1;
    if (neorv32_twi_transfer(&d, 0)) { neorv32_twi_generate_stop(); twi_rx_drain(); return 0xFF; }
    d = reg;
    if (neorv32_twi_transfer(&d, 0)) { neorv32_twi_generate_stop(); twi_rx_drain(); return 0xFF; }
    neorv32_twi_generate_start();
    d = (addr << 1) | 1;
    if (neorv32_twi_transfer(&d, 0)) { neorv32_twi_generate_stop(); twi_rx_drain(); return 0xFF; }
    d = 0xFF;
    neorv32_twi_transfer(&d, 0);  // host NACK
    uint8_t val = d;
    neorv32_twi_generate_stop();
    twi_rx_drain();
    return val;
}

// ── Codec init (Arty-style, 16-bit registers) ─────────────────
static void codec_init(void) {
    neorv32_uart0_puts("\n--- CS42448 TDM init (v27) ---\n");

    // Reset TWI
    NEORV32_TWI->CTRL = 0;
    neorv32_aux_delay_ms(neorv32_sysinfo_get_clk(), 5);

    // ── Hardware Reset Sequence (per Arty script) ──────────────
    // GPIO3 = RSTCN. Hold LOW for 10ms, then HIGH for 5ms.
    neorv32_uart0_puts("Reset: RST=0... ");
    neorv32_gpio_pin_set(3, 0);
    neorv32_aux_delay_ms(neorv32_sysinfo_get_clk(), 10);

    neorv32_uart0_puts("RST=1... ");
    neorv32_gpio_pin_set(3, 1);
    neorv32_aux_delay_ms(neorv32_sysinfo_get_clk(), 5);
    neorv32_uart0_puts("ok\n");

    // Enable clocks (GPIO6)
    neorv32_uart0_puts("Clocks: GPIO6=1... ");
    neorv32_gpio_pin_set(6, 1);
    neorv32_aux_delay_ms(neorv32_sysinfo_get_clk(), 50);
    neorv32_uart0_puts("ok\n");

    // Init TWI
    neorv32_twi_setup(6, 15, 0);

    // Check bus
    int scl = neorv32_twi_sense_scl(), sda = neorv32_twi_sense_sda();
    neorv32_uart0_puts("Bus: SCL="); neorv32_uart0_putc(scl ? 'H' : 'L');
    neorv32_uart0_puts(" SDA="); neorv32_uart0_putc(sda ? 'H' : 'L');
    if (!scl || !sda) { neorv32_uart0_puts(" STUCK\n"); return; }
    neorv32_uart0_puts(" OK\n");

    // Chip ID (16-bit read from reg 0x01)
    uint16_t chipid = i2c_read16(0x48, 0x01);
    neorv32_uart0_puts("ChipID (0x01): 0x"); phex16(chipid); neorv32_uart0_putc('\n');
    if (chipid == 0xFFFF) { neorv32_uart0_puts("No codec!\n"); return; }

    // ── Arty init sequence (16-bit writes) ─────────────────────
    neorv32_uart0_puts("\nArty-style init:\n");

    // 0x02 Power Control = 0x0000 (power up all)
    neorv32_uart0_puts("  PWRCTL=0x0000: ");
    if (i2c_write16(0x48, 0x02, 0x0000)) { neorv32_uart0_puts("FAIL\n"); return; }
    { uint16_t v = i2c_read16(0x48, 0x02); neorv32_uart0_puts("read 0x"); phex16(v); neorv32_uart0_putc('\n'); }

    // 0x03 Functional Mode = 0xF001 (TDM, slave, one-line)
    neorv32_uart0_puts("  FUNCMOD=0xF001: ");
    if (i2c_write16(0x48, 0x03, 0xF001)) { neorv32_uart0_puts("FAIL\n"); return; }
    { uint16_t v = i2c_read16(0x48, 0x03); neorv32_uart0_puts("read 0x"); phex16(v); neorv32_uart0_putc('\n'); }

    // 0x06 TDM Mode = 0x0077 (8 slots)
    neorv32_uart0_puts("  TDM=0x0077 (8 slots): ");
    if (i2c_write16(0x48, 0x06, 0x0077)) { neorv32_uart0_puts("FAIL\n"); return; }
    { uint16_t v = i2c_read16(0x48, 0x06); neorv32_uart0_puts("read 0x"); phex16(v); neorv32_uart0_putc('\n'); }

    // 0x07 ADC Mux = 0xE400 (route AIN1 to ADC1, etc.)
    neorv32_uart0_puts("  ADCMUX=0xE400: ");
    if (i2c_write16(0x48, 0x07, 0xE400)) { neorv32_uart0_puts("FAIL\n"); return; }
    { uint16_t v = i2c_read16(0x48, 0x07); neorv32_uart0_puts("read 0x"); phex16(v); neorv32_uart0_putc('\n'); }

    // 0x08-0x0A PGA gain = 0x0000 (unity)
    neorv32_uart0_puts("  PGA unity... ");
    for (uint8_t r = 0x08; r <= 0x0A; r++) {
        if (i2c_write16(0x48, r, 0x0000)) { neorv32_uart0_puts("FAIL\n"); return; }
    }
    neorv32_uart0_puts("ok\n");

    // 0x0B DAC Mute = 0x0000 (unmute all)
    neorv32_uart0_puts("  DACMUTE=0x0000: ");
    if (i2c_write16(0x48, 0x0B, 0x0000)) { neorv32_uart0_puts("FAIL\n"); return; }
    { uint16_t v = i2c_read16(0x48, 0x0B); neorv32_uart0_puts("read 0x"); phex16(v); neorv32_uart0_putc('\n'); }

    // 0x18-0x1F DAC volume = 0x0000 (0dB)
    neorv32_uart0_puts("  DAC vol 0dB... ");
    for (uint8_t r = 0x18; r <= 0x1F; r++) {
        if (i2c_write16(0x48, r, 0x0000)) { neorv32_uart0_puts("FAIL\n"); return; }
    }
    neorv32_uart0_puts("ok\n");

    neorv32_uart0_puts("\n=== CS42448 ready ===\n");
    neorv32_uart0_puts("TDM: 8-slot, slave, one-line\n");
    neorv32_uart0_puts("Probe: SDOUT=Br D21, SCLK=Br A19, LRCLK=Br A18\n");
}

// ── SPI helpers ───────────────────────────────────────────────
// CS map: 0=ILI9341, 1=XPT2046, 2=SD, 3=W25Q64
// SPI clock: prsc=2 (clk/16=10MHz), cdiv=0 → 10MHz max for W25Q64
//            XPT2046 needs ~2MHz → prsc=5 (clk/256=625kHz), cdiv=0

static void spi_touch_set_clock(void) {
    neorv32_spi_setup(5, 0, 0, 0); // 625kHz for XPT2046
}

static void spi_normal_set_clock(void) {
    neorv32_spi_setup(2, 0, 0, 0); // 10MHz for flash/display/SD
}

static void spi_diag(void) {
    spi_normal_set_clock();
    uint32_t ctrl = NEORV32_SPI->CTRL;
    neorv32_uart0_puts("SPI_CTRL=0x"); phex32(ctrl); neorv32_uart0_putc('\n');
    neorv32_uart0_puts("EN="); neorv32_uart0_putc((ctrl & (1<<0)) ? '1' : '0');
    neorv32_uart0_puts(" BUSY="); neorv32_uart0_putc((ctrl & (1<<31)) ? '1' : '0');
    neorv32_uart0_puts(" TX_EMPTY="); neorv32_uart0_putc((ctrl & (1<<17)) ? '1' : '0');
    neorv32_uart0_puts(" RX_AVAIL="); neorv32_uart0_putc((ctrl & (1<<16)) ? '1' : '0');
    neorv32_uart0_puts(" FIFO="); 
    { uint32_t tmp = (ctrl >> 24) & 0xF; neorv32_uart0_printf("%d", (1 << tmp)); }
    neorv32_uart0_putc('\n');
    neorv32_uart0_puts("Assert CS0... ");
    neorv32_spi_cs_en(0);
    neorv32_aux_delay_ms(neorv32_sysinfo_get_clk(), 10);
    ctrl = NEORV32_SPI->CTRL;
    neorv32_uart0_puts("CS_ACTIVE="); neorv32_uart0_putc((ctrl & (1<<30)) ? '1' : '0');
    neorv32_uart0_puts(" (expect 1)\n");
    neorv32_uart0_puts("TX 0x9F... ");
    uint8_t rx = neorv32_spi_transfer(0x9F);
    neorv32_uart0_puts("RX=0x"); phex(rx); neorv32_uart0_putc('\n');
    neorv32_spi_cs_dis();
    neorv32_aux_delay_ms(neorv32_sysinfo_get_clk(), 5);
    ctrl = NEORV32_SPI->CTRL;
    neorv32_uart0_puts("CS dis: CS_ACTIVE="); neorv32_uart0_putc((ctrl & (1<<30)) ? '1' : '0');
    neorv32_uart0_puts(" (expect 0)\n");
}

// Read W25Q64 JEDEC ID: cmd 0x9F → returns 3 bytes (MFR, TYPE, CAP)
static void flash_read_id(void) {
    spi_normal_set_clock();
    neorv32_spi_cs_en(3);
    neorv32_spi_transfer(0x9F);
    uint8_t mfr  = neorv32_spi_transfer(0xFF);
    uint8_t type = neorv32_spi_transfer(0xFF);
    uint8_t cap  = neorv32_spi_transfer(0xFF);
    neorv32_spi_cs_dis();
    neorv32_uart0_puts("JEDEC: MFR=0x"); phex(mfr);
    neorv32_uart0_puts(" TYPE=0x"); phex(type);
    neorv32_uart0_puts(" CAP=0x"); phex(cap);
    if (mfr == 0xEF && type == 0x40 && cap == 0x17)
        neorv32_uart0_puts(" [W25Q64 OK]");
    else
        neorv32_uart0_puts(" [??]");
    neorv32_uart0_putc('\n');
}

// Read N bytes from flash
static void flash_read(uint32_t addr, uint16_t len) {
    spi_normal_set_clock();
    neorv32_spi_cs_en(3);
    neorv32_spi_transfer(0x03);            // READ command
    neorv32_spi_transfer((addr >> 16) & 0xFF);
    neorv32_spi_transfer((addr >> 8)  & 0xFF);
    neorv32_spi_transfer(addr & 0xFF);
    for (uint16_t i = 0; i < len; i++) {
        if (i && (i % 16) == 0) {
            neorv32_uart0_putc('\n');
            // Print address prefix
            phex(((addr + i) >> 8) & 0xFF); phex((addr + i) & 0xFF); neorv32_uart0_puts(": ");
        }
        if ((i % 16) == 0 && i == 0) {
            phex((addr >> 8) & 0xFF); phex(addr & 0xFF); neorv32_uart0_puts(": ");
        }
        uint8_t b = neorv32_spi_transfer(0xFF);
        phex(b); neorv32_uart0_putc(' ');
    }
    neorv32_spi_cs_dis();
    neorv32_uart0_putc('\n');
}

// Read W25Q64 status register
static void flash_status(void) {
    spi_normal_set_clock();
    neorv32_spi_cs_en(3);
    neorv32_spi_transfer(0x05); // RDSR
    uint8_t sr = neorv32_spi_transfer(0xFF);
    neorv32_spi_cs_dis();
    neorv32_uart0_puts("SR=0x"); phex(sr);
    if (sr & 0x01) neorv32_uart0_puts(" [BUSY]");
    neorv32_uart0_putc('\n');
}

// ILI9341 display: read ID register (cmd 0x04 → 3 data bytes)
static void disp_read_id(void) {
    spi_normal_set_clock();
    neorv32_spi_cs_en(0);
    // DC pin for ILI9341: GPIO5 = DC (0=command, 1=data)
    neorv32_gpio_pin_set(5, 0); // command mode
    neorv32_spi_transfer(0x04); // Read Display ID
    neorv32_gpio_pin_set(5, 1); // data mode
    // 3 dummy/read bytes
    uint8_t b0 = neorv32_spi_transfer(0xFF);
    uint8_t b1 = neorv32_spi_transfer(0xFF);
    uint8_t b2 = neorv32_spi_transfer(0xFF);
    neorv32_gpio_pin_set(5, 0); // back to command mode
    neorv32_spi_cs_dis();
    neorv32_uart0_puts("ILI9341 ID: 0x"); phex(b0);
    neorv32_uart0_puts(" 0x"); phex(b1);
    neorv32_uart0_puts(" 0x"); phex(b2);
    if (b0 == 0x85 && b1 == 0x52) neorv32_uart0_puts(" [ILI9341 OK]");
    neorv32_uart0_putc('\n');
}

// XPT2046 touch: read X position (12-bit ADC)
static void touch_read_xy(void) {
    spi_touch_set_clock();
    neorv32_spi_cs_en(1);
    // X position: cmd byte = 0xD0 (start=1, A2..A0=101 for X, 8-bit, no powerdown)
    neorv32_spi_transfer(0xD0);
    uint8_t xh = neorv32_spi_transfer(0x00);
    uint8_t xl = neorv32_spi_transfer(0x00);
    uint16_t x = ((uint16_t)xh << 8) | xl;
    // Y position: cmd byte = 0x90 (A2..A0=001 for Y)
    neorv32_spi_transfer(0x90);
    uint8_t yh = neorv32_spi_transfer(0x00);
    uint8_t yl = neorv32_spi_transfer(0x00);
    uint16_t y = ((uint16_t)yh << 8) | yl;
    neorv32_spi_cs_dis();
    spi_normal_set_clock();
    neorv32_uart0_puts("Touch X=0x"); phex16(x);
    neorv32_uart0_puts(" Y=0x"); phex16(y); neorv32_uart0_putc('\n');
}

// SD card: send CMD0 (GO_IDLE) + ACMD41, check if card responds
static void sd_probe(void) {
    spi_normal_set_clock();
    // SD uses SPI mode: CS active, send dummy clocks for init
    neorv32_spi_cs_en(2);
    // Send 10 dummy bytes (80 clocks) for init
    for (int i = 0; i < 10; i++) neorv32_spi_transfer(0xFF);
    // CMD0: GO_IDLE_STATE
    neorv32_spi_transfer(0x40); // cmd index 0
    neorv32_spi_transfer(0x00); neorv32_spi_transfer(0x00);
    neorv32_spi_transfer(0x00); neorv32_spi_transfer(0x00); // arg
    neorv32_spi_transfer(0x95); // CRC
    // Wait for response (not 0xFF)
    uint8_t r1 = 0xFF;
    for (int i = 0; i < 16; i++) {
        r1 = neorv32_spi_transfer(0xFF);
        if (r1 != 0xFF) break;
    }
    neorv32_spi_cs_dis();
    neorv32_spi_cs_en(2);
    neorv32_uart0_puts("SD CMD0 R1=0x"); phex(r1);
    if (r1 == 0x01) neorv32_uart0_puts(" [idle, OK]");
    else if (r1 == 0xFF) neorv32_uart0_puts(" [no card]");
    else neorv32_uart0_puts(" [??]");
    neorv32_uart0_putc('\n');
    neorv32_spi_cs_dis();
}

// ── Commands ───────────────────────────────────────────────────
static void cmd_sys(void) {
    neorv32_uart0_printf("clk:%u IMEM:%u DMEM:%u\n",
        neorv32_sysinfo_get_clk(), neorv32_sysinfo_get_imemsize(), neorv32_sysinfo_get_dmemsize());
}

static void cmd_help(void) {
    neorv32_uart0_puts("Commands:\n");
    neorv32_uart0_puts(" sys|i2c|codec|clk|gpio\n");
    neorv32_uart0_puts(" spi flash id|read A L|sr        — W25Q64\n");
    neorv32_uart0_puts(" spi disp id                    — ILI9341\n");
    neorv32_uart0_puts(" spi touch                      — XPT2046\n");
    neorv32_uart0_puts(" spi sd                         — SD probe\n");
    neorv32_uart0_puts("> ");
}

static void process(void) {
    char *tok[8]; uint8_t n = tokenize(cmd_buf, tok, 8);
    if (!n) return;

    if (!strcmp(tok[0], "help")) { cmd_help(); }
    else if (!strcmp(tok[0], "sys")) { cmd_sys(); }
    else if (!strcmp(tok[0], "i2c")) {
        if (n >= 2 && !strcmp(tok[1], "raw")) {
            NEORV32_TWI->CTRL = 0; neorv32_aux_delay_ms(neorv32_sysinfo_get_clk(), 5);
            neorv32_twi_setup(6, 15, 0);
            neorv32_uart0_puts("TWI_CTRL: 0x"); phex32(NEORV32_TWI->CTRL);
            neorv32_uart0_puts(" FIFO="); neorv32_uart0_printf("%u", neorv32_twi_get_fifo_depth());
            neorv32_uart0_puts(" SCL="); neorv32_uart0_putc(neorv32_twi_sense_scl() ? 'H' : 'L');
            neorv32_uart0_puts(" SDA="); neorv32_uart0_putc(neorv32_twi_sense_sda() ? 'H' : 'L');
            neorv32_uart0_putc('\n');
        }
        else if (n >= 2 && !strcmp(tok[1], "scan")) {
            NEORV32_TWI->CTRL = 0; neorv32_aux_delay_ms(neorv32_sysinfo_get_clk(), 5);
            neorv32_twi_setup(6, 15, 0);
            neorv32_uart0_puts("scan:"); int found = 0;
            for (uint8_t i = 0; i < 128; i++) {
                neorv32_twi_generate_start();
                uint8_t tmp = 2 * i + 1;
                int ack = neorv32_twi_transfer(&tmp, 0);
                neorv32_twi_generate_stop(); twi_rx_drain();
                if (ack == 0) { neorv32_uart0_puts(" 0x"); phex(i); found++; }
            }
            neorv32_uart0_printf("\nfound=%d\n", found);
        }
        else if (n >= 4 && !strcmp(tok[1], "read8")) {
            NEORV32_TWI->CTRL = 0; neorv32_aux_delay_ms(neorv32_sysinfo_get_clk(), 5);
            neorv32_twi_setup(6, 15, 0);
            uint8_t v = i2c_read8((uint8_t)strtoul(tok[2],NULL,0), (uint8_t)strtoul(tok[3],NULL,0));
            neorv32_uart0_puts("0x"); phex(v); neorv32_uart0_putc('\n');
        }
        else if (n >= 4 && !strcmp(tok[1], "read16")) {
            NEORV32_TWI->CTRL = 0; neorv32_aux_delay_ms(neorv32_sysinfo_get_clk(), 5);
            neorv32_twi_setup(6, 15, 0);
            uint16_t v = i2c_read16((uint8_t)strtoul(tok[2],NULL,0), (uint8_t)strtoul(tok[3],NULL,0));
            neorv32_uart0_puts("0x"); phex16(v); neorv32_uart0_putc('\n');
        }
        else if (n >= 5 && !strcmp(tok[1], "write8")) {
            NEORV32_TWI->CTRL = 0; neorv32_aux_delay_ms(neorv32_sysinfo_get_clk(), 5);
            neorv32_twi_setup(6, 15, 0);
            int r = i2c_write8((uint8_t)strtoul(tok[2],NULL,0), (uint8_t)strtoul(tok[3],NULL,0), (uint8_t)strtoul(tok[4],NULL,0));
            neorv32_uart0_printf("write %s\n", r == 0 ? "ok" : "FAIL");
        }
        else if (n >= 5 && !strcmp(tok[1], "write16")) {
            NEORV32_TWI->CTRL = 0; neorv32_aux_delay_ms(neorv32_sysinfo_get_clk(), 5);
            neorv32_twi_setup(6, 15, 0);
            int r = i2c_write16((uint8_t)strtoul(tok[2],NULL,0), (uint8_t)strtoul(tok[3],NULL,0), (uint16_t)strtoul(tok[4],NULL,0));
            neorv32_uart0_printf("write %s\n", r == 0 ? "ok" : "FAIL");
        }
    }
    else if (!strcmp(tok[0], "codec")) {
        if (n >= 2 && !strcmp(tok[1], "init")) { codec_init(); }
    }
    else if (!strcmp(tok[0], "clk")) {
        if (n >= 2 && !strcmp(tok[1], "on")) { neorv32_gpio_pin_set(6, 1); neorv32_uart0_puts("clk on\n"); }
        else if (n >= 2 && !strcmp(tok[1], "off")) { neorv32_gpio_pin_set(6, 0); neorv32_uart0_puts("clk off\n"); }
    }
    else if (!strcmp(tok[0], "gpio")) {
        if (n >= 3 && !strcmp(tok[1], "r"))
            neorv32_uart0_printf("G[%u]=%c\n", (unsigned)atoi(tok[2]), neorv32_gpio_pin_get(atoi(tok[2]))?'1':'0');
        else if (n >= 4 && !strcmp(tok[1], "w"))
            { neorv32_gpio_pin_set(atoi(tok[2]), atoi(tok[3])); neorv32_uart0_printf("G[%u]=%u\n", (unsigned)atoi(tok[2]), (unsigned)atoi(tok[3])); }
        else if (n >= 2 && !strcmp(tok[1], "dump"))
            { for (uint8_t i=0;i<=5;i++) neorv32_uart0_printf("G[%u]=%c\n",i,neorv32_gpio_pin_get(i)?'1':'0'); }
    }
    else if (!strcmp(tok[0], "spi")) {
        if (n >= 3 && !strcmp(tok[1], "flash") && !strcmp(tok[2], "id")) {
            flash_read_id();
        }
        else if (n >= 3 && !strcmp(tok[1], "flash") && !strcmp(tok[2], "sr")) {
            flash_status();
        }
        else if (n >= 4 && !strcmp(tok[1], "flash") && !strcmp(tok[2], "read")) {
            uint32_t addr = strtoul(tok[3], NULL, 0);
            uint16_t len = (n >= 5) ? (uint16_t)strtoul(tok[4], NULL, 0) : 32;
            if (len > 256) len = 256;
            flash_read(addr, len);
        }
        else if (n >= 3 && !strcmp(tok[1], "disp") && !strcmp(tok[2], "id")) {
            disp_read_id();
        }
        else if (n >= 2 && !strcmp(tok[1], "touch")) {
            touch_read_xy();
        }
        else if (n >= 2 && !strcmp(tok[1], "sd")) {
            sd_probe();
        }
        else if (n >= 2 && !strcmp(tok[1], "diag")) {
            spi_diag();
        }
        else {
            neorv32_uart0_puts("spi: flash id|read A L|sr | disp id | touch | sd\n");
        }
    }
    else neorv32_uart0_puts("??\n");
}

int main(void) {
    neorv32_rte_setup();
    neorv32_gpio_port_set(0);
    neorv32_uart0_setup(19200, 0);
    while (neorv32_uart0_char_received()) neorv32_uart0_char_received_get();

    neorv32_uart0_puts("\n=== v28 — I2C + SPI debug console ===\n");
    cmd_sys();
    codec_init();

    while (1) {
        neorv32_uart0_puts("> ");
        cmd_pos = 0;
        while (1) {
            if (neorv32_uart0_char_received()) {
                char c = neorv32_uart0_char_received_get();
                if (c == '\r' || c == '\n') { neorv32_uart0_putc('\r'); neorv32_uart0_putc('\n'); cmd_buf[cmd_pos]='\0'; break; }
                else if (c==0x7F||c==0x08) { if(cmd_pos>0)cmd_pos--; }
                else if (c>=0x20 && c<=0x7E) { neorv32_uart0_putc(c); if(cmd_pos<CMD_LEN-1)cmd_buf[cmd_pos++]=c; }
            }
        }
        if (cmd_pos > 0) process();
    }
    return 0;
}
