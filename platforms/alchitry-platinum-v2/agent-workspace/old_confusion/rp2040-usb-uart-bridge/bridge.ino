// RP2040 Zero USB-UART Passthrough Bridge
// Serial  = USB CDC (host console)
// Serial1 = UART0 GP0(TX), GP1(RX) → FPGA NeoRV32
// Baud: 19200 (NeoRV32 bootloader default)

void setup() {
  Serial.begin(115200);   // USB to host
  Serial1.begin(19200);   // UART to FPGA
}

void loop() {
  if (Serial.available()) {
    Serial1.write(Serial.read());
  }
  if (Serial1.available()) {
    Serial.write(Serial1.read());
  }
}
