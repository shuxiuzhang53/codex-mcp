#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${CODEX_CONFIG:-$HOME/.codex/config.toml}"
SNIPPET="${CODEX_LITERATURE_SNIPPET:-$SCRIPT_DIR/codex-config-snippet.toml}"
ENV_EXAMPLE="$SCRIPT_DIR/mcp-literature.env.example"
ENV_FILE="$SCRIPT_DIR/mcp-literature.env"

if [[ ! -f "$ENV_FILE" && -f "$ENV_EXAMPLE" ]]; then
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "Created private env file: $ENV_FILE"
  echo "Fill in Zotero and Unpaywall values before doing write/import tests."
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "Config not found: $CONFIG" >&2
  exit 1
fi

if [[ ! -w "$CONFIG" ]]; then
  echo "Codex config is not writable: $CONFIG" >&2
  echo "Use runtime launcher instead:" >&2
  echo "  $SCRIPT_DIR/codex-literature.sh" >&2
  exit 2
fi

if grep -q 'mcp_servers\.paper_search' "$CONFIG" && grep -q 'mcp_servers\.zotero' "$CONFIG"; then
  echo "Codex config already contains paper_search and zotero MCP blocks."
  exit 0
fi

backup="$CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
cp "$CONFIG" "$backup"
{
  printf '\n\n# ============================================================\n'
  printf '# Literature MCP: paper-search-mcp + zotero-mcp\n'
  printf '# Added by %s/configure-codex-literature.sh\n' "$SCRIPT_DIR"
  printf '# ============================================================\n'
  cat "$SNIPPET"
} >> "$CONFIG"

echo "Backed up config to: $backup"
echo "Appended Literature MCP config to: $CONFIG"
echo "Restart Codex CLI, then run: codex mcp list"
