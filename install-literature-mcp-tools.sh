#!/usr/bin/env bash
set -euo pipefail

if ! timeout 5s getent hosts pypi.org >/dev/null 2>&1; then
  cat >&2 <<'MSG'
PyPI DNS lookup failed.

The MCP packages cannot be installed until this environment can resolve
pypi.org. Fix network/DNS first, then rerun this script.
MSG
  exit 2
fi

UV_DEFAULT_INDEX="${UV_DEFAULT_INDEX:-${CODEX_LITERATURE_UV_INDEX:-}}"
UV_INDEX_ARGS=()
if [[ -n "$UV_DEFAULT_INDEX" ]]; then
  UV_INDEX_ARGS+=(--default-index "$UV_DEFAULT_INDEX")
  echo "Using Python package index: $UV_DEFAULT_INDEX"
fi

ROOT="${CODEX_LITERATURE_ROOT:-$HOME/codex-mcp}"
PAPER_SEARCH_VENV="${CODEX_LITERATURE_PAPER_SEARCH_VENV:-$ROOT/.venv-paper-search}"
ZOTERO_PACKAGE="${CODEX_LITERATURE_ZOTERO_PACKAGE:-zotero-mcp-server[semantic]}"

echo "Installing paper-search-mcp into dedicated venv: $PAPER_SEARCH_VENV"
uv venv "$PAPER_SEARCH_VENV"
uv pip install --python "$PAPER_SEARCH_VENV/bin/python" "${UV_INDEX_ARGS[@]}" paper-search-mcp

echo "Verifying paper_search_mcp.server module"
"$PAPER_SEARCH_VENV/bin/python" -c 'import paper_search_mcp.server'

echo "Installing Zotero MCP tool: $ZOTERO_PACKAGE"
uv tool install "${UV_INDEX_ARGS[@]}" "$ZOTERO_PACKAGE"

echo "Verifying Zotero MCP semantic dependencies"
zotero-mcp db-status >/dev/null

echo "Installed tools:"
uv tool list
