# ADS+MCP — Section 03: MODEL LAYER

**Document ID:** ADS-03-MODEL-LAYER  
**Version:** 1.0  
**Date:** 2026-06-22  
**Author:** GodBot 🜂

---

## 3.1 Single Cockpit Architecture

One OWUI instance on R7 is the cockpit. It pools both Ollama backends and all cloud models. R5 OWUI is not needed for ADS+MCP — R7 OWUI already sees R5's models through the remote Ollama connection.

---

## 3.2 The Naming Convention — GPU Visibility Through Names

R7 OWUI pools two Ollama backends. If the same model name exists on both, OWUI routes unpredictably and you can't tell which GPU you hit. The fix: **never duplicate names. Suffix everything.**

| Suffix | GPU / Location | VRAM | Use |
|--------|---------------|------|-----|
| `*-r7` | R7 RX 7900 XT | 20GB | Big local models (27B), heavy reasoning |
| `*-r5` | R5 RX 6600 | 8GB | Small-model exploration (≤8B), embeddings |
| `*:cloud` / provider | Cloud (OpenRouter) | — | Strongest reasoning, no GPU cost |

This single convention solves two problems at once:
1. **Deterministic routing** — unique names mean each model maps to exactly one backend
2. **GPU visibility** — the dropdown reads like a map; you always know where inference runs

### Tagging R5 Models

```bash
ssh r5 'ollama cp <model> <model>-r5 && ollama rm <model>'
```

### Tagging R7 Models (Optional)

```bash
ollama cp <model> <model>-r7 && ollama rm <model>
```

---

## 3.3 Role Models

A **role model** is a wrapper. Its base LLM is a dropdown you change anytime. You explore freely.

### ai-design-orchestrator
| Property | Value |
|----------|-------|
| **Role** | Hardware debug agent — the one you chat with |
| **Tools** | ALL 4 MCP servers, write + hardware access |
| **Base LLM** | deepseek-v4-pro:cloud (default), or qwen3.6:27b-r7 |
| **Location** | R7 OWUI |
| **System Prompt** | `workspace/ai-design-orchestrator-prompt.txt` |

### ai-design-critic
| Property | Value |
|----------|-------|
| **Role** | Devil's advocate — finds flaws in proposals |
| **Tools** | filesystem (ro), github (ro), browser (ro) |
| **Base LLM** | Any :cloud, or explore *-r5 |
| **Location** | R7 OWUI |
| **System Prompt** | `workspace/ai-design-critic-prompt.txt` |

### ai-design-archivist
| Property | Value |
|----------|-------|
| **Role** | Documentarian — writes reports, updates KB |
| **Tools** | filesystem (ro), github (ro) |
| **Base LLM** | Any *-r5 model |
| **Location** | R7 OWUI |
| **System Prompt** | `workspace/ai-design-archivist-prompt.txt` |

### ai-design-researcher (Optional)
| Property | Value |
|----------|-------|
| **Role** | Read-only scout |
| **Tools** | filesystem (ro), github (ro), browser (ro) |
| **Base LLM** | Anything |
| **Location** | R7 OWUI |
| **System Prompt** | `workspace/ai-design-researcher-prompt.txt` |

---

## 3.4 Roles vs. Bases — Zero Lock-In

| Role (fixed) | Base LLM (swap freely) | Notes |
|-------------|----------------------|-------|
| orchestrator | deepseek-v4-pro:cloud or qwen3.6:27b-r7 | Needs strongest reasoning for debug chains |
| critic | any :cloud, or explore *-r5 | Occasional use — cheap to run cloud, or test small local |
| archivist | any *-r5 model | Light task — perfect for the 8GB exploration lab |
| researcher | anything | Read-only standalone use |

---

## 3.5 The Exploration Workflow

```bash
# 1. Pull a new model on R5
ssh r5 'ollama pull new-7b && ollama cp new-7b new-7b-r5 && ollama rm new-7b'

# 2. R7 OWUI dropdown auto-refreshes → "new-7b-r5" appears

# 3. Pick it as a base for any role, or chat with it directly

# 4. Watch rocm-smi on R5 to confirm it's running on the 8GB

# 5. Don't like it? Pick a different -r5 entry. No config, no restart, no lock-in.
```

---

## 3.6 The 8GB Reality

R5's RX 6600 holds 8GB. This is a hard physical limit, not a preference.

| Model class | Fits in 8GB? |
|------------|-------------|
| 27B (any quant) | ❌ Never — runs on R7 only |
| 14B @ Q4 | ❌ No room for context |
| 8B @ Q4 | ✅ Yes, decent context |
| 7B @ Q4 | ✅ Comfortable |
| embeddings (bge/nomic) | ✅ Yes |

R5 is your **≤8B exploration lab and embeddings server**. It offloads small models and RAG vectorization from R7 — exactly what 8GB is good for. Never attempt a 27B on R5.

---

## 3.7 Cross-Machine Review — Manual First

For Phase 1–5, the **human is the review loop**. The orchestrator proposes; you review; if you want a second opinion, you open the critic in another tab and paste the proposal. Reliable, zero plumbing.

Automated orchestrator→critic API calls are deferred to Phase 6+ polish. Build it only if the manual flow proves too slow.

---

## 3.8 Creating Role Models in OWUI

### Step-by-step for ai-design-orchestrator:

1. OWUI → Workspace → Models → Create Model
2. **Model ID:** `ai-design-orchestrator`
3. **Base Model:** Select from dropdown (e.g., `deepseek-v4-pro:cloud`)
4. **System Prompt:** Paste contents of `workspace/ai-design-orchestrator-prompt.txt`
5. **Tools:** Enable the mcpo Tool Server (all four MCP servers)
6. **Knowledge:** Attach project knowledge collection
7. **Save**

Repeat for critic, archivist, researcher with their respective prompts and tool sets.

---

*End of Section 03 — MODEL LAYER*
