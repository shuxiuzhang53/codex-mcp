#!/usr/bin/env bash
set -euo pipefail

# 按需启动 pdf2zh 翻译 server(监听 8890)。
# 已在跑就直接返回;没跑就从 WSL 通过 interop 拉起 Windows 上的 pdf2zh.exe(最小化),
# 然后等它就绪。翻译用完可以直接关掉那个窗口,不必常驻。
#
# 用法: ./start-pdf2zh.sh
# 依赖: WSL mirrored 网络(否则 WSL 够不到 Windows 的 127.0.0.1:8890)。

PORT="${PDF2ZH_PORT:-8890}"
URL="http://127.0.0.1:${PORT}"
# PDF2Zh 服务器安装位置。改成你自己的,或用环境变量 PDF2ZH_SERVER_DIR/PDF2ZH_SERVER_EXE 覆盖。
EXE_DIR="${PDF2ZH_SERVER_DIR:-D:\\zotero_translate\\server}"
EXE="${PDF2ZH_SERVER_EXE:-${EXE_DIR}\\pdf2zh.exe}"
TIMEOUT="${PDF2ZH_START_TIMEOUT:-30}"

alive() {
  curl -sS -o /dev/null --noproxy '*' --max-time 3 "$URL" 2>/dev/null
}

if alive; then
  echo "pdf2zh server 已在运行: $URL"
  exit 0
fi

echo "启动 pdf2zh server ..."
powershell.exe -NoProfile -Command \
  "Start-Process -FilePath '${EXE}' -WorkingDirectory '${EXE_DIR}' -WindowStyle Minimized" \
  >/dev/null 2>&1 || {
  echo "无法通过 PowerShell 启动 pdf2zh.exe;请确认路径存在: $EXE" >&2
  exit 1
}

for ((i = 1; i <= TIMEOUT; i++)); do
  if alive; then
    echo "pdf2zh server 就绪: $URL (用时 ${i}s)"
    exit 0
  fi
  sleep 1
done

echo "启动超时: ${TIMEOUT}s 内 $URL 未就绪。手动双击桌面 PDF2Zh 看是否报错。" >&2
exit 1
