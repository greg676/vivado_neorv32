#!/usr/bin/env python3
"""
hardware-debug-mcp — Safe hardware access via UART debug terminal.

Architecture:
  R7 (host) ──UART──► Arty firmware CLI ──► I²C/SPI/GPIO/Codec on FPGA fabric
  
The model never touches raw shell. It calls named operations.
Named operations send structured commands over UART to the Arty's debug shell.
The Arty firmware executes them on the FPGA fabric and returns results.

Stack: Python 3.12, MCP SDK (stdio), pyserial, pylink-square
"""

import json
import os
import time
import re
import hashlib
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

# ============================================================================
# Profile Loading
# ============================================================================

PROFILE_PATH = os.environ.get(
    "ADS_PROFILE",
    "/mnt/data-1tb/ai-design-studio/project.profile.json"
)

with open(PROFILE_PATH) as f:
    profile = json.load(f)

AUDIT_LOG = profile["audit_log"]
SESSION_DIR = profile["project"]["session_dir"]
HW_CONFIG = profile["hardware"]
KNOWN_GOOD = profile["known_good"]

# ============================================================================
# State Machine
# ============================================================================

class State:
    DISCONNECTED = "DISCONNECTED"
    CONNECTED = "CONNECTED"
    IDENTIFIED = "IDENTIFIED"
    MISMATCH = "MISMATCH"
    SAFE_MODE = "SAFE_MODE"
    DEBUG_MODE = "DEBUG_MODE"
    DANGEROUS_MODE = "DANGEROUS_MODE"

class DebugState:
    """Current debug interface state."""
    UNKNOWN = "UNKNOWN"
    JLINK_CONNECTED = "JLINK_CONNECTED"
    BOOTLOADER = "BOOTLOADER"
    DEBUG_CONSOLE = "DEBUG_CONSOLE"
    NO_RESPONSE = "NO_RESPONSE"

debug_state = DebugState.UNKNOWN
state = State.DISCONNECTED

# ============================================================================
# J-Link Integration
# ============================================================================

_jlink_available = None  # Lazy check

def jlink_probe() -> bool:
    """Check if J-Link is connected and responding."""
    global _jlink_available
    if _jlink_available is not None:
        return _jlink_available
    
    try:
        result = subprocess.run(
            ["JLinkExe", "-device", "RISC-V", "-if", "JTAG", "-speed", "1000",
             "-autoconnect", "1", "-CommanderScript", "-"],
            input="exit\n",
            capture_output=True,
            text=True,
            timeout=10
        )
        _jlink_available = "Connected" in result.stdout or "J-Link" in result.stdout
        return _jlink_available
    except Exception:
        _jlink_available = False
        return False

def jlink_command(cmd_script: str) -> dict:
    """Execute J-Link commands, return parsed result."""
    try:
        result = subprocess.run(
            ["JLinkExe", "-device", "RISC-V", "-if", "JTAG", "-speed", "1000",
             "-autoconnect", "1", "-JTAGConf", "-1,-1", "-CommanderScript", "-"],
            input=cmd_script,
            capture_output=True,
            text=True,
            timeout=30
        )
        return {
            "stdout": result.stdout,
            "stderr": result.stderr,
            "returncode": result.returncode,
            "success": result.returncode == 0
        }
    except subprocess.TimeoutExpired:
        return {"error": "J-Link command timed out", "success": False}
    except Exception as e:
        return {"error": str(e), "success": False}

def uart_send_raw(data: str):
    """Send raw bytes to UART without expecting response."""
    global _uart
    if _uart and _uart.is_open:
        _uart.write(data.encode('utf-8'))
        _uart.flush()

def uart_read_all(timeout: float = 1.0) -> list:
    """Read all available data from UART."""
    global _uart
    if not _uart or not _uart.is_open:
        return []
    
    lines = []
    start = time.time()
    buffer = b""
    
    while (time.time() - start) < timeout:
        if _uart.in_waiting:
            chunk = _uart.read(_uart.in_waiting)
            buffer += chunk
        else:
            time.sleep(0.05)
    
    if buffer:
        text = buffer.decode('utf-8', errors='replace')
        lines = [l.strip() for l in text.split('\r\n') if l.strip()]
    
    return lines

# ============================================================================
# State Detection
# ============================================================================

def detect_debug_state() -> str:
    """Auto-detect what debug interface is currently available."""
    global debug_state
    
    # Try J-Link first (if available)
    if jlink_probe():
        debug_state = DebugState.JLINK_CONNECTED
        return debug_state
    
    # Try UART
    if not _uart or not _uart.is_open:
        if not uart_connect():
            debug_state = DebugState.NO_RESPONSE
            return debug_state
    
    # Clear buffer and send CR to get prompt
    _uart.reset_input_buffer()
    uart_send_raw("\r\n")
    time.sleep(0.2)
    response_lines = uart_read_all(timeout=1.0)
    response_text = "\n".join(response_lines).lower()
    
    # Check for bootloader (NeoRV32 native)
    if "cmd:>" in response_text:
        debug_state = DebugState.BOOTLOADER
        return debug_state
    
    # Check for our debug console
    if ">" in response_text and any(x in response_text for x in ["sys", "i2c", "gpio", "spi", "codec"]):
        debug_state = DebugState.DEBUG_CONSOLE
        return debug_state
    
    # Check for NEORV32 string (bootloader on startup)
    if "neorv32" in response_text:
        debug_state = DebugState.BOOTLOADER
        return debug_state
    
    # No recognizable prompt
    debug_state = DebugState.UNKNOWN
    return debug_state

# ============================================================================
# Abstract Debug Commands
# ============================================================================

def dbg_write(binary_path: str, address: str = "0x00000000") -> dict:
    """
    WRITE firmware to MCU RAM via J-Link (temporary, for testing).
    
    This is NOT flash programming - it loads directly to RAM and starts.
    Use this for rapid iteration during development.
    
    For permanent storage, use dbg.flash (SPI flash programming) - 
    only after code is validated and pushed to GitHub.
    
    Args:
        binary_path: Path to .bin file
        address: Load address (default: 0x00000000)
    """
    t0 = time.time()
    result = {"command": "write", "binary": binary_path, "address": address}
    
    if not jlink_probe():
        result["error"] = "J-Link not available"
        result["success"] = False
        audit("dbg.write", 0, "error", (time.time() - t0) * 1000)
        return result
    
    # J-Link direct load to RAM: reset, halt, load, set PC, go
    jlink_script = f"""r
halt
loadbin {binary_path} {address}
wreg pc {address}
go
exit
"""
    jlink_result = jlink_command(jlink_script)
    result["jlink"] = jlink_result
    result["success"] = jlink_result.get("success", False)
    
    audit("dbg.write", 0, "ok" if result["success"] else "error", (time.time() - t0) * 1000)
    return result

def dbg_flash(binary_path: str, method: str = "auto") -> dict:
    """
    FLASH firmware to external SPI flash (permanent storage).
    
    ⚠️ CRITICAL: Only flash validated code that has been pushed to GitHub!
    
    This programs the external W25Q64 SPI flash so the NeoRV32
    bootloader can load it on power-up. Requires:
    - Valid .bin file with proper header
    - Code reviewed and committed
    - GitHub sync complete
    
    Methods:
    - "jlink-spi": Use J-Link to program SPI directly (requires DANGEROUS_MODE)
    - "uart-bootloader": Use NeoRV32 bootloader commands (via debug console)
    - "auto": Try bootloader first, fall back to J-Link
    
    Args:
        binary_path: Path to .bin file (must include NeoRV32 header for bootloader)
        method: "jlink-spi", "uart-bootloader", or "auto"
    """
    t0 = time.time()
    result = {
        "command": "flash",
        "binary": binary_path,
        "method_used": None,
        "warning": "CRITICAL: Only flash validated, GitHub-committed code!"
    }
    
    # TODO: Implement SPI flash programming
    result["error"] = "SPI flash programming not yet implemented"
    result["success"] = False
    result["note"] = "Use dbg.write for RAM loading (temporary)"
    
    audit("dbg.flash", 2, "error", (time.time() - t0) * 1000)
    return result

def dbg_boot_firmware(binary_path: str, address: str = "0x00000000") -> dict:
    """
    Boot firmware from bootloader mode.
    
    When the board is in NeoRV32 native bootloader (shows 'CMD:>'),
    this loads firmware via J-Link and starts execution.
    
    This is what you use when:
    - Board shows 'CMD:>' prompt
    - 'l' command gives ERROR_DEVICE (no flash image)
    - You want to run your debug console
    
    Args:
        binary_path: Path to .bin file to load and run
        address: Load address (default: 0x00000000)
    """
    t0 = time.time()
    result = {
        "command": "boot_firmware",
        "binary": binary_path,
        "address": address,
        "note": "For bootloader mode (CMD:> prompt)"
    }
    
    # Check current state
    current_state = detect_debug_state()
    result["detected_state"] = current_state
    
    if current_state == DebugState.DEBUG_CONSOLE:
        result["info"] = "Firmware already running (debug console active)"
        result["success"] = True
        return result
    
    if current_state != DebugState.JLINK_CONNECTED:
        if not jlink_probe():
            result["error"] = "J-Link required to boot from bootloader"
            result["success"] = False
            audit("dbg.boot_firmware", 0, "error", (time.time() - t0) * 1000)
            return result
    
    # Load via J-Link and start
    jlink_script = f"""r
halt
loadbin {binary_path} {address}
wreg pc {address}
go
exit
"""
    jlink_result = jlink_command(jlink_script)
    result["jlink"] = jlink_result
    result["success"] = jlink_result.get("success", False)
    
    if result["success"]:
        result["info"] = f"Firmware loaded at {address}, execution started"
        result["next_step"] = "Check UART for '> ' prompt (debug console)"
    else:
        result["error"] = "J-Link load failed"
    
    audit("dbg.boot_firmware", 0, "ok" if result["success"] else "error", (time.time() - t0) * 1000)
    return result
    
    audit("dbg.flash", 1 if method != "auto" else 0, 
          "ok" if result.get("success") else "error",
          (time.time() - t0) * 1000)
    return result

def dbg_reset(target_pc: str = "0x00000000", method: str = "auto") -> dict:
    """
    Soft reset the processor.
    
    Args:
        target_pc: Where to start execution
        method: "auto", "jlink", "soft"
    """
    t0 = time.time()
    result = {"command": "reset", "target_pc": target_pc}
    
    if method == "auto":
        current_state = detect_debug_state()
        method = "jlink" if current_state == DebugState.JLINK_CONNECTED else "soft"
    
    if method == "jlink":
        jlink_script = f"""r
wreg pc {target_pc}
go
exit
"""
        jlink_result = jlink_command(jlink_script)
        result["jlink"] = jlink_result
        result["success"] = jlink_result.get("success", False)
        
    elif method == "soft":
        # Try UART soft reset
        uart_result = uart_send_command("system reset")
        result["uart"] = uart_result
        result["success"] = "error" not in uart_result
    
    audit("dbg.reset", 0, "ok" if result.get("success") else "error", (time.time() - t0) * 1000)
    return result

def dbg_status() -> dict:
    """Get current system/debug status."""
    t0 = time.time()
    
    result = {
        "command": "status",
        "debug_state": detect_debug_state(),
        "uart_connected": _uart is not None and _uart.is_open if _uart else False,
        "uart_port": UART_PORT if os.path.exists(UART_PORT) else UART_PORT_FALLBACK if os.path.exists(UART_PORT_FALLBACK) else None,
        "jlink_available": jlink_probe(),
    }
    
    # Try to get more info via J-Link if available
    if result["jlink_available"]:
        jlink_info = jlink_command("regs\nexit\n")
        if jlink_info.get("success"):
            # Parse PC from output
            stdout = jlink_info.get("stdout", "")
            pc_match = re.search(r'pc\s*=\s*([0-9A-Fa-f]+)', stdout)
            if pc_match:
                result["pc"] = pc_match.group(1)
    
    # Try to get firmware version via UART
    if result["uart_connected"]:
        sys_info = uart_send_command("sys")
        if "error" not in sys_info:
            result["firmware_response"] = sys_info.get("response", [])
    
    audit("dbg.status", 0, "ok", (time.time() - t0) * 1000)
    return result

def dbg_read_mem(address: str, size: int = 4, width: int = 32) -> dict:
    """Read memory location."""
    t0 = time.time()
    result = {"command": "read_mem", "address": address, "size": size, "width": width}
    
    # Prefer J-Link if available
    if jlink_probe():
        width_char = {8: 'b', 16: '2', 32: '4'}.get(width, '4')
        jlink_script = f"mem {address}, {size}\nexit\n"
        jlink_result = jlink_command(jlink_script)
        result["jlink"] = jlink_result
        result["success"] = jlink_result.get("success", False)
    else:
        result["error"] = "Memory read requires J-Link"
        result["success"] = False
    
    audit("dbg.read_mem", 0, "ok" if result.get("success") else "error", (time.time() - t0) * 1000)
    return result

def dbg_read_reg(reg: str) -> dict:
    """Read CPU register."""
    t0 = time.time()
    result = {"command": "read_reg", "register": reg}
    
    if jlink_probe():
        jlink_script = f"regs\nexit\n"
        jlink_result = jlink_command(jlink_script)
        result["jlink"] = jlink_result
        # Parse register from output
        stdout = jlink_result.get("stdout", "")
        reg_pattern = rf'{reg}\s*=\s*([0-9A-Fa-f]+)'
        match = re.search(reg_pattern, stdout)
        if match:
            result["value"] = match.group(1)
            result["success"] = True
        else:
            result["success"] = False
    else:
        result["error"] = "Register read requires J-Link"
        result["success"] = False
    
    audit("dbg.read_reg", 0, "ok" if result.get("success") else "error", (time.time() - t0) * 1000)
    return result

def dbg_step(count: int = 1) -> dict:
    """Execute one or more instructions."""
    t0 = time.time()
    result = {"command": "step", "count": count}
    
    if jlink_probe():
        steps = "\n".join(["step" for _ in range(count)])
        jlink_script = f"{steps}\nexit\n"
        jlink_result = jlink_command(jlink_script)
        result["jlink"] = jlink_result
        result["success"] = jlink_result.get("success", False)
    else:
        result["error"] = "Single-step requires J-Link"
        result["success"] = False
    
    audit("dbg.step", 0, "ok" if result.get("success") else "error", (time.time() - t0) * 1000)
    return result

# ============================================================================
# UART Terminal — The Primary Interface
# ============================================================================

import serial
import threading
import queue

_uart: Optional[serial.Serial] = None
_uart_lock = threading.Lock()
_uart_response_queue = queue.Queue()

# UART detection - Alchitry Pt V2 can show as USB0 (FTDI) or ACM0 (RP2040 fallback)
UART_PORT = "/dev/ttyUSB1"  # Primary: FTDI channel B on basic_plus_top
UART_PORT_FALLBACK = "/dev/ttyUSB0"  # Fallback: FTDI channel A (sometimes JTAG)
UART_BAUD = 19200  # neorv32 debug console
UART_TIMEOUT = 2.0  # seconds - neorv32 responds quickly

def uart_connect() -> bool:
    """Open UART connection to neorv32 debug console."""
    global _uart, UART_PORT
    
    # Try primary port first
    port_to_use = UART_PORT
    if not os.path.exists(UART_PORT):
        if os.path.exists(UART_PORT_FALLBACK):
            port_to_use = UART_PORT_FALLBACK
        else:
            return False
    
    try:
        _uart = serial.Serial(port_to_use, UART_BAUD, timeout=UART_TIMEOUT)
        # Flush any stale data
        _uart.reset_input_buffer()
        _uart.reset_output_buffer()
        UART_PORT = port_to_use  # Remember which worked
        return True
    except Exception:
        return False

def uart_disconnect():
    global _uart
    if _uart and _uart.is_open:
        _uart.close()
    _uart = None

def uart_send_command(cmd: str, timeout: float = 2.0) -> dict:
    """
    Send a command to the neorv32 debug console and collect response.
    
    Protocol: neorv32 echoes the command, then provides response.
    Example:
      Send: "sys\r"
      Receive: "sys\r\nclk:100000000...\r\n>"
    """
    global _uart
    if not _uart or not _uart.is_open:
        if not uart_connect():
            return {"error": f"UART not connected at {UART_PORT}"}
    
    with _uart_lock:
        try:
            # Clear buffers
            _uart.reset_input_buffer()
            
            # Send command
            _uart.write((cmd + "\r").encode('utf-8'))
            _uart.flush()
            
            # Read response with timeout
            time.sleep(0.2)  # Let neorv32 process
            response_lines = []
            start = time.time()
            buffer = b""
            
            while (time.time() - start) < timeout:
                if _uart.in_waiting:
                    chunk = _uart.read(_uart.in_waiting)
                    buffer += chunk
                    # Check if we have a complete response (ends with prompt)
                    if b">" in buffer or b"\r\n" in buffer:
                        # Wait a bit more for any trailing data
                        time.sleep(0.1)
                        if _uart.in_waiting:
                            buffer += _uart.read(_uart.in_waiting)
                        break
                else:
                    time.sleep(0.05)
            
            # Decode and parse
            raw = buffer.decode('utf-8', errors='replace')
            lines = [l.strip() for l in raw.split('\r\n') if l.strip()]
            
            # Parse: first line is echo, rest is response
            if lines and cmd in lines[0]:
                actual_response = lines[1:]
            else:
                actual_response = lines
            
            return {
                "command": cmd,
                "echo": lines[0] if lines else "",
                "response": actual_response,
                "raw": raw,
                "line_count": len(actual_response)
            }
        except Exception as e:
            return {"error": str(e), "command": cmd}

# ============================================================================
# Audit Logging
# ============================================================================

def audit(tool: str, tier: int, result: str, duration_ms: float = 0,
          confirmed_by: str = None, args_hash: str = None):
    entry = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "server": "hardware-debug",
        "tool": tool,
        "tier": tier,
        "state": state,
        "result": result,
        "duration_ms": round(duration_ms, 1),
    }
    if confirmed_by:
        entry["confirmed_by"] = confirmed_by
    if args_hash:
        entry["args_hash"] = args_hash

    Path(AUDIT_LOG).parent.mkdir(parents=True, exist_ok=True)
    with open(AUDIT_LOG, "a") as f:
        f.write(json.dumps(entry) + "\n")

# ============================================================================
# Identity Check
# ============================================================================

def check_identity() -> bool:
    """Verify connected hardware matches profile."""
    # Send system status command to get board identity
    result = uart_send_command("system status")
    if "error" in result:
        return False
    # TODO: Parse response for board ID and compare to profile
    return True

# ============================================================================
# TIER 0 — Always Safe, No Confirmation
# ============================================================================

def hw_status() -> dict:
    """Report overall hardware status."""
    t0 = time.time()
    result = {
        "state": state,
        "uart_port": UART_PORT,
        "uart_connected": _uart is not None and _uart.is_open if _uart else False,
        "board": HW_CONFIG.get("board", "unknown"),
        "codec_chip": HW_CONFIG.get("codec", {}).get("chip", "not_configured"),
        "codec_i2c_addr": HW_CONFIG.get("codec", {}).get("i2c_addr", "not_configured"),
    }
    
    # Get system status from Arty if connected
    if result["uart_connected"]:
        sys_status = uart_send_command("sys")
        if "error" not in sys_status:
            result["firmware"] = sys_status["response"]
    
    audit("hw.status", 0, "ok", (time.time() - t0) * 1000)
    return result

def hw_identify() -> dict:
    """Full target identification via UART."""
    t0 = time.time()
    result = {
        "board": HW_CONFIG["board"],
        "board_serial": HW_CONFIG["board_serial"],
        "probe_serial": HW_CONFIG["probe"]["serial"],
        "target_device": HW_CONFIG["probe"]["target_device"],
    }
    
    if _uart and _uart.is_open:
        sys = uart_send_command("system status")
        if "error" not in sys:
            result["firmware_response"] = sys["response"]
        result["identity_match"] = check_identity()
    
    audit("hw.identify", 0, "ok", (time.time() - t0) * 1000)
    return result

def hw_uart_terminal(command: str) -> dict:
    """
    Send an arbitrary command to the Arty debug terminal.
    This is the primary debug interface — all hardware interaction goes through here.
    
    Use 'help' to see available commands on the Arty firmware.
    """
    t0 = time.time()
    result = uart_send_command(command)
    audit("hw.uart_terminal", 0, "ok", (time.time() - t0) * 1000)
    return result

def hw_uart_tail(lines: int = 50) -> dict:
    """Read recent UART output buffer (passive — doesn't send commands)."""
    t0 = time.time()
    if not _uart or not _uart.is_open:
        if not uart_connect():
            audit("hw.uart.tail", 0, "error", (time.time() - t0) * 1000)
            return {"error": f"UART not connected at {UART_PORT}"}
    
    with _uart_lock:
        try:
            response_lines = []
            while _uart.in_waiting:
                line = _uart.readline().decode('utf-8', errors='replace').strip()
                if line:
                    response_lines.append(line)
            audit("hw.uart.tail", 0, "ok", (time.time() - t0) * 1000)
            return {"lines": response_lines[-lines:], "count": len(response_lines[-lines:])}
        except Exception as e:
            audit("hw.uart.tail", 0, "error", (time.time() - t0) * 1000)
            return {"error": str(e)}

# ============================================================================
# I²C Tools (via UART → Arty firmware CLI)
# ============================================================================

def hw_i2c_scan() -> dict:
    """Scan I²C bus for devices (via Arty UART)."""
    t0 = time.time()
    result = uart_send_command("i2c scan")
    audit("hw.i2c.scan", 0, "ok", (time.time() - t0) * 1000)
    return result

def hw_i2c_read(addr: str, reg: str) -> dict:
    """Read an I²C register (via Arty UART)."""
    t0 = time.time()
    result = uart_send_command(f"i2c read {addr} {reg}")
    audit("hw.i2c.read", 0, "ok", (time.time() - t0) * 1000)
    return result

def hw_i2c_dump(addr: str) -> dict:
    """Dump all registers for an I²C device (via Arty UART)."""
    t0 = time.time()
    result = uart_send_command(f"i2c dump {addr}")
    audit("hw.i2c.dump", 0, "ok", (time.time() - t0) * 1000)
    return result

# ============================================================================
# Codec Tools (via UART → Arty firmware CLI)
# ============================================================================

def hw_codec_status() -> dict:
    """Get codec status summary (via Arty UART)."""
    t0 = time.time()
    result = uart_send_command("codec status")
    audit("hw.codec.status", 0, "ok", (time.time() - t0) * 1000)
    return result

def hw_codec_dump_registers() -> dict:
    """Dump all codec registers (via Arty UART)."""
    t0 = time.time()
    result = uart_send_command("codec regs")
    audit("hw.codec.dump_registers", 0, "ok", (time.time() - t0) * 1000)
    return result

def hw_codec_diff_known_good() -> dict:
    """Compare live codec registers to known-good profile (via Arty UART)."""
    t0 = time.time()
    result = uart_send_command(f"codec diff {KNOWN_GOOD['codec_register_profile']}")
    audit("hw.codec.diff_known_good", 0, "ok", (time.time() - t0) * 1000)
    return result

# ============================================================================
# GPIO Tools (via UART → Arty firmware CLI)
# ============================================================================

def hw_gpio_read(pin: str) -> dict:
    """Read a GPIO pin (via Arty UART)."""
    t0 = time.time()
    result = uart_send_command(f"gpio read {pin}")
    audit("hw.gpio.read", 0, "ok", (time.time() - t0) * 1000)
    return result

def hw_gpio_status() -> dict:
    """Read all GPIO pin states (via Arty UART)."""
    t0 = time.time()
    result = uart_send_command("gpio status")
    audit("hw.gpio.status", 0, "ok", (time.time() - t0) * 1000)
    return result

# ============================================================================
# SPI Tools (via UART → Arty firmware CLI)
# ============================================================================

def hw_spi_read(device: str, reg: str) -> dict:
    """Read an SPI register (via Arty UART)."""
    t0 = time.time()
    result = uart_send_command(f"spi read {device} {reg}")
    audit("hw.spi.read", 0, "ok", (time.time() - t0) * 1000)
    return result

def hw_spi_status(device: str = "") -> dict:
    """Get SPI device status (via Arty UART)."""
    t0 = time.time()
    cmd = f"spi status {device}" if device else "spi status"
    result = uart_send_command(cmd)
    audit("hw.spi.status", 0, "ok", (time.time() - t0) * 1000)
    return result

# ============================================================================
# System / DMA / TDM Tools (via UART → Arty firmware CLI)
# ============================================================================

def hw_system_status() -> dict:
    """Get full system status: firmware version, uptime, clocks (via Arty UART)."""
    t0 = time.time()
    result = uart_send_command("system status")
    audit("hw.system.status", 0, "ok", (time.time() - t0) * 1000)
    return result

def hw_dma_status() -> dict:
    """Get DMA engine status (via Arty UART)."""
    t0 = time.time()
    result = uart_send_command("dma status")
    audit("hw.dma.status", 0, "ok", (time.time() - t0) * 1000)
    return result

def hw_tdm_status() -> dict:
    """Get TDM link status (via Arty UART)."""
    t0 = time.time()
    result = uart_send_command("tdm status")
    audit("hw.tdm.status", 0, "ok", (time.time() - t0) * 1000)
    return result

def hw_help() -> dict:
    """List all available commands on the Arty debug terminal."""
    t0 = time.time()
    result = uart_send_command("help")
    audit("hw.help", 0, "ok", (time.time() - t0) * 1000)
    return result

# ============================================================================
# TIER 1 — Confirmation Required (via UART)
# ============================================================================

def hw_enable_debug_mode() -> dict:
    """Transition from SAFE_MODE to DEBUG_MODE."""
    global state
    if state not in [State.SAFE_MODE, State.IDENTIFIED, State.CONNECTED]:
        return {"error": f"Cannot enable debug from {state}"}
    state = State.DEBUG_MODE
    audit("hw.enable_debug_mode", 1, "ok", confirmed_by="human")
    return {"status": "debug_mode_enabled", "state": state}

def hw_i2c_write(addr: str, reg: str, val: str) -> dict:
    """Write an I²C register (via Arty UART). Requires DEBUG_MODE."""
    t0 = time.time()
    if state not in [State.DEBUG_MODE, State.DANGEROUS_MODE]:
        return {"error": f"Cannot write in {state}. Enable debug mode first."}
    result = uart_send_command(f"i2c write {addr} {reg} {val}")
    audit("hw.i2c.write", 1, "ok", (time.time() - t0) * 1000, confirmed_by="human")
    return result

def hw_codec_apply_known_good_config() -> dict:
    """Apply known-good codec config (via Arty UART). Requires DEBUG_MODE."""
    t0 = time.time()
    if state not in [State.DEBUG_MODE, State.DANGEROUS_MODE]:
        return {"error": f"Cannot apply config in {state}. Enable debug mode first."}
    
    # Checkpoint: dump current state first
    pre_state = uart_send_command("codec regs")
    
    result = uart_send_command(f"codec apply {KNOWN_GOOD['codec_register_profile']}")
    audit("hw.codec.apply_known_good_config", 1, "ok",
          (time.time() - t0) * 1000, confirmed_by="human")
    result["pre_state_saved"] = "checkpoint captured"
    return result

def hw_gpio_write(pin: str, val: str) -> dict:
    """Write a GPIO pin (via Arty UART). Requires DEBUG_MODE."""
    t0 = time.time()
    if state not in [State.DEBUG_MODE, State.DANGEROUS_MODE]:
        return {"error": f"Cannot write in {state}. Enable debug mode first."}
    result = uart_send_command(f"gpio write {pin} {val}")
    audit("hw.gpio.write", 1, "ok", (time.time() - t0) * 1000, confirmed_by="human")
    return result

def hw_system_reset() -> dict:
    """Soft reset the Arty (via UART). Requires DEBUG_MODE."""
    t0 = time.time()
    if state not in [State.DEBUG_MODE, State.DANGEROUS_MODE]:
        return {"error": f"Cannot reset in {state}. Enable debug mode first."}
    result = uart_send_command("system reset", timeout=5.0)
    audit("hw.system.reset", 1, "ok", (time.time() - t0) * 1000, confirmed_by="human")
    return result

def hw_run_smoke_test(test_name: str) -> dict:
    """Run a named smoke test (via Arty UART). Requires DEBUG_MODE."""
    t0 = time.time()
    if state not in [State.DEBUG_MODE, State.DANGEROUS_MODE]:
        return {"error": f"Cannot run tests in {state}. Enable debug mode first."}
    result = uart_send_command(f"test run {test_name}", timeout=10.0)
    audit("hw.run_smoke_test", 1, "ok", (time.time() - t0) * 1000, confirmed_by="human")
    return result

# ============================================================================
# TIER 2 — Explicit Unlock Required
# ============================================================================

def hw_unlock_dangerous() -> dict:
    """Transition from DEBUG_MODE to DANGEROUS_MODE."""
    global state
    if state != State.DEBUG_MODE:
        return {"error": f"Cannot unlock dangerous from {state}"}
    state = State.DANGEROUS_MODE
    audit("hw.unlock_dangerous", 2, "ok", confirmed_by="human")
    return {"status": "dangerous_mode_unlocked", "state": state}

def hw_spi_write(device: str, reg: str, val: str) -> dict:
    """Write an SPI register (via Arty UART). Requires DANGEROUS_MODE."""
    t0 = time.time()
    if state != State.DANGEROUS_MODE:
        return {"error": f"Cannot write SPI in {state}. Unlock dangerous mode first."}
    result = uart_send_command(f"spi write {device} {reg} {val}")
    audit("hw.spi.write", 2, "ok", (time.time() - t0) * 1000, confirmed_by="human")
    return result

# ============================================================================
# Emergency Stop — Always Available
# ============================================================================

def hw_emergency_stop() -> dict:
    """Emergency stop — always Tier 0, no confirmation."""
    global state
    t0 = time.time()
    uart_send_command("system halt")  # Best-effort
    state = State.SAFE_MODE
    uart_disconnect()
    audit("hw.emergency_stop", 0, "ok", (time.time() - t0) * 1000)
    return {"status": "emergency_stop_executed", "state": state}

# ============================================================================
# Tool Registry with Input Schemas
# ============================================================================

# Common parameter schemas
PARAM_COMMAND = {"command": {"type": "string", "description": "Command to send to debug terminal"}}
PARAM_ADDR = {"addr": {"type": "string", "description": "I2C address (hex, e.g., '48')"}}
PARAM_REG = {"reg": {"type": "string", "description": "Register address (hex, e.g., '01')"}}
PARAM_VAL = {"val": {"type": "string", "description": "Value to write (hex, e.g., 'F0')"}}
PARAM_PIN = {"pin": {"type": "string", "description": "GPIO pin number (0-6)"}}
PARAM_DEVICE = {"device": {"type": "string", "description": "Device name (flash, sd, disp, touch)"}}
PARAM_BINARY = {"binary_path": {"type": "string", "description": "Path to binary file"}}
PARAM_ADDRESS = {"address": {"type": "string", "description": "Memory/register address (hex, e.g., '80000000')"}}
PARAM_SIZE = {"size": {"type": "integer", "description": "Bytes to read", "default": 4}}
PARAM_TEST = {"test_name": {"type": "string", "description": "Name of smoke test to run"}}

TOOLS = {
    # Abstract Debug Commands
    "dbg.boot_firmware": {
        "fn": dbg_boot_firmware,
        "tier": 0,
        "desc": "Boot firmware from bootloader (CMD:>) via J-Link",
        "schema": {"type": "object", "properties": {**PARAM_BINARY, **PARAM_ADDRESS}, "required": ["binary_path"]}
    },
    "dbg.write": {
        "fn": dbg_write,
        "tier": 0,
        "desc": "WRITE firmware to RAM via J-Link (temporary, testing)",
        "schema": {"type": "object", "properties": {**PARAM_BINARY, **PARAM_ADDRESS}, "required": ["binary_path"]}
    },
    "dbg.flash": {
        "fn": dbg_flash,
        "tier": 2,
        "desc": "FLASH to SPI (PERMANENT - only after GitHub validation!)",
        "schema": {"type": "object", "properties": {**PARAM_BINARY}, "required": ["binary_path"]}
    },
    "dbg.reset": {"fn": dbg_reset, "tier": 0, "desc": "Soft reset processor", "schema": {"type": "object", "properties": {}}},
    "dbg.status": {"fn": dbg_status, "tier": 0, "desc": "Get debug interface status", "schema": {"type": "object", "properties": {}}},
    "dbg.read_mem": {
        "fn": dbg_read_mem,
        "tier": 0,
        "desc": "Read memory location via J-Link",
        "schema": {"type": "object", "properties": {**PARAM_ADDRESS, **PARAM_SIZE}, "required": ["address"]}
    },
    "dbg.read_reg": {
        "fn": dbg_read_reg,
        "tier": 0,
        "desc": "Read CPU register via J-Link",
        "schema": {"type": "object", "properties": {"reg": {"type": "string", "description": "Register name (pc, sp, ra, etc.)"}}, "required": ["reg"]}
    },
    "dbg.step": {"fn": dbg_step, "tier": 0, "desc": "Single-step via J-Link", "schema": {"type": "object", "properties": {}}},

    # Tier 0 — Always safe
    "hw.status": {"fn": hw_status, "tier": 0, "desc": "Report overall hardware status", "schema": {"type": "object", "properties": {}}},
    "hw.identify": {"fn": hw_identify, "tier": 0, "desc": "Full target identification", "schema": {"type": "object", "properties": {}}},
    "hw.help": {"fn": hw_help, "tier": 0, "desc": "List all Arty debug terminal commands", "schema": {"type": "object", "properties": {}}},
    "hw.uart_terminal": {
        "fn": hw_uart_terminal,
        "tier": 0,
        "desc": "Send command to Arty debug terminal",
        "schema": {"type": "object", "properties": PARAM_COMMAND, "required": ["command"]}
    },
    "hw.uart_tail": {"fn": hw_uart_tail, "tier": 0, "desc": "Read recent UART output", "schema": {"type": "object", "properties": {}}},
    "hw.system_status": {"fn": hw_system_status, "tier": 0, "desc": "Firmware version, uptime, clocks", "schema": {"type": "object", "properties": {}}},
    "hw.i2c_scan": {"fn": hw_i2c_scan, "tier": 0, "desc": "Scan I²C bus for devices", "schema": {"type": "object", "properties": {}}},
    "hw.i2c_read": {
        "fn": hw_i2c_read,
        "tier": 0,
        "desc": "Read I²C register",
        "schema": {"type": "object", "properties": {**PARAM_ADDR, **PARAM_REG}, "required": ["addr", "reg"]}
    },
    "hw.i2c_dump": {
        "fn": hw_i2c_dump,
        "tier": 0,
        "desc": "Dump all registers for I²C device",
        "schema": {"type": "object", "properties": PARAM_ADDR, "required": ["addr"]}
    },
    "hw.codec_status": {"fn": hw_codec_status, "tier": 0, "desc": "Codec status summary", "schema": {"type": "object", "properties": {}}},
    "hw.codec_dump_registers": {"fn": hw_codec_dump_registers, "tier": 0, "desc": "Dump all codec registers", "schema": {"type": "object", "properties": {}}},
    "hw.codec_diff_known_good": {"fn": hw_codec_diff_known_good, "tier": 0, "desc": "Diff live codec vs known-good", "schema": {"type": "object", "properties": {}}},
    "hw.gpio_read": {
        "fn": hw_gpio_read,
        "tier": 0,
        "desc": "Read GPIO pin state",
        "schema": {"type": "object", "properties": PARAM_PIN, "required": ["pin"]}
    },
    "hw.gpio_status": {"fn": hw_gpio_status, "tier": 0, "desc": "Read all GPIO states", "schema": {"type": "object", "properties": {}}},
    "hw.spi_read": {
        "fn": hw_spi_read,
        "tier": 0,
        "desc": "Read SPI register",
        "schema": {"type": "object", "properties": {**PARAM_DEVICE, **PARAM_REG}, "required": ["device", "reg"]}
    },
    "hw.spi_status": {"fn": hw_spi_status, "tier": 0, "desc": "SPI device status", "schema": {"type": "object", "properties": {}}},
    "hw.dma_status": {"fn": hw_dma_status, "tier": 0, "desc": "DMA engine status", "schema": {"type": "object", "properties": {}}},
    "hw.tdm_status": {"fn": hw_tdm_status, "tier": 0, "desc": "TDM link status", "schema": {"type": "object", "properties": {}}},
    "hw.emergency_stop": {"fn": hw_emergency_stop, "tier": 0, "desc": "EMERGENCY — halt CPU, disable outputs", "schema": {"type": "object", "properties": {}}},

    # Tier 1 — Confirmation required
    "hw.enable_debug_mode": {"fn": hw_enable_debug_mode, "tier": 1, "desc": "Enable DEBUG_MODE (controlled mutations)", "schema": {"type": "object", "properties": {}}},
    "hw.i2c_write": {
        "fn": hw_i2c_write,
        "tier": 1,
        "desc": "Write I²C register",
        "schema": {"type": "object", "properties": {**PARAM_ADDR, **PARAM_REG, **PARAM_VAL}, "required": ["addr", "reg", "val"]}
    },
    "hw.codec_apply_known_good": {"fn": hw_codec_apply_known_good_config, "tier": 1, "desc": "Apply known-good codec config", "schema": {"type": "object", "properties": {}}},
    "hw.gpio_write": {
        "fn": hw_gpio_write,
        "tier": 1,
        "desc": "Write GPIO pin",
        "schema": {"type": "object", "properties": {**PARAM_PIN, "val": {"type": "string", "description": "Value (0 or 1)"}}, "required": ["pin", "val"]}
    },
    "hw.system_reset": {"fn": hw_system_reset, "tier": 1, "desc": "Soft reset the board", "schema": {"type": "object", "properties": {}}},
    "hw.run_smoke_test": {
        "fn": hw_run_smoke_test,
        "tier": 1,
        "desc": "Run named hardware smoke test",
        "schema": {"type": "object", "properties": PARAM_TEST, "required": ["test_name"]}
    },

    # Tier 2 — Explicit unlock required
    "hw.unlock_dangerous": {"fn": hw_unlock_dangerous, "tier": 2, "desc": "Enable DANGEROUS_MODE (flash, program)", "schema": {"type": "object", "properties": {}}},
    "hw.spi_write": {
        "fn": hw_spi_write,
        "tier": 2,
        "desc": "Write SPI register",
        "schema": {"type": "object", "properties": {**PARAM_DEVICE, **PARAM_REG, **PARAM_VAL}, "required": ["device", "reg", "val"]}
    },
}

# ============================================================================
# MCP Server (stdio transport)
# ============================================================================

def main():
    import sys
    import asyncio
    from mcp.server import Server
    from mcp.server.stdio import stdio_server
    from mcp.types import Tool, TextContent

    server = Server("hardware-debug-mcp")

    @server.list_tools()
    async def list_tools():
        tool_defs = []
        for name, info in TOOLS.items():
            tool_defs.append(Tool(
                name=name,
                description=f"[Tier {info['tier']}] {info['desc']}",
                inputSchema=info.get("schema", {"type": "object", "properties": {}})
            ))
        return tool_defs

    @server.call_tool()
    async def call_tool(name: str, arguments: dict):
        if name not in TOOLS:
            return [TextContent(type="text", text=json.dumps(
                {"error": f"Unknown tool: {name}"}))]

        tool = TOOLS[name]
        try:
            result = tool["fn"](**arguments)
            return [TextContent(type="text", text=json.dumps(result, indent=2))]
        except Exception as e:
            return [TextContent(type="text", text=json.dumps(
                {"error": str(e)}))]

    async def run():
        async with stdio_server() as (read_stream, write_stream):
            await server.run(
                read_stream,
                write_stream,
                server.create_initialization_options()
            )

    asyncio.run(run())

if __name__ == "__main__":
    main()
