#!/usr/bin/env bash
set -u

ROOT="${CODEX_LITERATURE_ROOT:-$HOME/codex-mcp}"
ENV_FILE="${CODEX_LITERATURE_MCP_ENV:-$ROOT/mcp-literature.env}"
CONFIG="${CODEX_CONFIG:-$HOME/.codex/config.toml}"

failures=0
warnings=0

section() {
  printf '\n== %s ==\n' "$1"
}

ok() {
  printf 'OK: %s\n' "$1"
}

warn() {
  warnings=$((warnings + 1))
  printf 'WARN: %s\n' "$1"
}

fail() {
  failures=$((failures + 1))
  printf 'FAIL: %s\n' "$1"
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

is_placeholder() {
  case "${1:-}" in
    ""|your-*|paste-*|*example.com*|*TODO*|*CHANGE_ME*|*"你的"*|*"粘贴"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

check_var() {
  name="$1"
  required="$2"
  value="${!name:-}"
  if is_placeholder "$value"; then
    if [[ "$required" == "required" ]]; then
      fail "$name is missing or still uses a placeholder"
    else
      warn "$name is empty or still uses a placeholder"
    fi
  else
    ok "$name is set"
  fi
}

section "Local commands"
for cmd in codex uv uvx; do
  if has_command "$cmd"; then
    ok "$cmd -> $(command -v "$cmd")"
  else
    fail "$cmd is not on PATH"
  fi
done

section "Codex config mode"
if [[ -f "$CONFIG" ]]; then
  ok "Codex config exists: $CONFIG"
  if [[ -w "$CONFIG" ]]; then
    ok "Codex config is writable; persistent MCP config can be appended"
  else
    warn "Codex config is not writable; use $ROOT/codex-literature.sh"
  fi
else
  fail "Codex config not found: $CONFIG"
fi

section "Local wiring files"
for file in \
  "$ROOT/codex-literature.sh" \
  "$ROOT/paper-search-mcp-wrapper.sh" \
  "$ROOT/zotero-mcp-wrapper.sh" \
  "$ROOT/install-literature-mcp-tools.sh" \
  "$ROOT/verify-literature-mcp.sh"; do
  if [[ -x "$file" ]]; then
    ok "$file is executable"
  elif [[ -f "$file" ]]; then
    fail "$file exists but is not executable"
  else
    fail "$file is missing"
  fi
done

section "Private env file"
if [[ -f "$ENV_FILE" ]]; then
  ok "Env file exists: $ENV_FILE"
  mode="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || true)"
  if [[ "$mode" == "600" ]]; then
    ok "Env file permissions are 600"
  else
    warn "Env file permissions are $mode; expected 600"
  fi

  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  check_var PAPER_SEARCH_MCP_UNPAYWALL_EMAIL required
  check_var UNPAYWALL_EMAIL required
  if [[ "${ZOTERO_LOCAL:-}" == "true" ]]; then
    ok "ZOTERO_LOCAL is true; Zotero Web API key/library id are not required for local reads"
  else
    check_var ZOTERO_API_KEY required
    check_var ZOTERO_LIBRARY_ID required
    check_var ZOTERO_LIBRARY_TYPE required
    if [[ "${ZOTERO_LIBRARY_TYPE:-}" == "user" && ! "${ZOTERO_LIBRARY_ID:-}" =~ ^[0-9]+$ ]]; then
      fail "ZOTERO_LIBRARY_ID should be the numeric Zotero User ID for user libraries, not the username"
    fi
  fi
  check_var PAPER_SEARCH_MCP_SEMANTIC_SCHOLAR_API_KEY optional
else
  fail "Env file missing: $ENV_FILE"
fi

section "Zotero local API"
if [[ "${ZOTERO_LOCAL:-}" == "true" ]]; then
  if ps -ef 2>/dev/null | grep -q '[c]odex-linux-sandbox.*network_access":false'; then
    warn "Current Codex tool sandbox has network_access=false; localhost checks may be blocked here"
  fi
  net_mode=""
  if command -v wslinfo >/dev/null 2>&1; then
    net_mode="$(wslinfo --networking-mode 2>/dev/null)"
  fi
  if grep -qi microsoft /proc/version 2>/dev/null && [[ "$net_mode" != "mirrored" ]]; then
    warn "Running inside WSL without mirrored networking; Windows Zotero on localhost may be unreachable (set networkingMode=mirrored in .wslconfig)"
  fi
  if has_command curl && timeout 3s curl -fsS --noproxy '*' "http://127.0.0.1:23119/api/" >/dev/null 2>&1; then
    ok "Zotero local API is reachable on 127.0.0.1:23119${net_mode:+ (WSL networking: $net_mode)}"
  else
    fail "ZOTERO_LOCAL=true but Zotero local API is not reachable; start Zotero and enable local API"
  fi
else
  ok "ZOTERO_LOCAL is not true; using Zotero Web API mode"
fi

section "Package availability"
paper_search_ready=0
zotero_ready=0
paper_search_python="${CODEX_LITERATURE_PAPER_SEARCH_PYTHON:-$ROOT/.venv-paper-search/bin/python}"
if [[ -x "$paper_search_python" ]] && "$paper_search_python" -c 'import paper_search_mcp.server' >/dev/null 2>&1; then
  ok "paper-search-mcp module is installed in $paper_search_python"
  paper_search_ready=1
elif has_command paper-search-mcp; then
  ok "paper-search-mcp executable is on PATH"
  paper_search_ready=1
else
  fail "paper-search-mcp is not installed locally"
fi

if has_command zotero-mcp; then
  ok "zotero-mcp executable is on PATH"
  zotero_ready=1
elif uv tool list 2>/dev/null | grep -q '^zotero-mcp-server '; then
  ok "zotero-mcp-server is installed as a uv tool"
  zotero_ready=1
else
  fail "zotero-mcp-server is not installed locally"
fi

section "Network preflight"
if timeout 5s getent hosts pypi.org >/dev/null 2>&1; then
  ok "pypi.org resolves through system DNS"
elif [[ "$paper_search_ready" == "1" && "$zotero_ready" == "1" ]]; then
  warn "pypi.org does not resolve; installs/upgrades are blocked, but local MCP packages are available"
else
  fail "pypi.org does not resolve; uv/uvx cannot install MCP packages yet"
fi

section "External API reachability"
if [[ "${CODEX_LITERATURE_ALLOW_OFFLINE:-0}" == "1" ]]; then
  warn "CODEX_LITERATURE_ALLOW_OFFLINE=1; skipping external API DNS gates"
else
  if [[ "${ZOTERO_LOCAL:-}" == "true" ]]; then
    ok "ZOTERO_LOCAL is true; api.zotero.org is not required"
  elif timeout 5s getent hosts api.zotero.org >/dev/null 2>&1; then
    ok "api.zotero.org resolves"
  else
    fail "api.zotero.org does not resolve; Zotero Web API import cannot run here"
  fi

  source_hosts=(
    export.arxiv.org
    api.crossref.org
    api.openalex.org
    api.semanticscholar.org
  )
  source_ready=0
  for host in "${source_hosts[@]}"; do
    if timeout 5s getent hosts "$host" >/dev/null 2>&1; then
      ok "$host resolves"
      source_ready=1
    else
      warn "$host does not resolve"
    fi
  done
  if [[ "$source_ready" == "0" ]]; then
    fail "No paper-search source hosts resolve; paper lookup cannot run here"
  fi
fi

section "Codex MCP injection"
if [[ -x "$ROOT/codex-literature.sh" ]] && has_command codex; then
  mcp_list="$(CODEX_LITERATURE_SKIP_PREFLIGHT=1 "$ROOT/codex-literature.sh" mcp list 2>&1 || true)"
  printf '%s\n' "$mcp_list" | sed -n '1,40p'
  if printf '%s\n' "$mcp_list" | grep -q '^paper_search[[:space:]]'; then
    ok "Codex sees paper_search"
  else
    fail "Codex does not list paper_search"
  fi
  if printf '%s\n' "$mcp_list" | grep -q '^zotero[[:space:]]'; then
    ok "Codex sees zotero"
  else
    fail "Codex does not list zotero"
  fi
else
  fail "Cannot run Codex MCP injection check"
fi

section "Summary"
if (( failures == 0 )); then
  if [[ "${CODEX_LITERATURE_ALLOW_OFFLINE:-0}" == "1" ]]; then
    ok "Local MCP startup is ready; external API checks were skipped, so do not run the 3-paper import test yet"
  else
    ok "Ready for the 3-paper end-to-end Zotero import test"
  fi
  if (( warnings > 0 )); then
    warn "$warnings warning(s) remain"
  fi
  exit 0
fi

printf 'BLOCKED: %d failure(s), %d warning(s).\n' "$failures" "$warnings"
printf 'Next: fix the failed checks above, then rerun %s.\n' "$0"
exit 2
