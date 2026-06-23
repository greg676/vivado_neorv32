# ADS+MCP — Section 02: PROJECT PROFILE (The Keystone)

**Document ID:** ADS-02-PROJECT-PROFILE  
**Version:** 1.0  
**Date:** 2026-06-22  
**Author:** GodBot 🜂

---

## 2.1 Purpose

All four MCP servers load a shared `project.profile.json` at startup. This is what makes four servers a **system** instead of four disconnected tools. It binds them to the same project identity, hardware identity, filesystem roots, repos, and known-good state.

**Location:** `/mnt/data-1tb/ai-design-studio/project.profile.json`

---

## 2.2 Complete Schema

```json
{
  "profile_version": "1",
  "project": {
    "name": "<active-project>",
    "version": "0.4.x",
    "session_dir": "/mnt/data-1tb/ai-design-studio/debug-sessions/",
    "workspace_dir": "/mnt/data-1tb/ai-design-studio/workspace/"
  },
  "filesystem": {
    "read_roots": [
      "~/projects/",
      "/mnt/data-1tb/ai-design-studio/",
      "~/.openclaw-godbot/workspace/",
      "~/.openclaw-codecbot/workspaces/codecbot/",
      "~/Downloads/"
    ],
    "write_roots": [
      "~/projects/<active-project>/",
      "/mnt/data-1tb/ai-design-studio/workspace/",
      "/mnt/data-1tb/ai-design-studio/debug-sessions/"
    ],
    "trash_dir": "/mnt/data-1tb/ai-design-studio/.trash"
  },
  "github": {
    "username": "<github-user>",
    "repos": [
      "<org>/<active-project>",
      "openclaw/openclaw"
    ],
    "default_branch": "main",
    "read_only_by_default": true
  },
  "hardware": {
    "board": "Arty-Z7-20",
    "board_serial": "<serial>",
    "probe": {
      "type": "SEGGER-JLink",
      "serial": "<probe-serial>",
      "interface": "JTAG",
      "target_device": "<target>"
    },
    "codec": {
      "chip": "<codec-chip>",
      "i2c_addr": "0x48",
      "config_profile": "tdm-8ch"
    },
    "uart": {
      "port": "/dev/ttyUSB0",
      "baud": 115200
    },
    "rtt_enabled": true
  },
  "known_good": {
    "firmware_hash": "<sha256>",
    "bitstream_hash": "<sha256>",
    "codec_register_profile": "profiles/tdm-8ch-known-good.json"
  },
  "browser": {
    "screenshot_dir": "/mnt/data-1tb/ai-design-studio/browser-captures/",
    "url_allowlist": [
      "http://127.0.0.1:*",
      "http://localhost:*",
      "http://10.0.0.*",
      "http://192.168.*",
      "*.ts.net",
      "github.com",
      "docs.amd.com",
      "docs.xilinx.com"
    ]
  },
  "audit_log": "/mnt/data-1tb/ai-design-studio/audit/audit.jsonl"
}
```

---

## 2.3 Field Reference

### project
| Field | Description |
|-------|-------------|
| name | Active project name — used in session dirs, logs, reports |
| version | Project version — informational |
| session_dir | Where debug session artifacts are stored |
| workspace_dir | Working directory for generated files |

### filesystem
| Field | Description |
|-------|-------------|
| read_roots | Directories the model can read from |
| write_roots | Directories the model can write to (gated) |
| trash_dir | Safe delete destination (never raw rm) |

### github
| Field | Description |
|-------|-------------|
| username | GitHub username for auth |
| repos | Approved repos for read/write |
| default_branch | Default branch for PRs |
| read_only_by_default | If true, writes require explicit confirmation |

### hardware
| Field | Description |
|-------|-------------|
| board | Board model string |
| board_serial | Unique board identifier for identity lock |
| probe | Debug probe details (type, serial, interface) |
| codec | Audio codec chip and I²C address |
| uart | Serial port and baud rate |
| rtt_enabled | Whether Segger RTT is available |

### known_good
| Field | Description |
|-------|-------------|
| firmware_hash | SHA-256 of known-good firmware |
| bitstream_hash | SHA-256 of known-good bitstream |
| codec_register_profile | Path to known-good register dump |

### browser
| Field | Description |
|-------|-------------|
| screenshot_dir | Where browser screenshots are saved |
| url_allowlist | URLs the browser is allowed to visit |

### audit_log
Path to append-only JSONL audit log.

---

## 2.4 How Servers Load It

Each MCP server reads the profile at startup:

```python
import json, os

PROFILE_PATH = os.environ.get(
    "ADS_PROFILE",
    "/mnt/data-1tb/ai-design-studio/project.profile.json"
)

with open(PROFILE_PATH) as f:
    profile = json.load(f)

# Each server extracts its section:
fs_roots = profile["filesystem"]
github_repos = profile["github"]["repos"]
hw_config = profile["hardware"]
browser_allowlist = profile["browser"]["url_allowlist"]
```

---

## 2.5 Project Swap Procedure

To switch projects:

1. Update `project.profile.json` with new project values
2. Restart mcpo: `systemctl --user restart mcpo`
3. All four MCP servers reload the new profile
4. New project is active

No code changes. No server rebuilds. One file.

---

*End of Section 02 — PROJECT PROFILE*
