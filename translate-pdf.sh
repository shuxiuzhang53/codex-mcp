#!/usr/bin/env bash
set -euo pipefail

# 通过 PDF2Zh 的 8890 API 翻译一个 PDF 文件(终端触发)。
# 译本落在 D:\zotero_translate\server\translated\ ,返回 fileList。
# 不负责挂回 Zotero —— 那步由调用方(如 Codex + zotero-mcp)完成。
#
# 用法: ./translate-pdf.sh <pdf路径> [service] [mode]
#   service: 翻译引擎, 默认 siliconflowfree(免费)
#   mode:    mono | dual | compare | all , 默认 mono(最快, 只出纯中文)

PDF="${1:?用法: translate-pdf.sh <pdf路径> [service] [mode]}"
SERVICE="${2:-siliconflowfree}"
MODE="${3:-dual}"
ENGINE="${PDF2ZH_ENGINE:-pdf2zh_next}"   # 本机实测:pdf2zh_next 可用;老版 pdf2zh 因二进制不匹配失败
PORT="${PDF2ZH_PORT:-8890}"
URL="http://127.0.0.1:${PORT}/translate"
# 输出落在 D:\zotero_translate\server\translated\ ,命名如:
#   <fileName去扩展>.no_watermark.zh.mono.pdf / .dual.pdf

[ -f "$PDF" ] || { echo "找不到 PDF: $PDF" >&2; exit 1; }

mono=false; dual=false; compare=false
case "$MODE" in
  mono) mono=true ;;
  dual) dual=true ;;
  compare) compare=true ;;
  all) mono=true; dual=true; compare=true ;;
  *) echo "未知 mode: $MODE (mono|dual|compare|all)" >&2; exit 2 ;;
esac

TMP=$(mktemp /tmp/pdf2zh-req-XXXXXX.json)
trap 'rm -f "$TMP"' EXIT

b64=$(base64 -w0 "$PDF")
fname=$(basename "$PDF")

jq -n --arg fc "data:application/pdf;base64,$b64" \
      --arg fn "$fname" --arg svc "$SERVICE" --arg eng "$ENGINE" \
      --argjson mono "$mono" --argjson dual "$dual" --argjson compare "$compare" \
  '{fileContent:$fc, fileName:$fn, engine:$eng, service:$svc,
    sourceLang:"en", targetLang:"zh", qps:4, thread_num:4,
    mono:$mono, dual:$dual, compare:$compare}' > "$TMP"

echo "POST $URL  (engine=$ENGINE, service=$SERVICE, mode=$MODE, file=$fname, $(wc -c <"$PDF") bytes)"
echo "注意:同步接口, 翻译较慢(免费引擎单篇约 2-4 分钟), 请耐心等待返回 fileList。"
curl -sS --noproxy '*' --max-time 600 \
  -X POST -H 'Content-Type: application/json' \
  --data @"$TMP" "$URL"
echo
