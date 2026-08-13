#!/usr/bin/env bash
set -euo pipefail

# 一条命令跑完:确保 server → 翻译 → 挂回 Zotero。
#
# 用法: ./translate-and-attach.sh <源PDF> <父条目key> [mode] [service]
#   mode:    mono | dual | compare , 默认 dual
#   service: 翻译引擎, 默认 siliconflowfree(免费)
#
# 依赖: mirrored 网络 + PDF2Zh 已装 + env 里 ZOTERO_API_KEY(write)/ZOTERO_LIBRARY_ID。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PDF="${1:?用法: translate-and-attach.sh <源PDF> <父条目key> [mode] [service]}"
PARENT="${2:?缺少父条目 key}"
MODE="${3:-dual}"
SERVICE="${4:-siliconflowfree}"

[ -f "$PDF" ] || { echo "找不到源 PDF: $PDF" >&2; exit 1; }

echo "[1/3] 确保 PDF2Zh server ..."
"$SCRIPT_DIR/start-pdf2zh.sh"

echo "[2/3] 翻译 ($MODE, $SERVICE) ..."
# translate-pdf.sh 把实际译本绝对路径打到 stdout(取自 /translate 的 fileList,不猜文件名)
mapfile -t OUTS < <("$SCRIPT_DIR/translate-pdf.sh" "$PDF" "$SERVICE" "$MODE")
[ "${#OUTS[@]}" -gt 0 ] || { echo "翻译未产出译本" >&2; exit 1; }
OUT="${OUTS[0]}"
echo "译本: $OUT"

echo "[3/3] 挂回 Zotero 条目 $PARENT ..."
"$SCRIPT_DIR/attach-to-zotero.sh" "$PARENT" "$OUT" "中文译本(${MODE})-pdf2zh"

echo "✅ 全部完成:$(basename "$PDF") → 条目 $PARENT"
