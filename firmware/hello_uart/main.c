// ================================================================================ //
// hello_uart — First NeoRV32 Firmware
//
// Prints system info over UART0, then echoes characters.
// Build: make NEORV32_HOME=../../.. clean_all exe
// Flash: JLinkExe -device RISC-V -if JTAG -speed 4000 -autoconnect 1
//          -JTAGConf "-1,-1" -CommanderScript flash.jlink
// ================================================================================ //

#include <neorv32.h>

// ── Main ──────────────────────────────────────────────────────
int main(void) {

  // capture CPU clock from SYSINFO
  uint32_t clk = neorv32_sysinfo_get_clk();

  neorv32_uart0_puts("\n========================================\n");
  neorv32_uart0_puts(" Hello from NeoRV32!\n");
  neorv32_uart0_puts("========================================\n");

  neorv32_uart0_printf("CPU clock: %u Hz\n", clk);

  neorv32_uart0_printf("ISA (MISA):  %x\n", neorv32_cpu_csr_read(CSR_MISA));
  neorv32_uart0_printf("ISA (MXISA): %x\n", neorv32_cpu_csr_read(CSR_MXISA));

  neorv32_uart0_printf("IMEM size: %u bytes\n", neorv32_sysinfo_get_imemsize());
  neorv32_uart0_printf("DMEM size: %u bytes\n", neorv32_sysinfo_get_dmemsize());

  neorv32_uart0_puts("\nEcho test — type something:\n> ");

  // ── Echo loop ─────────────────────────────────────────────
  while (1) {
    if (neorv32_uart0_available()) {
      char c = neorv32_uart0_char_received();
      neorv32_uart0_putc(c);

      if (c == '\r') {
        neorv32_uart0_puts("\n> ");
      }
    }
  }

  return 0;
}
