#!/usr/bin/env bash
set -u

echo "== Codex CLI =="
command -v codex || true
codex --version 2>/dev/null || true

echo
echo "== uvx =="
command -v uvx || true
uvx --version 2>/dev/null || true

echo
echo "== Zotero local app =="
command -v zotero || true
timeout 5s flatpak list 2>/dev/null | grep -i zotero || true
timeout 5s snap list 2>/dev/null | grep -i zotero || true
timeout 5s find /usr/share/applications "$HOME/.local/share/applications" -maxdepth 1 -iname '*zotero*' -print 2>/dev/null | head -20 || true

echo
echo "== Env template/private file =="
ls -l "$HOME/codex-mcp/mcp-literature.env.example" "$HOME/codex-mcp/mcp-literature.env" 2>/dev/null || true

echo
echo "== Readiness preflight =="
"$HOME/codex-mcp/check-literature-mcp-ready.sh" || true

echo
echo "== paper-search-mcp module check =="
paper_search_python="${CODEX_LITERATURE_PAPER_SEARCH_PYTHON:-$HOME/codex-mcp/.venv-paper-search/bin/python}"
if [[ -x "$paper_search_python" ]]; then
  "$paper_search_python" -c 'import paper_search_mcp.server; print("paper_search_import_ok")'
else
  echo "missing: $paper_search_python"
fi

echo
echo "== zotero-mcp startup check =="
timeout 35s "$HOME/codex-mcp/zotero-mcp-wrapper.sh" --help 2>&1 | sed -n '1,80p'

echo
echo "== zotero-mcp semantic search check =="
if timeout 60s zotero-mcp db-status >/tmp/zotero-mcp-db-status.$$ 2>&1; then
  sed -n '1,120p' /tmp/zotero-mcp-db-status.$$
  echo "zotero_semantic_ok"
else
  sed -n '1,160p' /tmp/zotero-mcp-db-status.$$
  echo "zotero_semantic_missing"
fi
rm -f /tmp/zotero-mcp-db-status.$$
