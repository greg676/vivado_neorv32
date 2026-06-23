# LOOM Project Status

**Last Updated:** 2026-06-22 18:15 PDT  
**Repository:** greg676/vivado_neorv32  
**Branch:** main

---

## Overall Status: 🟡 In Development

The three-pillar system is structurally complete. Hardware platform works. Application design is documented. AI infrastructure is operational but needs MCP tool refinement.

---

## Pillar 1: LOOM Application 🚧 Design Phase

| Component | Status | Location |
|-----------|--------|----------|
| Master Architecture | ✅ Complete | `applications/loom/docs/LOOM_by_opus48.md` |
| 12 Design Documents | ✅ Complete | `applications/loom/docs/00-VISION.md` - `11-BUILD-PLAN.md` |
| DSP Architecture | ✅ Complete | Software-defined, time-multiplexed MAC |
| RTL Implementation | 📋 Not Started | `applications/loom/rtl/` empty |
| Firmware | 📋 Not Started | `applications/loom/firmware/` empty |

**Key Decision:** Partial Reconfiguration abandoned in favor of software-defined DSP. One MAC engine serves all channels via coefficient tables in BRAM.

---

## Pillar 2: Alchitry Platinum V2 Platform ✅ Working

| Component | Status | Details |
|-----------|--------|---------|
| NeoRV32 Boot | ✅ Working | v29 debug console firmware |
| UART Console | ✅ Working | 19200 baud on /dev/ttyUSB0 |
| I²C (CS42448) | ✅ Working | Codec responding at 0x4A |
| GPIO Control | ✅ Working | RSTCN, CLK_EN, address pins |
| DDR3 | ✅ Present | 256MB via MIG, not yet tested |
| SPI Display | ⚠️ Partial | RST sequence works, ID read fails |
| SPI Flash | 📋 Not Soldered | W25Q64 footprint empty |
| SD Card | 📋 Not Tested | CS1 on SPI |
| FT601 USB3.0 | 📋 Not Implemented | Hardware present, no RTL |

**Known Issues:**
- Display ID read returns 0x00 0x00 0x00 (possible 5V vs 3.3V issue)
- Display commands work, just can't identify chip

---

## Pillar 3: ADS+MCP Infrastructure ⚠️ Operational

| Component | Status | Details |
|-----------|--------|---------|
| Open WebUI | ✅ Running | Port 8080, data on /mnt/data-1tb |
| Ollama R7 | ✅ Running | qwen3.6:27b-r7, rnj-1-r5:latest, etc. |
| Ollama R5 | ✅ Running | RX 6600, embeddings + fallback |
| mcpo Bridge | ✅ Running | Port 8200, all 4 servers connected |
| Filesystem MCP | ✅ Working | Read/write/search tools |
| GitHub MCP | ✅ Working | Issues, PRs, commits |
| Browser MCP | ✅ Working | Puppeteer automation |
| Hardware-Debug MCP | ⚠️ Partial | Server runs, needs parameter schemas |

**Blocking Issue:** MCP tool parameter schemas are empty in OpenAPI spec. Tools can't be called from OWUI with arguments.

---

## GitHub Integration ✅ Working

| Component | Status |
|-----------|--------|
| Repository | ✅ greg676/vivado_neorv32 |
| Save Script | ✅ `platforms/alchitry-platinum-v2/scripts/save-to-github.sh` |
| Commit Workflow | ✅ Sync → Stage → Diff → Commit → Push |
| History | ✅ Clean conventional commits |

---

## Next Steps

### Immediate (This Week)

1. **Fix MCP parameter schemas** — Enable tool arguments from OWUI
2. **Test hardware-debug tools** — Verify UART communication via MCP
3. **Begin LOOM RTL** — Start with TDM audio fabric template

### Short Term (Next 2 Weeks)

4. **FT601 RTL** — USB3.0 FIFO interface for audio streaming
5. **DSP Core** — Time-multiplexed MAC engine
6. **Display Driver** — Debug ILI9341 ID read issue

### Medium Term (Next Month)

7. **Instrument Separator** — DUET algorithm on FPGA
8. **Recording Pipeline** — SD card + DDR3 storage
9. **Touch UI** — Menu system on NeoRV32

---

## Blockers

| Issue | Impact | Workaround |
|-------|--------|------------|
| MCP parameter schemas | Can't use hw.i2c_write, etc. | Direct UART terminal for now |
| Display ID read | Can't auto-detect display | Hardcode ILI9341 init sequence |
| Flash not soldered | Can't store persistent config | Use DDR3 for now |

---

## Resource Budget (Alchitry Pt V2)

| Resource | Used | Total | % |
|----------|------|-------|---|
| LUTs | ~8,000 | 63,400 | 13% |
| FFs | ~12,000 | 126,800 | 9% |
| BRAM | ~50 kb | 4.86 Mb | 1% |
| DSP48 | 4 | 240 | 2% |
| MMCM | 3 | 6 | 50% |

*Note: LOOM application will significantly increase utilization*

---

## Documentation Status

| Document | Location | Status |
|----------|----------|--------|
| This status file | `PROJECT-STATUS.md` | ✅ Current |
| Main README | `README.md` | ✅ Updated for unified structure |
| LOOM Architecture | `applications/loom/docs/` | ✅ Complete |
| ADS+MCP | `infrastructure/ads-mcp/docs/` | ✅ Complete |
| Hardware Debug | `platforms/alchitry-platinum-v2/doc/` | ✅ Complete |

---

## Contact

- **Development:** R7 (gj-007, 10.0.0.50)
- **Mesh:** claw-studio.tail708254.ts.net
- **GitHub:** https://github.com/greg676/vivado_neorv32
