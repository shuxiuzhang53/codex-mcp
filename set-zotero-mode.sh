#!/usr/bin/env bash
set -euo pipefail

# 在 Zotero 访问模式之间安全切换,只改 mcp-literature.env 里的 ZOTERO_LOCAL 一行,
# 不打印任何密钥。
#
# 用法:
#   ./set-zotero-mode.sh local   # 本地直连(127.0.0.1:23119)。注意:local API 只读,导入(写)不可用!
#   ./set-zotero-mode.sh web     # Zotero Web API(云端),读写都行,是导入所必需
#   ./set-zotero-mode.sh status  # 只看当前模式
#
# 本地模式前提:WSL 切到 mirrored 网络 + Zotero 桌面端开着并启用 local API。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${CODEX_LITERATURE_MCP_ENV:-$SCRIPT_DIR/mcp-literature.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "找不到 env 文件: $ENV_FILE" >&2
  exit 1
fi

current() {
  local v
  v="$(grep -E '^ZOTERO_LOCAL=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"' || true)"
  [[ "$v" == "true" ]] && echo "local" || echo "web"
}

set_local() {
  if grep -qE '^ZOTERO_LOCAL=' "$ENV_FILE"; then
    sed -i 's/^ZOTERO_LOCAL=.*/ZOTERO_LOCAL="'"$1"'"/' "$ENV_FILE"
  else
    printf 'ZOTERO_LOCAL="%s"\n' "$1" >> "$ENV_FILE"
  fi
}

case "${1:-status}" in
  local)
    set_local true
    echo "已切到 [local] 本地直连模式 (ZOTERO_LOCAL=true)。"
    echo "⚠️  Zotero local API 只读:可搜索/读取,但导入(写入)不可用 —— 导入请切回 web。"
    echo "前提:mirrored 网络 + Zotero 开着且启用 local API。用 check-literature-mcp-ready.sh 验证。"
    ;;
  web)
    set_local false
    echo "已切到 [web] Zotero Web API 模式 (ZOTERO_LOCAL=false)。读写均可,导入可用。"
    echo "需要 mcp-literature.env 里的 ZOTERO_API_KEY / ZOTERO_LIBRARY_ID 有效。"
    ;;
  status)
    echo "当前模式: [$(current)]  ($ENV_FILE)"
    ;;
  *)
    echo "用法: $0 {local|web|status}" >&2
    exit 2
    ;;
esac
