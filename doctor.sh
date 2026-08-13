#!/usr/bin/env bash
set -u

# 一条命令体检整套系统(检索 + 翻译 + 挂回),任何一环坏了立刻定位。
# 只读检查,不改任何东西。用法: ./doctor.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${CODEX_LITERATURE_MCP_ENV:-$SCRIPT_DIR/mcp-literature.env}"
curl_local() { curl -sS --noproxy '*' --max-time 6 "$@"; }   # 本地服务绕过代理

P=0; W=0; F=0
sec()  { printf '\n== %s ==\n' "$1"; }
ok()   { P=$((P+1)); printf '  ✅ %s\n' "$1"; }
warn() { W=$((W+1)); printf '  ⚠️  %s\n' "$1"; }
bad()  { F=$((F+1)); printf '  ❌ %s\n' "$1"; }

sec "本地工具"
for c in curl jq python3 base64; do
  command -v "$c" >/dev/null 2>&1 && ok "$c" || bad "$c 缺失"
done

sec "WSL 网络(本地直连/翻译需要 mirrored)"
if command -v wslinfo >/dev/null 2>&1; then
  m=$(wslinfo --networking-mode 2>/dev/null)
  [ "$m" = mirrored ] && ok "networkingMode = mirrored" \
    || warn "networkingMode = ${m:-未知}(非 mirrored,WSL 可能够不到 Windows 的 23119/8890;见 README)"
else
  warn "非 WSL 或无 wslinfo,跳过网络模式检查"
fi

sec "Zotero 本地 API (23119, 读库/批量发现)"
if curl_local -o /dev/null -w '' "http://127.0.0.1:23119/api/" 2>/dev/null; then
  ok "Zotero local API 可达"
else
  warn "Zotero local API 不可达(是否开着 Zotero + 勾了本地 API?本地读/batch 需要)"
fi

sec "PDF2Zh 翻译 server (8890)"
if curl_local -o /dev/null -w '' "http://127.0.0.1:8890/" 2>/dev/null; then
  ok "PDF2Zh server 在运行"
else
  warn "PDF2Zh server 未运行(翻译前先跑 ./start-pdf2zh.sh)"
fi

sec "私有 env 与 Zotero Web API key(挂回需要写权限)"
if [ -f "$ENV_FILE" ]; then
  ok "env 文件存在"
  [ "$(stat -c '%a' "$ENV_FILE" 2>/dev/null)" = 600 ] && ok "env 权限 600" || warn "env 权限非 600"
  KEY=$(grep -E '^ZOTERO_API_KEY=' "$ENV_FILE" | cut -d= -f2- | tr -d '"')
  LIB=$(grep -E '^ZOTERO_LIBRARY_ID=' "$ENV_FILE" | cut -d= -f2- | tr -d '"')
  if [ -n "$KEY" ] && [ -n "$LIB" ]; then
    acc=$(curl -sS --max-time 12 -H "Zotero-API-Key: $KEY" "https://api.zotero.org/keys/current" 2>/dev/null \
      | python3 -c "import sys,json
try:
 d=json.load(sys.stdin);a=d.get('access',{}).get('user',{})
 print('write' if a.get('write') else 'nowrite', 'files' if a.get('files') else 'nofiles')
except Exception: print('invalid')" 2>/dev/null)
    case "$acc" in
      *invalid*|"") bad "Web API key 无效或无法验证(检查 key / 网络)" ;;
      *nowrite*)    bad "Web API key 没有 write 权限(挂回会失败,去 zotero.org 重建带写权限的 key)" ;;
      *nofiles*)    warn "key 有 write 但无 files 权限,文件上传可能受限" ;;
      *)            ok "Web API key 有 write + files 权限" ;;
    esac
  else
    warn "env 缺 ZOTERO_API_KEY / ZOTERO_LIBRARY_ID(挂回/Web 导入需要)"
  fi
else
  bad "env 文件不存在:$ENV_FILE(从 mcp-literature.env.example 复制)"
fi

sec "体检结论"
printf '  通过 %d · 警告 %d · 失败 %d\n' "$P" "$W" "$F"
if [ "$F" -gt 0 ]; then
  echo "  → 有失败项,先修上面 ❌ 再跑完整流程"; exit 2
elif [ "$W" -gt 0 ]; then
  echo "  → 无致命问题;⚠️ 项按需处理(如翻译前先 start-pdf2zh)"; exit 0
else
  echo "  → 全绿,可跑检索 / 翻译 / 挂回全流程 🚀"; exit 0
fi
