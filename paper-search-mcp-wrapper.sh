#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${CODEX_LITERATURE_MCP_ENV:-$HOME/codex-mcp/mcp-literature.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

PAPER_SEARCH_PYTHON="${CODEX_LITERATURE_PAPER_SEARCH_PYTHON:-$HOME/codex-mcp/.venv-paper-search/bin/python}"
if [[ -x "$PAPER_SEARCH_PYTHON" ]]; then
  exec "$PAPER_SEARCH_PYTHON" -m paper_search_mcp.server "$@"
fi

exec uv run --with paper-search-mcp python -m paper_search_mcp.server "$@"
