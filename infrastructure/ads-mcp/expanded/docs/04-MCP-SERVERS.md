# ADS+MCP — Section 04: THE FOUR MCP SERVERS

**Document ID:** ADS-04-MCP-SERVERS  
**Version:** 1.0  
**Date:** 2026-06-22  
**Author:** GodBot 🜂

---

## 4.1 Server Overview

| Server | Purpose | Stack | Risk |
|--------|---------|-------|------|
| r7-filesystem-mcp | Controlled file access | Python 3.12 + MCP SDK | Low |
| github-project-mcp | Repo / issues / PRs / CI | Official GitHub MCP | Low (read), Medium (write) |
| browser-puppeteer-mcp | Headless browser | Node.js + Puppeteer | Low |
| hardware-debug-mcp | JLink / UART / I²C / codec | Python 3.12 + pylink + pyserial | **High — custom build** |

---

## 4.2 r7-filesystem-mcp

### Purpose
The model's eyes and hands on R7. Scoped, audited, never exposes secrets.

### Tools

| Tool | Tier | Description |
|------|------|-------------|
| `fs.list(path)` | 0 | Directory listing |
| `fs.read(path, offset?, limit?)` | 0 | Read file content |
| `fs.stat(path)` | 0 | File metadata, hash |
| `fs.tree(path, depth)` | 0 | Directory tree |
| `fs.search(query, glob?, roots?)` | 0 | Full-text search |
| `fs.hash(path)` | 0 | SHA-256 of file |
| `fs.diff(path_a, path_b)` | 0 | Diff two files |
| `fs.write(path, content)` | 1 | Write with confirmation |
| `fs.patch(path, unified_diff)` | 1 | Patch with confirmation |
| `fs.mkdir(path)` | 1 | Create directory |
| `fs.trash(path)` | 2 | Move to trash (never raw delete) |

### Safety Rules
- Read/write only inside profile roots
- No `/etc`, no `~/.ssh`, no browser data
- Default read-only
- Every write logs: timestamp, session, path, old/new SHA-256, diff
- Destructive ops go to trash, never raw delete

### Implementation
Uses `@modelcontextprotocol/server-filesystem` reference server, wrapped with profile-based root enforcement.

```bash
# Wrapper script: run-filesystem-mcp.sh
npx @modelcontextprotocol/server-filesystem \
  --roots-from-profile /mnt/data-1tb/ai-design-studio/project.profile.json
```

---

## 4.3 github-project-mcp

### Purpose
Correlates code state with hardware findings: issues, branches, PRs, CI, diffs.

### Tools

| Tool | Tier | Description |
|------|------|-------------|
| `github.issue.list(repo, labels?, state?)` | 0 | List issues |
| `github.issue.get(repo, number)` | 0 | Get issue detail |
| `github.pr.list(repo)` | 0 | List PRs |
| `github.pr.diff(repo, number)` | 0 | PR diff |
| `github.branch.status(repo, ref)` | 0 | Branch CI state |
| `github.commit.list(repo, ref, n)` | 0 | Recent commits |
| `github.ci.status(repo, ref)` | 0 | CI run results |
| `github.issue.comment(...)` | 3 | Post comment |
| `github.pr.create(...)` | 3 | Open PR |
| `github.commit.create(...)` | 3 | Push commit |

### Safety Rules
- Token scoped to approved repos only (from profile)
- Read is always safe (Tier 0)
- Any public-facing action (comment, PR, push) requires Tier 3 explicit unlock
- Auth: `gh auth token` or `GITHUB_TOKEN` env var — never stored in service files

### Implementation
Uses official GitHub MCP server.

```bash
# Wrapper script: run-github-mcp.sh
export GITHUB_TOKEN=$(gh auth token)
npx @modelcontextprotocol/server-github \
  --repos-from-profile /mnt/data-1tb/ai-design-studio/project.profile.json
```

---

## 4.4 browser-puppeteer-mcp

### Purpose
Headless browser for OWUI itself, Jupyter, dashboards, vendor docs, GitHub UI.

### Tools

| Tool | Tier | Description |
|------|------|-------------|
| `browser.goto(url)` | 0* | Navigate (allowlisted URLs only) |
| `browser.screenshot()` | 0 | Capture current view |
| `browser.text()` | 0 | Extract visible text |
| `browser.title()` | 0 | Page title |
| `browser.extract_table(selector?)` | 0 | Parse table data |
| `browser.wait_for(selector, timeout)` | 0 | Wait for element |
| `browser.click(selector)` | 1 | Click element |
| `browser.type(selector, text)` | 1 | Type into field |
| `browser.download(url, dest)` | 1 | Download file |
| `browser.evaluate(js)` | 2 | Execute JavaScript |
| `browser.network_log()` | 0 | Inspect network activity |

*URL must pass allowlist check or returns permission error.

### Safety Rules
- URL allowlist enforced server-side before navigation
- `browser.evaluate()` is Tier 2 with JS content logged in full
- No stored credentials in browser profile
- Screenshots auto-saved to session artifact dir
- Session browser profile is ephemeral (tmpdir), wiped per OWUI conversation

### Implementation
Uses Puppeteer MCP server.

```bash
# Wrapper script: run-browser-mcp.sh
npx @anthropic/mcp-server-puppeteer \
  --allowlist-from-profile /mnt/data-1tb/ai-design-studio/project.profile.json \
  --screenshot-dir /mnt/data-1tb/ai-design-studio/browser-captures/
```

---

## 4.5 hardware-debug-mcp

### Purpose
**This is the custom server we build.** Wraps real hardware tools behind safe named operations. The model never sees raw shell.

### Stack
- Python 3.12
- MCP SDK (stdio transport)
- pylink-square (SEGGER JLink Python library)
- pyserial (UART)
- smbus2 (I²C if direct codec access needed)

### Full specification
See **Section 05 — HARDWARE DEBUG MCP** for complete tool tiers, state machine, confirmation flow, and safety architecture.

---

## 4.6 mcpo Bridge Configuration

All four servers are registered in mcpo:

```json
{
  "mcpServers": {
    "r7-filesystem": {
      "command": "/mnt/data-1tb/ai-design-studio/mcp-servers/run-filesystem-mcp.sh"
    },
    "github-project": {
      "command": "/mnt/data-1tb/ai-design-studio/mcp-servers/run-github-mcp.sh"
    },
    "browser-puppeteer": {
      "command": "/mnt/data-1tb/ai-design-studio/mcp-servers/run-browser-mcp.sh"
    },
    "hardware-debug": {
      "command": "/mnt/data-1tb/ai-design-studio/mcp-servers/run-hardware-mcp.sh"
    }
  }
}
```

OWUI Tool Server URL: `http://host.docker.internal:8200`

---

*End of Section 04 — MCP SERVERS*
