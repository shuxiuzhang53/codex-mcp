# Codex → Zotero → pdf2zh 翻译链路

在"Codex 检索论文 → 导入 Zotero"之上，接上"英文 PDF → 中文译本"。有两条路，**推荐路线 B(终端全自动，已端到端验证)**。

---

## 路线 B:终端全自动(推荐)

一条龙,Codex 或你在终端直接驱动,译本自动作为附件挂回 Zotero 条目:

```text
start-pdf2zh.sh      拉起 PDF2Zh 翻译 server(8890)
translate-pdf.sh     POST /translate → 译本 mono/dual 落到 server\translated\
attach-to-zotero.sh  经 Zotero Web API 把译本挂回父条目(本地 API 只读,写必须走云端)
```

### 前提

- WSL **mirrored** 网络(否则 WSL 够不到 Windows 的 8890；见主 README)
- 已装 PDF2Zh(guaguastandup 版,带 8890 的 `pdf2zh.exe` server)
- `mcp-literature.env` 里 `ZOTERO_API_KEY`(需 **write** 权限)+ `ZOTERO_LIBRARY_ID`

### 用法

**最省事 —— 一条命令跑完(推荐):**

```bash
./translate-and-attach.sh "/mnt/c/.../paper.pdf" <父条目key> dual
# 内部依次:start-pdf2zh → translate（等待译本产出）→ attach-to-zotero
```

**或分三步(便于调试/自定义):**

```bash
# 1) 确保翻译 server 开着(按需拉起, 已开则秒返回)
#    安装路径不同就设: PDF2ZH_SERVER_DIR='D:\你的\路径'
./start-pdf2zh.sh

# 2) 翻译一个 PDF(mono=纯中文 / dual=双语 / compare / all)
./translate-pdf.sh "/mnt/c/Users/you/Zotero/storage/XXXX/paper.pdf" siliconflowfree dual
#    → 译本落在  D:\zotero_translate\server\translated\
#      命名: <文件名去扩展>.no_watermark.zh.mono.pdf / .dual.pdf

# 3) 把译本挂回 Zotero 父条目(父条目 key 见下面"怎么拿 key")
./attach-to-zotero.sh <父条目key> \
  "/mnt/d/zotero_translate/server/translated/paper.no_watermark.zh.dual.pdf" \
  "中文译本(双语)"
```

同步后,Zotero 桌面端该条目下就会出现中文译本附件。

### ⚠️ 关键坑(都踩过并验证)

| 事项 | 结论 |
|---|---|
| **翻译引擎** | 必须用 `pdf2zh_next`(脚本已默认)。老 `pdf2zh` 引擎在本类打包版里因二进制其实是 next、参数不匹配而失败——右键翻译若选"标准/老引擎"也会挂,选 **pdf2zh_next** 才行。 |
| **本地 API 写不了** | Zotero 23119 是 Connector API,只读;挂回附件只能走云端 Web API(`attach-to-zotero.sh` 已如此)。 |
| **速度** | 免费 siliconflow 单篇约 2-4 分钟,`/translate` 是同步接口,耐心等 fileList 返回。 |
| **要 write 权限的 key** | 挂回是写操作;key 必须有 files+write 权限。 |

### 怎么拿父条目 key

- Codex 场景:它导入/读库时就知道条目 key,直接串三步。
- 手动场景:从本地 API 反查,例如已知附件在 `storage/XXXX/`,`XXXX` 就是附件 key:
  ```bash
  curl -s --noproxy '*' "http://127.0.0.1:23119/api/users/<你的LIBID>/items/XXXX?format=json" \
    | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['parentItem'])"
  ```

### 让 Codex 一句话跑完

在启动了 MCP 的 Codex 里,可以让它读出目标条目的 key 与 PDF 路径,然后依次调
`start-pdf2zh.sh` / `translate-pdf.sh` / `attach-to-zotero.sh` 完成"翻译并挂回"。

### `/translate` 接口契约(逆向所得,供二次开发)

`POST http://127.0.0.1:8890/translate` , JSON:
```jsonc
{
  "fileContent": "data:application/pdf;base64,....",   // PDF 的 base64
  "fileName": "paper.pdf",
  "engine": "pdf2zh_next",         // 用 next!
  "service": "siliconflowfree",    // 免费引擎
  "sourceLang": "en", "targetLang": "zh",
  "qps": 4, "thread_num": 4,
  "mono": true, "dual": true, "compare": false
}
```
返回 `{"status":"success","fileList":["...mono.pdf","...dual.pdf"]}`。

---

## 路线 A:Zotero 内一键(Actions & Tags,备选)

不想用终端、就想在 Zotero 里点的话:用 `zotero-action-pdf2zh.js`(本目录),配成 Actions & Tags 的
菜单动作,按 `to-translate` 标签筛选后右键批量翻译并挂回。注意 Actions & Tags **没有"标签触发"
事件**,只能菜单/`createItem` 触发,所以是"Codex 打标签 + 你右键一次"的半自动。详见脚本头注释。

> 你已经装了 guaguastandup 插件的话,其自带右键翻译本身就能翻+挂回(选 pdf2zh_next 引擎),
> 路线 A 的脚本仅在你想要"按标签批量"时才需要。

---

## 排错

| 现象 | 排查 |
|---|---|
| `translate-pdf.sh` 报 `unrecognized arguments` / exit 2 | 引擎选错;确认用 `pdf2zh_next`(默认) |
| `start-pdf2zh.sh` 超时 | 手动双击桌面 PDF2Zh 看是否报错;`PDF2ZH_SERVER_DIR` 路径对不对 |
| `attach-to-zotero.sh` 创建条目失败 | 父条目 key 错,或 key 无 write 权限 |
| 8890 连不上 | WSL 不是 mirrored,或 server 没起;`wslinfo --networking-mode` 应为 mirrored |
| 译本没同步到桌面 | 等 Zotero 同步,或手动点同步 |
