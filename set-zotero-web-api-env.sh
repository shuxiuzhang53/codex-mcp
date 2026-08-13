#!/usr/bin/env bash
set -euo pipefail

ROOT="${CODEX_LITERATURE_ROOT:-$HOME/codex-mcp}"
ENV_FILE="${CODEX_LITERATURE_MCP_ENV:-$ROOT/mcp-literature.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  if [[ -f "$ROOT/mcp-literature.env.example" ]]; then
    cp "$ROOT/mcp-literature.env.example" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
  else
    echo "Env template not found: $ROOT/mcp-literature.env.example" >&2
    exit 1
  fi
fi

chmod 600 "$ENV_FILE"

read -r -p "Zotero library id/user id: " library_id
read -r -p "Zotero library type [user]: " library_type
library_type="${library_type:-user}"
read -r -p "Unpaywall/contact email: " email
read -r -s -p "New Zotero API key: " api_key
printf '\n'

if [[ -z "$library_id" || -z "$email" || -z "$api_key" ]]; then
  echo "Library id, email, and API key are required." >&2
  exit 2
fi

tmp="$(mktemp)"
awk -v zotero_local="false" \
    -v api_key="$api_key" \
    -v library_id="$library_id" \
    -v library_type="$library_type" \
    -v email="$email" '
  BEGIN {
    seen_zotero_local = 0
    seen_api_key = 0
    seen_library_id = 0
    seen_library_type = 0
    seen_unpaywall = 0
    seen_paper_unpaywall = 0
  }
  /^ZOTERO_LOCAL=/ {
    print "ZOTERO_LOCAL=\"" zotero_local "\""
    seen_zotero_local = 1
    next
  }
  /^ZOTERO_API_KEY=/ {
    print "ZOTERO_API_KEY=\"" api_key "\""
    seen_api_key = 1
    next
  }
  /^ZOTERO_LIBRARY_ID=/ {
    print "ZOTERO_LIBRARY_ID=\"" library_id "\""
    seen_library_id = 1
    next
  }
  /^ZOTERO_LIBRARY_TYPE=/ {
    print "ZOTERO_LIBRARY_TYPE=\"" library_type "\""
    seen_library_type = 1
    next
  }
  /^UNPAYWALL_EMAIL=/ {
    print "UNPAYWALL_EMAIL=\"" email "\""
    seen_unpaywall = 1
    next
  }
  /^PAPER_SEARCH_MCP_UNPAYWALL_EMAIL=/ {
    print "PAPER_SEARCH_MCP_UNPAYWALL_EMAIL=\"" email "\""
    seen_paper_unpaywall = 1
    next
  }
  { print }
  END {
    if (!seen_paper_unpaywall) print "PAPER_SEARCH_MCP_UNPAYWALL_EMAIL=\"" email "\""
    if (!seen_unpaywall) print "UNPAYWALL_EMAIL=\"" email "\""
    if (!seen_zotero_local) print "ZOTERO_LOCAL=\"" zotero_local "\""
    if (!seen_api_key) print "ZOTERO_API_KEY=\"" api_key "\""
    if (!seen_library_id) print "ZOTERO_LIBRARY_ID=\"" library_id "\""
    if (!seen_library_type) print "ZOTERO_LIBRARY_TYPE=\"" library_type "\""
  }
' "$ENV_FILE" > "$tmp"

mv "$tmp" "$ENV_FILE"
chmod 600 "$ENV_FILE"

echo "Updated $ENV_FILE for Zotero Web API mode."
echo "Run: $ROOT/check-literature-mcp-ready.sh"
