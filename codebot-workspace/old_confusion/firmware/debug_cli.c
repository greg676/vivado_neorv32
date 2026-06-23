// =============================================================================
// codecbot_debug_cli.c — Interactive Debug Monitor for neorv_basic_plus_top
// =============================================================================
// Commands:
//   twi scan          — I²C bus scan (0x00–0x7F)
//   twi read <addr> <reg> [len] — I²C register read
//   twi write <addr> <reg> <val> — I²C register write
//   twi dump <addr> <start> <len> — I²C multi-register dump
//   twi probe <addr> — single address ACK check
//   spi cs <n>        — assert SPI CS line n (0=display,1=touch,2=SD,3=flash)
//   spi tx <byte>     — SPI transmit byte, show RX
//   spi cmd <byte>     — SPI command-mode transmit (CS controlled)
//   spi read <n>       — read n bytes from SPI RX FIFO
//   spi jedec <cs>     — read JEDEC ID from flash (CS3) or display (CS0)
//   spi status         — show SPI CTRL register flags
//   gpio read          — read GPIO input state
//   gpio set <pin> <0|1> — set GPIO output pin
//   gpio status        — show all GPIO registers
//   pwm set <duty>     — set PWM duty cycle (0-255)
//   pwm status         — show PWM config
//   mem rd <addr> [n]  — read memory words (hex dump)
//   mem wr <addr> <val> — write memory word
//   sysinfo            — dump SYSINFO registers
//   reset              — software reset
//   help               — this menu
// =============================================================================

#include <neorv32.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

// ── UART ─────────────────────────────────────────────────────────────
#define BAUD_RATE 19200

// ── TWI (I²C) ────────────────────────────────────────────────────────
// CS42448 is at 0x48. Standard-mode ~100 kHz from 100 MHz core:
// PRSC=2 (CLK/4), CDIV=10 → 100MHz/4/(2*10) ≈ 1.25 MHz (fast-mode+)
// For standard 100 kHz: PRSC=3 (CLK/8), CDIV=12 → 100MHz/8/(2*12) ≈ 520 kHz
// Let's use PRSC=3, CDIV=15 → 100MHz/8/(2*15) ≈ 417 kHz (safe)
#define TWI_PRSC  3
#define TWI_CDIV 15
#define TWI_CLKSTR 1  // enable clock stretching

// ── SPI ──────────────────────────────────────────────────────────────
// CS0=display(ILI9341), CS1=touch(XPT2046), CS2=SD, CS3=flash(W25Q64)
// Display: mode 0 (CPOL=0, CPHA=0), ~20 MHz
// Touch: mode 0, ~2 MHz
// Flash: mode 0 or 3, ~20 MHz
// PRSC=0 (CLK/2), CDIV=1 → 100MHz/2/(2*1) = 25 MHz
// PRSC=0 (CLK/2), CDIV=12 → 100MHz/2/(2*12) ≈ 2 MHz (for touch)
#define SPI_PRSC_FAST  0
#define SPI_CDIV_FAST  1
#define SPI_PRSC_SLOW  0
#define SPI_CDIV_SLOW 12

// ── GPIO ─────────────────────────────────────────────────────────────
// gpio_o[0]=LED, gpio_o[1]=?, gpio_o[2]=codec RST?, gpio_o[3]=?, gpio_o[4]=?
// gpio_i[0]=int_in (from Br t_intt = R4)

// ── Prototypes ───────────────────────────────────────────────────────
void cmd_help(void);
void cmd_twi_scan(void);
void cmd_twi_read(uint8_t addr, uint8_t reg, int len);
void cmd_twi_write(uint8_t addr, uint8_t reg, uint8_t val);
void cmd_twi_dump(uint8_t addr, uint8_t start, int len);
void cmd_twi_probe(uint8_t addr);
void cmd_spi_cs(int cs);
void cmd_spi_tx(uint8_t data);
void cmd_spi_cmd(uint8_t data);
void cmd_spi_read(int n);
void cmd_spi_jedec(int cs);
void cmd_spi_status(void);
void cmd_gpio_read(void);
void cmd_gpio_set(int pin, int val);
void cmd_gpio_status(void);
void cmd_pwm_set(int duty);
void cmd_pwm_status(void);
void cmd_mem_rd(uint32_t addr, int n);
void cmd_mem_wr(uint32_t addr, uint32_t val);
void cmd_sysinfo(void);
void cmd_reset(void);

void twi_start(void);
void twi_stop(void);
int  twi_send_byte(uint8_t data);
uint8_t twi_recv_byte(int ack);
void spi_setup_fast(void);
void spi_setup_slow(void);
uint32_t parse_hex(const char *s);

// ── Globals ──────────────────────────────────────────────────────────
static char buffer[64];

// ─────────────────────────────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────────────────────────────
int main(void) {
    neorv32_uart0_setup(BAUD_RATE, 0);

    neorv32_uart0_printf("\n\n");
    neorv32_uart0_printf("╔══════════════════════════════════════════╗\n");
    neorv32_uart0_printf("║   CodecBot Debug CLI v1.0                ║\n");
    neorv32_uart0_printf("║   neorv_basic_plus_top                  ║\n");
    neorv32_uart0_printf("╠══════════════════════════════════════════╣\n");

    // System info
    neorv32_uart0_printf("║ CLK:  ");
    neorv32_uart0_printf("%u MHz", (uint32_t)(NEORV32_SYSINFO->CLK / 1000000));
    neorv32_uart0_printf("\n");

    neorv32_uart0_printf("║ IMEM: ");
    neorv32_uart0_printf("%u KB", (uint32_t)(1 << NEORV32_SYSINFO->MISC[SYSINFO_MISC_IMEM]) / 1024);
    neorv32_uart0_printf("  DMEM: ");
    neorv32_uart0_printf("%u KB", (uint32_t)(1 << NEORV32_SYSINFO->MISC[SYSINFO_MISC_DMEM]) / 1024);
    neorv32_uart0_printf("\n");

    // Peripheral availability
    neorv32_uart0_printf("║ Peripherals: ");
    if (neorv32_uart0_available())  neorv32_uart0_printf("UART ");
    if (neorv32_twi_available())    neorv32_uart0_printf("TWI ");
    if (neorv32_spi_available())    neorv32_uart0_printf("SPI ");
    if (neorv32_gpio_available())   neorv32_uart0_printf("GPIO ");
    if (neorv32_pwm_available())    neorv32_uart0_printf("PWM ");
    neorv32_uart0_printf("\n");

    neorv32_uart0_printf("╚══════════════════════════════════════════╝\n");
    neorv32_uart0_printf("Type 'help' for commands. 'twi scan' to find codec.\n\n");

    // Initialize TWI
    if (neorv32_twi_available()) {
        neorv32_twi_setup(TWI_PRSC, TWI_CDIV, TWI_CLKSTR);
        neorv32_uart0_printf("[INIT] TWI ready (PRSC=%d, CDIV=%d, clkstr=%d)\n", TWI_PRSC, TWI_CDIV, TWI_CLKSTR);
    }

    // Initialize SPI (fast mode default)
    if (neorv32_spi_available()) {
        neorv32_spi_setup(SPI_PRSC_FAST, SPI_CDIV_FAST, 0, 0, 0);
        neorv32_uart0_printf("[INIT] SPI ready (fast: ~%u kHz)\n",
            (uint32_t)(neorv32_spi_get_clock_speed() / 1000));
    }

    // Main command loop
    for (;;) {
        neorv32_uart0_printf("CODECBOT> ");
        int len = neorv32_uart0_scan(buffer, sizeof(buffer)-1, 1);
        neorv32_uart0_printf("\n");

        if (len == 0) continue;

        // Tokenize
        char *cmd = strtok(buffer, " ");
        char *a0  = strtok(NULL, " ");
        char *a1  = strtok(NULL, " ");
        char *a2  = strtok(NULL, " ");

        if (cmd == NULL) continue;

        // ── HELP ────────────────────────────────────────────────
        if (strcmp(cmd, "help") == 0 || strcmp(cmd, "?") == 0) {
            cmd_help();
        }
        // ── TWI COMMANDS ────────────────────────────────────────
        else if (strcmp(cmd, "twi") == 0) {
            if (a0 == NULL) {
                neorv32_uart0_printf("twi: need subcommand (scan|probe|read|write|dump)\n");
            } else if (strcmp(a0, "scan") == 0) {
                cmd_twi_scan();
            } else if (strcmp(a0, "probe") == 0) {
                if (a1) cmd_twi_probe((uint8_t)parse_hex(a1));
                else neorv32_uart0_printf("twi probe <addr>\n");
            } else if (strcmp(a0, "read") == 0) {
                if (a1 && a2) cmd_twi_read((uint8_t)parse_hex(a1), (uint8_t)parse_hex(a2), a2 ? (int)parse_hex(a2) : 1);
                else neorv32_uart0_printf("twi read <addr> <reg> [len]\n");
            } else if (strcmp(a0, "write") == 0) {
                if (a1 && a2 && a2) {
                    // a1=addr, a2=reg, need a3=val
                    char *a3 = strtok(NULL, " ");
                    if (a3) cmd_twi_write((uint8_t)parse_hex(a1), (uint8_t)parse_hex(a2), (uint8_t)parse_hex(a3));
                    else neorv32_uart0_printf("twi write <addr> <reg> <val>\n");
                } else neorv32_uart0_printf("twi write <addr> <reg> <val>\n");
            } else if (strcmp(a0, "dump") == 0) {
                if (a1 && a2) cmd_twi_dump((uint8_t)parse_hex(a1), (uint8_t)parse_hex(a2), a2 ? (int)parse_hex(a2) : 16);
                else neorv32_uart0_printf("twi dump <addr> <start_reg> <len>\n");
            } else {
                neorv32_uart0_printf("twi: unknown subcommand '%s'\n", a0);
            }
        }
        // ── SPI COMMANDS ────────────────────────────────────────
        else if (strcmp(cmd, "spi") == 0) {
            if (a0 == NULL) {
                neorv32_uart0_printf("spi: need subcommand (cs|tx|cmd|read|jedec|status)\n");
            } else if (strcmp(a0, "cs") == 0) {
                if (a1) cmd_spi_cs((int)parse_hex(a1));
                else neorv32_uart0_printf("spi cs <0-3>\n");
            } else if (strcmp(a0, "tx") == 0) {
                if (a1) cmd_spi_tx((uint8_t)parse_hex(a1));
                else neorv32_uart0_printf("spi tx <byte>\n");
            } else if (strcmp(a0, "cmd") == 0) {
                if (a1) cmd_spi_cmd((uint8_t)parse_hex(a1));
                else neorv32_uart0_printf("spi cmd <byte>\n");
            } else if (strcmp(a0, "read") == 0) {
                if (a1) cmd_spi_read((int)parse_hex(a1));
                else cmd_spi_read(1);
            } else if (strcmp(a0, "jedec") == 0) {
                if (a1) cmd_spi_jedec((int)parse_hex(a1));
                else cmd_spi_jedec(3); // default flash CS3
            } else if (strcmp(a0, "status") == 0) {
                cmd_spi_status();
            } else {
                neorv32_uart0_printf("spi: unknown subcommand '%s'\n", a0);
            }
        }
        // ── GPIO COMMANDS ───────────────────────────────────────
        else if (strcmp(cmd, "gpio") == 0) {
            if (a0 == NULL) {
                cmd_gpio_status();
            } else if (strcmp(a0, "read") == 0) {
                cmd_gpio_read();
            } else if (strcmp(a0, "set") == 0) {
                if (a1 && a2) cmd_gpio_set((int)parse_hex(a1), (int)parse_hex(a2));
                else neorv32_uart0_printf("gpio set <pin> <0|1>\n");
            } else if (strcmp(a0, "status") == 0) {
                cmd_gpio_status();
            } else {
                neorv32_uart0_printf("gpio: unknown subcommand '%s'\n", a0);
            }
        }
        // ── PWM COMMANDS ────────────────────────────────────────
        else if (strcmp(cmd, "pwm") == 0) {
            if (a0 == NULL) {
                cmd_pwm_status();
            } else if (strcmp(a0, "set") == 0) {
                if (a1) cmd_pwm_set((int)parse_hex(a1));
                else neorv32_uart0_printf("pwm set <duty 0-255>\n");
            } else if (strcmp(a0, "status") == 0) {
                cmd_pwm_status();
            } else {
                neorv32_uart0_printf("pwm: unknown subcommand '%s'\n", a0);
            }
        }
        // ── MEM COMMANDS ────────────────────────────────────────
        else if (strcmp(cmd, "mem") == 0) {
            if (a0 == NULL) {
                neorv32_uart0_printf("mem: need subcommand (rd|wr)\n");
            } else if (strcmp(a0, "rd") == 0) {
                if (a1) cmd_mem_rd(parse_hex(a1), a2 ? (int)parse_hex(a2) : 16);
                else neorv32_uart0_printf("mem rd <addr> [count]\n");
            } else if (strcmp(a0, "wr") == 0) {
                if (a1 && a2) cmd_mem_wr(parse_hex(a1), parse_hex(a2));
                else neorv32_uart0_printf("mem wr <addr> <val>\n");
            } else {
                neorv32_uart0_printf("mem: unknown subcommand '%s'\n", a0);
            }
        }
        // ── SYSINFO ─────────────────────────────────────────────
        else if (strcmp(cmd, "sysinfo") == 0) {
            cmd_sysinfo();
        }
        // ── RESET ───────────────────────────────────────────────
        else if (strcmp(cmd, "reset") == 0) {
            cmd_reset();
        }
        // ── UNKNOWN ────────────────────────────────────────────
        else {
            neorv32_uart0_printf("Unknown command '%s'. Type 'help'.\n", cmd);
        }
    }

    return 0;
}

// ─────────────────────────────────────────────────────────────────────
// HELP
// ─────────────────────────────────────────────────────────────────────
void cmd_help(void) {
    neorv32_uart0_printf(
        "\n┌─────────── CodecBot Debug CLI ───────────┐\n"
        "│ TWI (I²C)                                 │\n"
        "│  twi scan          — bus scan 0x00–0x7F   │\n"
        "│  twi probe <addr>  — check ACK at addr    │\n"
        "│  twi read <a> <r> [len] — read register(s)│\n"
        "│  twi write <a> <r> <v> — write register   │\n"
        "│  twi dump <a> <s> <n> — dump n regs       │\n"
        "│                                            │\n"
        "│ SPI                                       │\n"
        "│  spi cs <0-3>      — assert CS (0=disp,    │\n"
        "│                       1=touch,2=SD,3=flash)│\n"
        "│  spi tx <byte>     — transfer byte, show RX│\n"
        "│  spi cmd <byte>    — command-mode transfer │\n"
        "│  spi read <n>      — read n RX bytes       │\n"
        "│  spi jedec [cs]    — read JEDEC ID         │\n"
        "│  spi status        — show CTRL flags       │\n"
        "│                                            │\n"
        "│ GPIO                                      │\n"
        "│  gpio [status]     — show GPIO registers   │\n"
        "│  gpio read         — read input pins       │\n"
        "│  gpio set <pin> <v> — set output pin       │\n"
        "│                                            │\n"
        "│ PWM                                       │\n"
        "│  pwm [status]      — show PWM config       │\n"
        "│  pwm set <duty>    — set duty 0-255        │\n"
        "│                                            │\n"
        "│ MEM                                       │\n"
        "│  mem rd <addr> [n] — hex dump n words      │\n"
        "│  mem wr <addr> <v> — write word            │\n"
        "│                                            │\n"
        "│ OTHER                                     │\n"
        "│  sysinfo           — dump SYSINFO          │\n"
        "│  reset             — software reset        │\n"
        "│  help              — this menu             │\n"
        "└────────────────────────────────────────────┘\n\n"
    );
}

// ─────────────────────────────────────────────────────────────────────
// TWI (I²C) COMMANDS
// ─────────────────────────────────────────────────────────────────────

void twi_start(void) {
    neorv32_twi_generate_start();
}

void twi_stop(void) {
    neorv32_twi_generate_stop();
}

int twi_send_byte(uint8_t data) {
    uint8_t d = data;
    int ack = neorv32_twi_transfer(&d, 0);
    return ack; // 0=ACK, 1=NACK
}

uint8_t twi_recv_byte(int ack) {
    uint8_t d = 0;
    neorv32_twi_transfer(&d, ack ? 0 : 1); // mack=0 for ACK, 1 for NACK
    return d;
}

void cmd_twi_scan(void) {
    if (!neorv32_twi_available()) {
        neorv32_uart0_printf("TWI not available!\n");
        return;
    }
    neorv32_uart0_printf("TWI Bus Scan (0x00–0x7F):\n");
    neorv32_uart0_printf("   ");
    int found = 0;
    for (int addr = 0; addr < 0x80; addr++) {
        twi_start();
        int ack = twi_send_byte((uint8_t)(addr << 1)); // write address
        twi_stop();

        if (ack == 0) {
            neorv32_uart0_printf("%02x ", addr);
            found++;
        } else {
            neorv32_uart0_printf("-- ");
        }
        if ((addr & 0x0F) == 0x0F) {
            neorv32_uart0_printf("\n   ");
        }
    }
    neorv32_uart0_printf("\nFound %d device(s).\n", found);
}

void cmd_twi_probe(uint8_t addr) {
    if (!neorv32_twi_available()) { neorv32_uart0_printf("TWI not available!\n"); return; }
    twi_start();
    int ack = twi_send_byte((uint8_t)(addr << 1));
    twi_stop();
    if (ack == 0) {
        neorv32_uart0_printf("Device 0x%02x: ACK (present)\n", addr);
    } else {
        neorv32_uart0_printf("Device 0x%02x: NACK (not found)\n", addr);
    }
}

void cmd_twi_read(uint8_t addr, uint8_t reg, int len) {
    if (!neorv32_twi_available()) { neorv32_uart0_printf("TWI not available!\n"); return; }
    if (len < 1) len = 1;
    if (len > 64) len = 64;

    // Write register address (no stop → repeated START for read)
    twi_start();
    int ack = twi_send_byte((uint8_t)(addr << 1)); // write
    if (ack != 0) {
        neorv32_uart0_printf("TWI: NACK on address 0x%02x\n", addr);
        twi_stop();
        return;
    }
    twi_send_byte(reg); // register number
    // Repeated START
    twi_start();
    twi_send_byte((uint8_t)((addr << 1) | 1)); // read

    neorv32_uart0_printf("TWI read 0x%02x reg 0x%02x: ", addr, reg);
    for (int i = 0; i < len; i++) {
        uint8_t val = twi_recv_byte(i < (len-1) ? 0 : 1); // ACK all but last
        neorv32_uart0_printf("%02x ", val);
    }
    neorv32_uart0_printf("\n");
    twi_stop();
}

void cmd_twi_write(uint8_t addr, uint8_t reg, uint8_t val) {
    if (!neorv32_twi_available()) { neorv32_uart0_printf("TWI not available!\n"); return; }
    twi_start();
    int ack = twi_send_byte((uint8_t)(addr << 1));
    if (ack != 0) {
        neorv32_uart0_printf("TWI: NACK on address 0x%02x\n", addr);
        twi_stop();
        return;
    }
    twi_send_byte(reg);
    twi_send_byte(val);
    twi_stop();
    neorv32_uart0_printf("TWI write 0x%02x reg 0x%02x = 0x%02x\n", addr, reg, val);
}

void cmd_twi_dump(uint8_t addr, uint8_t start, int len) {
    if (!neorv32_twi_available()) { neorv32_uart0_printf("TWI not available!\n"); return; }
    if (len < 1) len = 16;
    if (len > 64) len = 64;

    neorv32_uart0_printf("TWI dump 0x%02x from reg 0x%02x:\n", addr, start);
    for (int i = 0; i < len; i++) {
        uint8_t reg = start + i;
        twi_start();
        int ack = twi_send_byte((uint8_t)(addr << 1));
        if (ack != 0) {
            neorv32_uart0_printf("  reg 0x%02x: NACK (device gone?)\n", reg);
            twi_stop();
            return;
        }
        twi_send_byte(reg);
        twi_start();
        twi_send_byte((uint8_t)((addr << 1) | 1));
        uint8_t val = twi_recv_byte(1); // NACK last
        twi_stop();
        neorv32_uart0_printf("  reg 0x%02x = 0x%02x\n", reg, val);
    }
}

// ─────────────────────────────────────────────────────────────────────
// SPI COMMANDS
// ─────────────────────────────────────────────────────────────────────

void spi_setup_fast(void) {
    neorv32_spi_setup(SPI_PRSC_FAST, SPI_CDIV_FAST, 0, 0, 0);
}

void spi_setup_slow(void) {
    neorv32_spi_setup(SPI_PRSC_SLOW, SPI_CDIV_SLOW, 0, 0, 0);
}

void cmd_spi_cs(int cs) {
    if (!neorv32_spi_available()) { neorv32_uart0_printf("SPI not available!\n"); return; }
    if (cs < 0 || cs > 3) {
        neorv32_uart0_printf("spi cs: invalid CS %d (0-3)\n", cs);
        return;
    }
    neorv32_spi_cs_en(cs);
    neorv32_uart0_printf("SPI CS%d asserted.\n", cs);
    neorv32_uart0_printf("  (Use 'spi tx' or 'spi cmd', then CS auto-deasserts on next cs_en)\n");
}

void cmd_spi_tx(uint8_t data) {
    if (!neorv32_spi_available()) { neorv32_uart0_printf("SPI not available!\n"); return; }
    uint8_t rx = neorv32_spi_transfer(data);
    neorv32_uart0_printf("SPI TX 0x%02x → RX 0x%02x\n", data, rx);
}

void cmd_spi_cmd(uint8_t data) {
    if (!neorv32_spi_available()) { neorv32_uart0_printf("SPI not available!\n"); return; }
    // Command mode: write to DATA with CMD bit set
    // This controls CS automatically per the NeoRV32 SPI controller
    uint32_t cmd_word = (uint32_t)data;
    cmd_word |= (1 << SPI_DATA_CMD);  // command mode
    // CS is controlled by CSEN bits in the data register
    NEORV32_SPI->DATA = cmd_word;
    while (neorv32_spi_busy()); // wait
    uint8_t rx = (uint8_t)(NEORV32_SPI->DATA & 0xFF);
    neorv32_uart0_printf("SPI CMD 0x%02x → RX 0x%02x\n", data, rx);
}

void cmd_spi_read(int n) {
    if (!neorv32_spi_available()) { neorv32_uart0_printf("SPI not available!\n"); return; }
    if (n < 1) n = 1;
    if (n > 256) n = 256;
    neorv32_uart0_printf("SPI read %d bytes: ", n);
    for (int i = 0; i < n; i++) {
        // Send dummy byte to clock in data
        uint8_t rx = neorv32_spi_transfer(0xFF);
        neorv32_uart0_printf("%02x ", rx);
        if ((i & 0x0F) == 0x0F && i < n-1) neorv32_uart0_printf("\n  ");
    }
    neorv32_uart0_printf("\n");
}

void cmd_spi_jedec(int cs) {
    if (!neorv32_spi_available()) { neorv32_uart0_printf("SPI not available!\n"); return; }
    if (cs < 0 || cs > 3) { neorv32_uart0_printf("Invalid CS %d\n", cs); return; }

    neorv32_uart0_printf("SPI JEDEC ID on CS%d:\n", cs);
    neorv32_spi_cs_en(cs);

    // Send JEDEC ID command (0x9F)
    uint8_t rx0 = neorv32_spi_transfer(0x9F);
    uint8_t mfr = neorv32_spi_transfer(0xFF);
    uint8_t dev1 = neorv32_spi_transfer(0xFF);
    uint8_t dev2 = neorv32_spi_transfer(0xFF);

    neorv32_spi_cs_dis();

    neorv32_uart0_printf("  CMD 0x9F → RX 0x%02x\n", rx0);
    neorv32_uart0_printf("  MFR=0x%02x  DEV=0x%02x%02x\n", mfr, dev1, dev2);

    if (mfr == 0xFF && dev1 == 0xFF && dev2 == 0xFF) {
        neorv32_uart0_printf("  ⚠️ All 0xFF — device not responding (check wiring/power)\n");
    } else if (mfr == 0x00 && dev1 == 0x00 && dev2 == 0x00) {
        neorv32_uart0_printf("  ⚠️ All 0x00 — bus stuck low (check CS/pullups)\n");
    } else {
        neorv32_uart0_printf("  ✅ Device responded!\n");
    }
}

void cmd_spi_status(void) {
    if (!neorv32_spi_available()) { neorv32_uart0_printf("SPI not available!\n"); return; }
    uint32_t ctrl = NEORV32_SPI->CTRL;
    neorv32_uart0_printf("SPI CTRL = 0x%08x\n", ctrl);
    neorv32_uart0_printf("  EN=%d CPHA=%d CPOL=%d HIGHSPEED=%d\n",
        (ctrl>>0)&1, (ctrl>>1)&1, (ctrl>>2)&1, (ctrl>>10)&1);
    neorv32_uart0_printf("  RX_AVAIL=%d TX_EMPTY=%d TX_HALF=%d TX_FULL=%d\n",
        (ctrl>>16)&1, (ctrl>>17)&1, (ctrl>>18)&1, (ctrl>>19)&1);
    neorv32_uart0_printf("  CS_ACTIVE=%d BUSY=%d\n",
        (ctrl>>30)&1, (ctrl>>31)&1);
    neorv32_uart0_printf("  FIFO depth=%d\n", neorv32_spi_get_fifo_depth());
    neorv32_uart0_printf("  Clock speed=%u Hz\n", (uint32_t)neorv32_spi_get_clock_speed());
}

// ─────────────────────────────────────────────────────────────────────
// GPIO COMMANDS
// ─────────────────────────────────────────────────────────────────────

void cmd_gpio_read(void) {
    if (!neorv32_gpio_available()) { neorv32_uart0_printf("GPIO not available!\n"); return; }
    neorv32_uart0_printf("GPIO input pins:\n");
    for (int i = 0; i < 7; i++) {
        uint32_t val = neorv32_gpio_pin_get(i);
        neorv32_uart0_printf("  pin %d = %d\n", i, (int)val);
    }
}

void cmd_gpio_set(int pin, int val) {
    if (!neorv32_gpio_available()) { neorv32_uart0_printf("GPIO not available!\n"); return; }
    if (pin < 0 || pin > 6) {
        neorv32_uart0_printf("gpio set: pin %d out of range (0-6)\n", pin);
        return;
    }
    neorv32_gpio_pin_set(pin, val);
    neorv32_uart0_printf("GPIO pin %d = %d\n", pin, val);
}

void cmd_gpio_status(void) {
    if (!neorv32_gpio_available()) { neorv32_uart0_printf("GPIO not available!\n"); return; }
    neorv32_uart0_printf("GPIO pins:\n");
    for (int i = 0; i < 7; i++) {
        uint32_t val = neorv32_gpio_pin_get(i);
        neorv32_uart0_printf("  pin %d = %d\n", i, (int)val);
    }
}

// ─────────────────────────────────────────────────────────────────────
// PWM COMMANDS
// ─────────────────────────────────────────────────────────────────────

void cmd_pwm_set(int duty) {
    if (!neorv32_pwm_available()) { neorv32_uart0_printf("PWM not available!\n"); return; }
    if (duty < 0) duty = 0;
    if (duty > 255) duty = 255;
    // PWM channel 0: set duty cycle
    uint32_t cfg = (uint32_t)(duty & 0xFF);
    cfg |= (uint32_t)(4 << 8);  // CDIV=4 (simple divider)
    NEORV32_PWM->CHANNEL_CFG[0] = cfg;
    neorv32_uart0_printf("PWM ch0 duty = %d/255 (%.1f%%)\n", duty, duty*100.0/255.0);
}

void cmd_pwm_status(void) {
    if (!neorv32_pwm_available()) { neorv32_uart0_printf("PWM not available!\n"); return; }
    uint32_t cfg = NEORV32_PWM->CHANNEL_CFG[0];
    int duty = (int)(cfg & 0xFF);
    int cdiv = (int)((cfg >> 8) & 0x3FF);
    neorv32_uart0_printf("PWM ch0: duty=%d/255 cdiv=%d\n", duty, cdiv);
}

// ─────────────────────────────────────────────────────────────────────
// MEMORY COMMANDS
// ─────────────────────────────────────────────────────────────────────

void cmd_mem_rd(uint32_t addr, int n) {
    if (n < 1) n = 1;
    if (n > 256) n = 256;
    neorv32_uart0_printf("MEM dump 0x%08x (%d words):\n", addr, n);
    for (int i = 0; i < n; i++) {
        if ((i & 0x03) == 0) {
            neorv32_uart0_printf("  %08x: ", addr + i*4);
        }
        uint32_t val = *(volatile uint32_t*)(addr + i*4);
        neorv32_uart0_printf("%08x ", val);
        if ((i & 0x03) == 0x03) neorv32_uart0_printf("\n");
    }
    if ((n & 0x03) != 0) neorv32_uart0_printf("\n");
}

void cmd_mem_wr(uint32_t addr, uint32_t val) {
    *(volatile uint32_t*)addr = val;
    neorv32_uart0_printf("MEM write 0x%08x = 0x%08x\n", addr, val);
    // Readback verify
    uint32_t rb = *(volatile uint32_t*)addr;
    if (rb == val) {
        neorv32_uart0_printf("  Readback OK: 0x%08x\n", rb);
    } else {
        neorv32_uart0_printf("  ⚠️ Readback MISMATCH: 0x%08x\n", rb);
    }
}

// ─────────────────────────────────────────────────────────────────────
// SYSINFO
// ─────────────────────────────────────────────────────────────────────

void cmd_sysinfo(void) {
    neorv32_uart0_printf("SYSINFO @ 0xFFFE0000:\n");
    neorv32_uart0_printf("  CLK:     %u Hz (%u MHz)\n",
        (uint32_t)NEORV32_SYSINFO->CLK,
        (uint32_t)(NEORV32_SYSINFO->CLK / 1000000));
    neorv32_uart0_printf("  SOC:     0x%08x\n", (uint32_t)NEORV32_SYSINFO->SOC);
    neorv32_uart0_printf("  CACHE:   0x%08x\n", (uint32_t)NEORV32_SYSINFO->CACHE);
    neorv32_uart0_printf("  IMEM:    %u bytes\n", (uint32_t)(1 << NEORV32_SYSINFO->MISC[SYSINFO_MISC_IMEM]));
    neorv32_uart0_printf("  DMEM:    %u bytes\n", (uint32_t)(1 << NEORV32_SYSINFO->MISC[SYSINFO_MISC_DMEM]));
    neorv32_uart0_printf("  HARTs:   %u\n", (uint32_t)NEORV32_SYSINFO->MISC[SYSINFO_MISC_HART]);
    neorv32_uart0_printf("  BOOT:    %u\n", (uint32_t)NEORV32_SYSINFO->MISC[SYSINFO_MISC_BOOT]);
    neorv32_uart0_printf("  MIMPID:  0x%08x\n", (uint32_t)neorv32_cpu_csr_read(CSR_MIMPID));
}

// ─────────────────────────────────────────────────────────────────────
// RESET
// ─────────────────────────────────────────────────────────────────────

void cmd_reset(void) {
    neorv32_uart0_printf("Resetting...\n");
    neorv32_cpu_csr_write(CSR_MIE, 0); // disable interrupts
    // Software reset via watchdog or direct jump to reset vector
    // Use the bootloader entry point
    void (*reset_vec)(void) = (void(*)(void))0xFFE00000;
    reset_vec();
}

// ─────────────────────────────────────────────────────────────────────
// UTILITY: Parse hex string to uint32
// ─────────────────────────────────────────────────────────────────────

uint32_t parse_hex(const char *s) {
    if (s == NULL) return 0;
    uint32_t val = 0;
    while (*s) {
        char c = *s++;
        val <<= 4;
        if (c >= '0' && c <= '9')      val |= (c - '0');
        else if (c >= 'a' && c <= 'f') val |= (c - 'a' + 10);
        else if (c >= 'A' && c <= 'F') val |= (c - 'A' + 10);
        else break;
    }
    return val;
}
