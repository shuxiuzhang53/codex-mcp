#!/usr/bin/env bash
set -euo pipefail

# 一条命令跑完:确保 server → 翻译 → 挂回 Zotero。
#
# 用法: ./translate-and-attach.sh <源PDF> <父条目key> [mode] [service]
#   mode:    mono | dual | compare , 默认 dual
#   service: 翻译引擎, 默认 siliconflowfree(免费)
#
# 依赖: mirrored 网络 + PDF2Zh 已装 + env 里 ZOTERO_API_KEY(write)/ZOTERO_LIBRARY_ID。
# 译本目录默认 /mnt/d/zotero_translate/server/translated ,可用 PDF2ZH_TRANSLATED_DIR 覆盖。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PDF="${1:?用法: translate-and-attach.sh <源PDF> <父条目key> [mode] [service]}"
PARENT="${2:?缺少父条目 key}"
MODE="${3:-dual}"
SERVICE="${4:-siliconflowfree}"
TRANSLATED_DIR="${PDF2ZH_TRANSLATED_DIR:-/mnt/d/zotero_translate/server/translated}"

[ -f "$PDF" ] || { echo "找不到源 PDF: $PDF" >&2; exit 1; }
case "$MODE" in mono|dual|compare) ;; *) echo "mode 只支持 mono|dual|compare" >&2; exit 2;; esac

base="$(basename "$PDF")"; stem="${base%.*}"
OUT="$TRANSLATED_DIR/${stem}.no_watermark.zh.${MODE}.pdf"
START=$(date +%s)

echo "[1/3] 确保 PDF2Zh server ..."
"$SCRIPT_DIR/start-pdf2zh.sh"

echo "[2/3] 翻译 ($MODE, $SERVICE) ..."
"$SCRIPT_DIR/translate-pdf.sh" "$PDF" "$SERVICE" "$MODE" || true

echo "等待译本产出: $OUT"
found=""
for _ in $(seq 1 120); do
  if [ -f "$OUT" ] && [ "$(stat -c %Y "$OUT")" -ge "$START" ]; then found=1; break; fi
  sleep 5
done
[ -n "$found" ] || { echo "超时(10min)未见新译本: $OUT" >&2; exit 1; }

echo "[3/3] 挂回 Zotero 条目 $PARENT ..."
"$SCRIPT_DIR/attach-to-zotero.sh" "$PARENT" "$OUT" "中文译本(${MODE})-pdf2zh"

echo "✅ 全部完成:$stem → 条目 $PARENT"
