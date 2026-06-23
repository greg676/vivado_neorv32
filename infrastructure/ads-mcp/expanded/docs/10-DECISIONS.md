# ADS+MCP — Section 10: DECISIONS LOCKED

**Document ID:** ADS-10-DECISIONS  
**Version:** 1.0  
**Date:** 2026-06-22  
**Author:** GodBot 🜂

---

## 10.1 All Decisions

| # | Decision | Answer | Rationale |
|---|----------|--------|-----------|
| 1 | OWUI instances? | **One — R7 cockpit.** R5 OWUI optional, unrelated to ADS+MCP. | R7 OWUI pools both Ollama backends. No need for a second OWUI. |
| 2 | Orchestrator location? | **R7 OWUI** — the model you chat with; all 4 MCP tools + write + hardware access | Single cockpit. One place to sit. |
| 3 | Critic / Archivist location? | **R7 OWUI role models** with swappable bases (cloud or -r5) | Same cockpit, different tabs. Manual review loop for Phase 1-5. |
| 4 | Model selection? | **Fully flexible** — roles fixed, bases swapped from dropdown anytime | Lock the roles, never lock the models. |
| 5 | GPU visibility? | **Naming convention:** -r7 / -r5 / :cloud; unique names = deterministic routing | Solves routing ambiguity and makes the dropdown a GPU map. |
| 6 | R5 8GB role? | **≤8B exploration lab + embeddings.** Never a 27B. | Physical limit. 8GB can't hold 27B. |
| 7 | Cross-machine review? | **Manual (human in loop)** for Phase 1–5; automate later if needed | Reliable, zero plumbing. Build automation only if manual is too slow. |
| 8 | MCP bridge? | **mcpo**, systemd service on R7, port 8200 | Proven, works with OWUI's Tool Server feature. |
| 9 | Hardware MCP language? | **Python 3.12** (pylink-square, pyserial, smbus2) | pylink is Python-only. pyserial is Python-native. One language, simple stack. |
| 10 | Debug channel? | **RTT primary, UART secondary** | RTT is non-intrusive, 100x faster, no UART pins needed. |
| 11 | GitHub formality? | **Full** — issues, PRs, CI, public-facing quality | This is going to be seen. Professional from day one. |
| 12 | KB sync? | **Single collection** on /mnt/data-1tb/.../knowledge/, no cross-OWUI sync needed | One OWUI = one KB. No sync problem. |
| 13 | Data location? | **All on /mnt/data-1tb** | 800GB free. OS drive has 107GB — don't fill it. |
| 14 | Project coupling? | **None.** Any project plugs in via project.profile.json. | ADS+MCP is infrastructure, not a product. |
| 15 | Safety model? | **Unified 4-tier system** across all servers | Tier 0 (read) → Tier 1 (local write) → Tier 2 (controlled mutation) → Tier 3 (dangerous) |
| 16 | Audit? | **Append-only JSONL**, one line per tool call | Queryable, immutable, rotated monthly. |
| 17 | Emergency stop? | **Always Tier 0**, available in any state | Safety must never require confirmation. |

---

## 10.2 Decisions NOT Made (Deferred)

| Decision | Deferred To | Reason |
|----------|------------|--------|
| Automated orchestrator→critic API calls | Phase 6 | Manual loop works. Automate only if needed. |
| Custom PCB for debug probe switching | Post-Phase 5 | Current JLink setup works. |
| OWUI native MCP support (vs mcpo) | When OWUI ships it | mcpo works now. Switch when native is stable. |
| Multi-project simultaneous support | Post-Phase 6 | Single project for now. Profile swap is fast enough. |

---

*End of Section 10 — DECISIONS LOCKED*
