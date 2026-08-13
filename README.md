# codex-mcp — a literature workflow for Codex CLI

Wire **Codex CLI** to your research library so a single natural-language prompt can
**search papers → download open-access PDFs → import into Zotero → (optionally) translate to Chinese**.

> This is **not** another Zotero MCP server. It's a thin **orchestration + safety layer**
> on top of two existing MCP servers, tuned for **Codex CLI** and for running inside
> **WSL2 / sandboxed** shells. The value here is the wiring, the readiness gating, the
> safety rails, and the WSL/Windows integration — not the servers themselves.

Built on:
- [openags/paper-search-mcp](https://github.com/openags/paper-search-mcp) — search/download across 20+ scholarly sources
- [54yyyu/zotero-mcp](https://github.com/54yyyu/zotero-mcp) — read/write your Zotero library
- [PDFMathTranslate / pdf2zh](https://github.com/PDFMathTranslate/PDFMathTranslate) + [guaguastandup/zotero-pdf2zh](https://github.com/guaguastandup/zotero-pdf2zh) — format-preserving EN→ZH PDF translation (optional)

## Architecture

```text
┌──────────────────────── Codex CLI (WSL2) ────────────────────────┐
│                                                                    │
│  paper-search-mcp   search 20+ sources → dedupe → OA PDF download  │
│  zotero-mcp         create collection · import items · attach PDF  │
│                     · tag (e.g. to-translate)                      │
└───────────────────────────────┬────────────────────────────────────┘
                                 │  Zotero Web API  (writes: import)
                                 ▼
                    Zotero Desktop (Windows)
                                 │
                                 │  right-click / batch on `to-translate`
                                 ▼
                    pdf2zh  →  EN→ZH translation
                    re-attach `*-mono.pdf` (Chinese) + `*-dual.pdf` (bilingual)
```

**Why the split** — Zotero's *local* API is read-only, so **imports (writes) go through the
Zotero Web API**. Translation happens entirely on the Windows side (pdf2zh), independent of
Codex. See [Zotero access modes](#zotero-access-modes) and
[Translation chain](pdf2zh-translation/SETUP.md).

> **Health check:** run `./doctor.sh` any time to verify the whole system in one shot —
> WSL networking, Zotero local API, pdf2zh server, and Web API write access.

## Prerequisites

- Codex CLI with MCP client enabled (`features.rmcp_client = true`)
- `uv` / `uvx`
- A Zotero account (Web API mode) **or** Zotero 7+ desktop with local API enabled (local mode)
- Python 3.10–3.12 for the MCP servers
- (Optional, for translation) Zotero desktop on Windows + the pdf2zh plugin

## Quickstart

```bash
# 1. Create the private env file and (if config is writable) register the MCP servers
./configure-codex-literature.sh

# 2. Fill in credentials WITHOUT pasting keys into chat/history
./set-zotero-web-api-env.sh        # Zotero Web API key + numeric user ID + Unpaywall email

# 3. Install the MCP servers locally (mirror fallback available)
./install-literature-mcp-tools.sh
#   CODEX_LITERATURE_UV_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple ./install-literature-mcp-tools.sh

# 4. Verify readiness
./check-literature-mcp-ready.sh
./verify-literature-mcp.sh

# 5. Launch Codex with the MCP servers injected (works even if ~/.codex/config.toml is read-only)
./codex-literature.sh
./codex-literature.sh mcp list      # should list: paper_search, zotero
```

Detailed step-by-step (中文): [`docs/首次运行清单.md`](docs/首次运行清单.md) · progress log: [`docs/明日继续进度.md`](docs/明日继续进度.md).

The launcher gates full Codex startup on the readiness preflight so failed imports are caught
early. Two layers are checked: (a) local MCP startup (commands, env, packages, registration);
(b) end-to-end network (Zotero Web API + at least one paper-search source). If the local layer
is ready but external DNS is down, `mcp list` still works; to open Codex for offline inspection:

```bash
CODEX_LITERATURE_ALLOW_OFFLINE=1 ./codex-literature.sh
```

## Zotero access modes

Toggle safely with the helper (only flips `ZOTERO_LOCAL`, never prints secrets):

```bash
./set-zotero-mode.sh status
./set-zotero-mode.sh web      # Web API — read+write. REQUIRED for importing. (default)
./set-zotero-mode.sh local    # Local API — READ-ONLY. search/read only, imports won't work.
```

| Mode | Reach | Writes (import) | Notes |
|------|-------|-----------------|-------|
| `web` | cloud `api.zotero.org` | ✅ | Works from WSL/sandbox. Imported items sync to desktop. **Default.** |
| `local` | `127.0.0.1:23119` | ❌ read-only | Fast local reads + full-text. Needs Zotero desktop + local API enabled. From WSL requires **mirrored networking** (see below). |

Recommended split: **import with `web`, read/search local library with `local`, translate on Windows.**

## WSL2 → Windows networking (for local mode)

By default WSL2 uses NAT and cannot reach Windows `localhost` services (Zotero `23119`,
pdf2zh `8890`). To use local mode from WSL, switch to **mirrored** networking:

1. `C:\Users\<you>\.wslconfig`:
   ```ini
   [wsl2]
   networkingMode=mirrored
   ```
2. `wsl --shutdown`, reopen.
3. Verify: `wslinfo --networking-mode` → `mirrored`; `curl -i http://127.0.0.1:23119/api/`.
4. If still blocked, allow the Hyper-V firewall (admin PowerShell):
   ```powershell
   Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow
   ```

Requires Windows 11 22H2+ and WSL ≥ 2.0.0. On Windows 10, use `netsh portproxy` instead.

## Translation chain (optional, EN→ZH)

Turn an English PDF into a Chinese translation attached back onto its Zotero item — driven
entirely from the terminal (or by Codex), no Zotero UI needed:

```bash
./start-pdf2zh.sh                                              # ensure the pdf2zh server (8890) is up
./translate-pdf.sh "/mnt/c/.../paper.pdf" siliconflowfree dual  # → mono/dual PDFs in the translated/ dir
./attach-to-zotero.sh <parentItemKey> "/mnt/d/.../paper.no_watermark.zh.dual.pdf" "中文译本(双语)"
```

Uses the free SiliconFlow engine and the pdf2zh **next** engine (the classic `pdf2zh` engine
fails on common packaged builds — see SETUP). Attach-back goes through the Zotero **Web API**
because the local API is read-only. Requires WSL mirrored networking (server is on Windows).

Full setup, the reverse-engineered `/translate` contract, the engine caveat, and an
alternative Zotero-side Actions & Tags route are documented in
**[`pdf2zh-translation/SETUP.md`](pdf2zh-translation/SETUP.md)**.

## First end-to-end test prompt

Start with a small test collection:

```text
检索 2023 年以来 retrieval augmented generation 的开放获取论文，先选 3 篇。
创建 Zotero collection：Codex MCP Test - RAG。
能通过 DOI 或 arXiv URL 导入的导入 Zotero；能找到开放 PDF 的附加 PDF。
每篇添加 tags：codex-mcp-test, RAG, to-translate。
最后输出：标题、年份、DOI/arXiv、PDF 状态、Zotero 导入状态。
```

## Safety notes

- Import ≤ 3 papers on the first run; output a candidate list before any bulk import.
- Import metadata only when a PDF is not open access.
- Keep `mcp-literature.env` out of git (already in `.gitignore`); never paste API keys into chat.
- If a key was ever exposed, revoke it on zotero.org and re-enter via `set-zotero-web-api-env.sh`.
- On errors, stay in a test collection — never operate on your main library.

## Files

| File | Purpose |
|------|---------|
| `codex-literature.sh` | Launch Codex with MCP servers injected at runtime (no config write needed) |
| `configure-codex-literature.sh` | Create env file + append MCP config when `~/.codex/config.toml` is writable |
| `install-literature-mcp-tools.sh` | Install both MCP servers locally (mirror fallback) |
| `doctor.sh` | One-shot health check of the whole system (networking, Zotero/pdf2zh servers, Web API write) |
| `check-literature-mcp-ready.sh` | Readiness preflight (commands, creds, packages, DNS, local API, registration) |
| `verify-literature-mcp.sh` | Local smoke checks for the two servers |
| `set-zotero-web-api-env.sh` | Enter Zotero Web API credentials without exposing them in chat/history |
| `set-zotero-mode.sh` | Toggle `ZOTERO_LOCAL` between `web` / `local` |
| `start-pdf2zh.sh` | Start the pdf2zh translation server (8890) on demand |
| `translate-pdf.sh` | Translate a PDF via the pdf2zh `/translate` API (→ mono/dual) |
| `attach-to-zotero.sh` | Attach a local file to a Zotero item via the Web API |
| `paper-search-mcp-wrapper.sh` / `zotero-mcp-wrapper.sh` | Server launchers (prefer local install, fall back to uvx) |
| `codex-config-snippet*.toml` | MCP config blocks to paste into `~/.codex/config.toml` |
| `mcp-literature.env.example` | Credential template (copy to `mcp-literature.env`, kept private) |
| `translate-and-attach.sh` | One-shot: ensure server → translate → attach back to Zotero |
| `batch-translate.sh` | Batch-translate a whole collection/tag (discover → translate → attach, idempotent) |
| `pdf2zh-translation/` | EN→ZH translation chain: setup guide + Actions & Tags script |
| `docs/` | Chinese walkthrough & progress log |

## Credits & license

Orchestration layer over [paper-search-mcp](https://github.com/openags/paper-search-mcp),
[zotero-mcp](https://github.com/54yyyu/zotero-mcp), [pdf2zh](https://github.com/PDFMathTranslate/PDFMathTranslate),
and [zotero-actions-tags](https://github.com/windingwind/zotero-actions-tags) — please respect
their licenses. This repository: MIT (add a `LICENSE` file before publishing).
