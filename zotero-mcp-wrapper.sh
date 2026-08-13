#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${CODEX_LITERATURE_MCP_ENV:-$HOME/codex-mcp/mcp-literature.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

if command -v zotero-mcp >/dev/null 2>&1; then
  exec zotero-mcp serve "$@"
fi

exec uvx --from zotero-mcp-server zotero-mcp serve "$@"
