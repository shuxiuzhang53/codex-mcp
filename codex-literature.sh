#!/usr/bin/env bash
set -euo pipefail

# Launch Codex with paper-search and Zotero MCP servers injected at runtime.
# This works even when ~/.codex/config.toml is read-only.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CODEX_LITERATURE_ROOT:-$SCRIPT_DIR}"
if [[ "${CODEX_LITERATURE_SKIP_PREFLIGHT:-0}" != "1" ]]; then
  if [[ "${1:-}" == "mcp" && "${2:-}" == "list" ]]; then
    :
  elif ! "$ROOT/check-literature-mcp-ready.sh" >/dev/null 2>&1; then
    cat >&2 <<MSG
Literature MCP is not fully ready yet.

Run this for details:
  $ROOT/check-literature-mcp-ready.sh

To inspect Codex MCP registration anyway:
  CODEX_LITERATURE_SKIP_PREFLIGHT=1 $ROOT/codex-literature.sh mcp list

To open Codex for offline MCP inspection only:
  CODEX_LITERATURE_ALLOW_OFFLINE=1 $ROOT/codex-literature.sh
MSG
    exit 2
  fi
fi

exec codex \
  -c 'features.rmcp_client=true' \
  -c "mcp_servers.paper_search.command=\"$ROOT/paper-search-mcp-wrapper.sh\"" \
  -c 'mcp_servers.paper_search.enabled=true' \
  -c 'mcp_servers.paper_search.startup_timeout_sec=30' \
  -c "mcp_servers.zotero.command=\"$ROOT/zotero-mcp-wrapper.sh\"" \
  -c 'mcp_servers.zotero.enabled=true' \
  -c 'mcp_servers.zotero.startup_timeout_sec=30' \
  "$@"
