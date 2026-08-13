#!/usr/bin/env bash
set -euo pipefail

# 通过 PDF2Zh 的 8890 API 翻译一个 PDF,并把**实际译本的绝对路径**打到 stdout(每行一个),
# 供 translate-and-attach.sh / batch 消费。人类可读日志走 stderr。
# 译本路径优先取 /translate 返回的 fileList(准确,不猜文件名);curl 超时则回退扫描目录。
#
# 用法: ./translate-pdf.sh <pdf路径> [service] [mode]
#   service: 翻译引擎, 默认 siliconflowfree(免费)
#   mode:    mono | dual | compare , 默认 dual

PDF="${1:?用法: translate-pdf.sh <pdf路径> [service] [mode]}"
SERVICE="${2:-siliconflowfree}"
MODE="${3:-dual}"
ENGINE="${PDF2ZH_ENGINE:-pdf2zh_next}"   # 本机实测:pdf2zh_next 可用;老版 pdf2zh 因二进制不匹配失败
PORT="${PDF2ZH_PORT:-8890}"
URL="http://127.0.0.1:${PORT}/translate"
TRANSLATED_DIR="${PDF2ZH_TRANSLATED_DIR:-/mnt/d/zotero_translate/server/translated}"

[ -f "$PDF" ] || { echo "找不到 PDF: $PDF" >&2; exit 1; }
case "$MODE" in mono|dual|compare) ;; *) echo "mode 只支持 mono|dual|compare" >&2; exit 2;; esac

log() { echo "$@" >&2; }
mono=false; dual=false; compare=false; eval "$MODE=true"

REQ=$(mktemp /tmp/pdf2zh-req-XXXXXX.json)
RESP=$(mktemp /tmp/pdf2zh-resp-XXXXXX.json)
trap 'rm -f "$REQ" "$RESP"' EXIT

b64=$(base64 -w0 "$PDF"); fname=$(basename "$PDF")
jq -n --arg fc "data:application/pdf;base64,$b64" --arg fn "$fname" --arg svc "$SERVICE" --arg eng "$ENGINE" \
   --argjson mono "$mono" --argjson dual "$dual" --argjson compare "$compare" \
  '{fileContent:$fc, fileName:$fn, engine:$eng, service:$svc, sourceLang:"en", targetLang:"zh",
    qps:4, thread_num:4, mono:$mono, dual:$dual, compare:$compare}' > "$REQ"

log "POST $URL  (engine=$ENGINE, service=$SERVICE, mode=$MODE, file=$fname)"
log "同步接口, 免费引擎单篇约 2-4 分钟, 请稍候 ..."
START=$(date +%s)
code=$(curl -sS --noproxy '*' --max-time 600 -o "$RESP" -w '%{http_code}' \
  -X POST -H 'Content-Type: application/json' --data @"$REQ" "$URL" 2>/dev/null) || code=000

# 优先:从返回的 fileList 拿准确文件名
mapfile -t NAMES < <(python3 - "$RESP" <<'PY' 2>/dev/null || true
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
if d.get("status")=="success":
    for f in d.get("fileList",[]): print(f)
PY
)

PATHS=()
if [ "${#NAMES[@]}" -gt 0 ]; then
  for n in "${NAMES[@]}"; do PATHS+=("$TRANSLATED_DIR/$n"); done
else
  # 返回不是成功 JSON:要么服务器报错,要么 curl 超时(服务器仍在后台翻)
  errmsg=$(python3 -c "import json,sys;print(json.load(open('$RESP')).get('message','')[:300])" 2>/dev/null || true)
  if [ -n "$errmsg" ]; then log "翻译报错: $errmsg"; exit 1; fi
  log "未拿到 fileList(HTTP=$code,可能超时),回退扫描 $TRANSLATED_DIR ..."
  stem="${fname%.*}"
  for _ in $(seq 1 60); do
    while IFS= read -r p; do PATHS+=("$p"); done < <(
      find "$TRANSLATED_DIR" -maxdepth 1 -type f -name "${stem}*${MODE}.pdf" \
        -newermt "@$START" 2>/dev/null)
    [ "${#PATHS[@]}" -gt 0 ] && break
    sleep 5
  done
fi

# 校验存在并输出绝对路径
found=0
for p in "${PATHS[@]}"; do
  if [ -f "$p" ]; then echo "$p"; found=$((found+1)); else log "警告: 预期译本未找到: $p"; fi
done
[ "$found" -gt 0 ] || { log "翻译未产出可用文件"; exit 1; }
log "✅ 译本 $found 个已产出"
