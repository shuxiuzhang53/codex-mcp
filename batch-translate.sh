#!/usr/bin/env bash
set -euo pipefail

# 批量翻译一个 Zotero collection 或标签下的所有条目,逐篇翻译并挂回。
#
# 用法:
#   ./batch-translate.sh collection "综述-RAG" [mode] [service]
#   ./batch-translate.sh tag        "to-translate" [mode] [service]
#     mode: mono|dual|compare (默认 dual)   service: 默认 siliconflowfree
#   DRY_RUN=1 ./batch-translate.sh ...   # 只列出将翻译哪些,不真翻(先验证)
#
# 依赖: mirrored 网络 + Zotero 开着(读列表用本地 API) + env 里 ZOTERO_API_KEY(write)/ZOTERO_LIBRARY_ID。
# 幂等: 条目下已有译本(标题含 pdf2zh 或文件名含 .zh.)则跳过。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${CODEX_LITERATURE_MCP_ENV:-$SCRIPT_DIR/mcp-literature.env}"
TYPE="${1:?用法: batch-translate.sh <collection|tag> <名称> [mode] [service]}"
VALUE="${2:?缺少 collection 名称或标签}"
MODE="${3:-dual}"
SERVICE="${4:-siliconflowfree}"

LIB=$(grep -E '^ZOTERO_LIBRARY_ID=' "$ENV_FILE" | cut -d= -f2- | tr -d '"')
[ -n "$LIB" ] || { echo "env 缺少 ZOTERO_LIBRARY_ID" >&2; exit 1; }
# Zotero 数据目录(WSL 视角),用于定位附件文件。改成你自己的或用 ZOTERO_DATA_DIR 覆盖。
DATA_DIR="${ZOTERO_DATA_DIR:-/mnt/c/Users/$USER/Zotero}"

WORK=$(mktemp /tmp/batch-work-XXXXXX.tsv)
trap 'rm -f "$WORK"' EXIT

echo "发现 [$TYPE] = $VALUE 下的条目 ..."
python3 - "$TYPE" "$VALUE" "$LIB" "$DATA_DIR" > "$WORK" <<'PY'
import sys, json, urllib.request, urllib.parse, os
typ, value, lib, data_dir = sys.argv[1:5]
BASE = f"http://127.0.0.1:23119/api/users/{lib}"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))  # 绕过 http_proxy

def get(path):
    with opener.open(BASE + path, timeout=15) as r:
        return json.load(r)

# 1) 定位顶层条目列表
if typ == "collection":
    coll = None
    for c in get("/collections?limit=100"):
        if c["data"].get("name") == value:
            coll = c["key"]; break
    if not coll:
        sys.stderr.write(f"找不到 collection: {value}\n"); sys.exit(3)
    items = get(f"/collections/{coll}/items/top?limit=100&itemType=-attachment")
elif typ == "tag":
    items = get("/items/top?limit=100&itemType=-attachment&tag=" + urllib.parse.quote(value))
else:
    sys.stderr.write("第一个参数只能是 collection 或 tag\n"); sys.exit(2)

def is_translation(d):
    t = (d.get("title") or ""); f = (d.get("filename") or "")
    return ("pdf2zh" in t) or (".zh." in f)

# 2) 每个条目:找源 PDF / 判断是否已翻
for it in items:
    key = it["key"]; title = (it["data"].get("title") or key)[:60]
    try:
        kids = get(f"/items/{key}/children")
    except Exception as e:
        print(f"SKIP\t{key}\t\t{title}\t取子条目失败:{e}"); continue
    already = any(k["data"].get("itemType")=="attachment" and is_translation(k["data"]) for k in kids)
    if already:
        print(f"SKIP\t{key}\t\t{title}\t已有译本"); continue
    src = None
    for k in kids:
        d = k["data"]
        if d.get("itemType")=="attachment" and d.get("contentType")=="application/pdf" and not is_translation(d):
            fn = d.get("filename")
            if fn:
                path = os.path.join(data_dir, "storage", k["key"], fn)
                if os.path.exists(path):
                    src = path; break
    if not src:
        print(f"SKIP\t{key}\t\t{title}\t无可用源 PDF"); continue
    print(f"TODO\t{key}\t{src}\t{title}")
PY

todo=$(grep -c '^TODO' "$WORK" || true)
skip=$(grep -c '^SKIP' "$WORK" || true)
echo "计划:待翻译 $todo 篇,跳过 $skip 篇"
echo "---- 明细 ----"
awk -F'\t' '{printf "  [%s] %s %s\n", $1, $4, ($1=="SKIP"?"("$5")":"")}' "$WORK"
echo "--------------"

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "(DRY_RUN=1,只列计划,不翻译)"; exit 0
fi
[ "$todo" -gt 0 ] || { echo "没有需要翻译的条目。"; exit 0; }

ok=0; fail=0; failed_list=""
i=0
while IFS=$'\t' read -r action key pdf title; do
  [ "$action" = "TODO" ] || continue
  i=$((i+1))
  echo; echo "==== [$i/$todo] $title ===="
  if "$SCRIPT_DIR/translate-and-attach.sh" "$pdf" "$key" "$MODE" "$SERVICE"; then
    ok=$((ok+1))
  else
    fail=$((fail+1)); failed_list="$failed_list\n  - $title ($key)"
  fi
done < "$WORK"

echo; echo "================ 批量完成 ================"
echo "成功 $ok 篇,失败 $fail 篇,跳过 $skip 篇"
[ "$fail" -gt 0 ] && printf "失败列表:%b\n" "$failed_list"
exit 0
