# CodecBot Model Catalog — June 12, 2026

## 10 OpenRouter Models (Cloud, pay-per-token)

| # | Alias | Model ID | Intel | Code | Agent | In $/M | Out $/M | Ctx |
|---|-------|----------|-------|------|--------|--------|---------|-----|
| 1 | `gpt-5.4` | openai/gpt-5.4 | 56.8 | 57.2 | 68.0 | $2.50 | $15.00 | 1.05M |
| 2 | `gemini-pro` | google/gemini-3.1-pro-preview | 57.2 | 55.5 | 59.1 | $2.00 | $12.00 | 1.05M |
| 3 | `qwen-max` | qwen/qwen3.7-max | 56.6 | 50.1 | 66.6 | $1.25 | $3.75 | 1M |
| 4 | `gemini-flash` | google/gemini-3.5-flash | 55.3 | 45.0 | 70.3 | $1.50 | $9.00 | 1.05M |
| 5 | `m3` | minimax/minimax-m3 | 54.7 | 43.4 | 68.6 | $0.30 | $1.20 | 524K |
| 6 | `kimi-or` | moonshotai/kimi-k2.6 | 53.9 | 47.1 | 66.0 | $0.68 | $3.41 | 262K |
| 7 | `qwen-plus` | qwen/qwen3.7-plus | 53.3 | 46.5 | 65.1 | $0.32 | $1.28 | 1M |
| 8 | `grok` | xai/grok-4.3 | 53.2 | 41.0 | 65.9 | $1.25 | $2.50 | 1M |
| 9 | `ds-or` | deepseek/deepseek-v4-pro | 51.5 | 47.5 | 67.2 | $0.43 | $0.87 | 1.05M |
| 10 | `glm-or` | z-ai/glm-5.1 | 51.4 | 43.4 | 67.1 | $0.98 | $3.08 | 203K |

## 10 Ollama Models (6 Local GPU + 4 Cloud Proxy)

### Local GPU (RX 7900 XT 20GB)
| # | Alias | Model ID | Size | Ctx | Notes |
|---|-------|----------|------|-----|-------|
| 1 | `qwen36` | qwen3.6:27b | 16.2GB | 131K | Best local dense generalist |
| 2 | `qwen36-iq3` | batiai/qwen3.6-27b:iq3 | 10.4GB | 131K | IQ3 quant, faster, more VRAM for ctx |
| 3 | `qwen3` | qwen3:14b | 8.6GB | 41K | Mid-size workhorse |
| 4 | `gemma3` | gemma3:12b | 7.6GB | 131K | Multimodal vision, 128K ctx |
| 5 | `gemma4` | gemma4:e4b | 8.9GB | 131K | Native function calling, Apache 2.0 |
| 6 | `rnj` | rnj-1:latest | 4.8GB | 33K | Gemma3 fine-tune, small/fast |

### Cloud Proxy (via Ollama cloud)
| # | Alias | Model ID | Ctx | Notes |
|---|-------|----------|-----|-------|
| 7 | `kimi` | kimi-k2.6:cloud | 131K | 1T MoE, strong coder |
| 8 | `minimax` | minimax-m2.7:cloud | 98K | Solid agentic, cheap |
| 9 | `qwen` | qwen3.5:397b-cloud | 131K | Massive MoE, multimodal |
| 10 | (none) | nemotron-3-super:cloud | 131K | NVIDIA 120B MoE, 1M ctx |

## Critic Pair
- **Primary:** MiniMax M3 (`m3` via OR, or `minimax` via Ollama cloud)
- **Secondary:** DeepSeek V4 Pro (`ds-or` via OR, or `deepseek` via Ollama cloud)

## Primary Model & Fallback Chain
- **Primary:** `ollama/deepseek-v4-pro:cloud` (alias: `deepseek`)
- **Fallbacks:** 22-deep chain: Ollama cloud → OR value → OR premium → local GPU → small locals

## API Key Status
- **OpenRouter:** Placeholder `OPENROUTER_API_KEY` — Claw needs to provide real key
- **Ollama:** Already working (local + cloud proxy)
