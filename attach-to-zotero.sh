#!/usr/bin/env bash
set -euo pipefail

# 把一个本地文件作为 imported_file 附件挂到指定 Zotero 条目下(经 Zotero Web API)。
# Zotero 本地(Connector)API 不支持写,所以走云端 Web API;附件会同步回桌面端。
#
# 用法: ./attach-to-zotero.sh <父条目key> <文件路径> [标题] [Zotero里的文件名]
# 依赖: mcp-literature.env 里的 ZOTERO_API_KEY(需 write 权限) 和 ZOTERO_LIBRARY_ID。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${CODEX_LITERATURE_MCP_ENV:-$SCRIPT_DIR/mcp-literature.env}"

PARENT="${1:?用法: attach-to-zotero.sh <父条目key> <文件路径> [标题] [文件名]}"
FILE="${2:?缺少文件路径}"
TITLE="${3:-中文译本-pdf2zh}"
[ -f "$FILE" ] || { echo "找不到文件: $FILE" >&2; exit 1; }
FNAME="${4:-$(basename "$FILE")}"

KEY=$(grep -E '^ZOTERO_API_KEY=' "$ENV_FILE" | cut -d= -f2- | tr -d '"')
LIB=$(grep -E '^ZOTERO_LIBRARY_ID=' "$ENV_FILE" | cut -d= -f2- | tr -d '"')
[ -n "$KEY" ] && [ -n "$LIB" ] || { echo "env 缺少 ZOTERO_API_KEY / ZOTERO_LIBRARY_ID" >&2; exit 1; }
API="https://api.zotero.org"

MD5=$(md5sum "$FILE" | cut -d' ' -f1)
SIZE=$(stat -c%s "$FILE")
MTIME=$(( $(stat -c %Y "$FILE") * 1000 ))
CT=$(file --mime-type -b "$FILE" 2>/dev/null || echo application/pdf)

# Step1: 创建附件条目
REQ=$(mktemp); TRAP_FILES="$REQ"
trap 'rm -f $TRAP_FILES' EXIT
python3 - "$PARENT" "$TITLE" "$FNAME" "$CT" > "$REQ" <<'PY'
import json,sys
parent,title,fname,ct=sys.argv[1:5]
print(json.dumps([{"itemType":"attachment","linkMode":"imported_file",
  "parentItem":parent,"title":title,"filename":fname,"contentType":ct}]))
PY
ITEM=$(curl -sS --max-time 20 -X POST -H "Zotero-API-Key: $KEY" -H 'Content-Type: application/json' \
  --data @"$REQ" "$API/users/$LIB/items" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);k=(d.get('success') or {}).get('0');print(k or '')")
[ -n "$ITEM" ] || { echo "创建附件条目失败(检查父条目 key / 写权限)" >&2; exit 1; }
echo "附件条目已建: $ITEM (parent=$PARENT)"

# Step2: 申请上传授权
AUTH=$(mktemp); TRAP_FILES="$TRAP_FILES $AUTH"
curl -sS --max-time 20 -X POST -H "Zotero-API-Key: $KEY" \
  -H 'Content-Type: application/x-www-form-urlencoded' -H 'If-None-Match: *' \
  --data-urlencode "md5=$MD5" --data-urlencode "filename=$FNAME" \
  --data-urlencode "filesize=$SIZE" --data-urlencode "mtime=$MTIME" --data "params=1" \
  "$API/users/$LIB/items/$ITEM/file" > "$AUTH"

if python3 -c "import json,sys;sys.exit(0 if json.load(open('$AUTH')).get('exists') else 1)"; then
  echo "文件已存在于 Zotero 存储(同 md5),无需再传。完成。"
  exit 0
fi

# Step3: multipart 上传到 S3(params 字段在前, file 最后)
mapfile -t FARGS < <(python3 -c "
import json;d=json.load(open('$AUTH'))
for k,v in d['params'].items(): print('-F'); print(f'{k}={v}')")
URL=$(python3 -c "import json;print(json.load(open('$AUTH'))['url'])")
UKEY=$(python3 -c "import json;print(json.load(open('$AUTH'))['uploadKey'])")
code=$(curl -sS --max-time 120 -o /dev/null -w '%{http_code}' "${FARGS[@]}" -F "file=@$FILE" "$URL")
[ "$code" = 201 ] || [ "$code" = 204 ] || { echo "S3 上传失败: HTTP $code" >&2; exit 1; }

# Step4: 注册上传
code=$(curl -sS --max-time 20 -o /dev/null -w '%{http_code}' -X POST -H "Zotero-API-Key: $KEY" \
  -H 'Content-Type: application/x-www-form-urlencoded' -H 'If-None-Match: *' \
  --data "upload=$UKEY" "$API/users/$LIB/items/$ITEM/file")
[ "$code" = 204 ] || { echo "注册失败: HTTP $code" >&2; exit 1; }

echo "✅ 已挂回 Zotero: 「$TITLE」 -> 条目 $PARENT (同步后桌面端可见)"
