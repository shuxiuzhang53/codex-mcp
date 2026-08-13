/**
 * Zotero Actions & Tags 动作脚本：用 pdf2zh 翻译 PDF 并回附中文/双语译本
 *
 * 适配自 https://github.com/windingwind/zotero-actions-tags/discussions/491 (@liszt01)
 * 改动：菜单触发 + 批量(items) + to-translate 标签过滤 + 译后自动改标签 + Windows 路径。
 *
 * 用法：在 Actions & Tags 里新建 action：
 *   - Event: 选 "Menu item"(菜单触发,最可靠)。也可再加一个 "Create item" 版本自动跑本地保存的条目。
 *   - Operation: "Script"
 *   - 把本文件内容整段粘进脚本框。
 * 然后在 Zotero 里按 `to-translate` 标签筛选条目 → 全选 → 右键菜单运行本 action。
 *
 * 依赖：本机(Zotero 所在机器,通常是 Windows)已安装 pdf2zh CLI,且下面的 pdf2zhPath 指向它。
 */

// ============ 配置 ============
// pdf2zh 可执行文件的绝对路径。用 `where pdf2zh`(Windows)/ `which pdf2zh`(mac/Linux)查。
const pdf2zhPath = "C:\\Users\\你的用户名\\.local\\bin\\pdf2zh.exe";
// mac/Linux 示例: "/home/you/.local/bin/pdf2zh"

// pdf2zh CLI 参数。注意:不同 pdf2zh 版本的 flag 可能不同,先用 `pdf2zh --help` 核对。
// li=源语言 lo=目标语言 s=翻译引擎(google 免费无需 key) t=线程数
const config = {
  li: "en",
  lo: "zh",
  s: "google",
  t: "4",
};

// 只翻译带这个标签的条目(菜单批量时的安全过滤)。设为 "" 可关闭过滤,翻译所有选中项。
const requireTag = "to-translate";
// 翻译成功后:去掉上面的标签,并打上这个标签(设为 "" 则不打)。便于区分已翻译。
const doneTag = "translated";

// createItem 触发时,等待 Connector 下载 PDF 的毫秒数;菜单触发已有 PDF,设 0 即可。
const downloadWaitMs = 0;
// ============================

const sleep = (t) => new Promise((r) => setTimeout(r, t));

async function getPDFAttachment(item) {
  let pdf;
  if (item.isPDFAttachment()) {
    pdf = item;
  } else if (item.isRegularItem()) {
    const maxTries = 12;
    for (let i = 0; i < maxTries; i++) {
      const pdfs = item
        .getAttachments()
        .map((id) => Zotero.Items.get(id))
        .filter((a) => a.isPDFAttachment());
      if (pdfs.length > 0) {
        pdf = pdfs[0];
        break;
      }
      await sleep(5000);
    }
  }
  if (!pdf) throw new Error("[pdf2zh] 未找到 PDF 附件");
  return pdf;
}

function buildOutputPaths(srcPDFPath) {
  const dir = PathUtils.parent(srcPDFPath);
  const base = PathUtils.filename(srcPDFPath).replace(/\.pdf$/i, "");
  return {
    mono: PathUtils.join(dir, `${base}-mono.pdf`),
    dual: PathUtils.join(dir, `${base}-dual.pdf`),
    dir,
  };
}

async function runPDF2zh(srcPDFPath, outputDir) {
  const cfg = { ...config, o: outputDir };
  const args = [srcPDFPath, ...Object.entries(cfg).flatMap(([k, v]) => [`-${k}`, String(v)])];
  Zotero.debug(`[pdf2zh] exec: ${pdf2zhPath} ${args.join(" ")}`);
  await Zotero.Utilities.Internal.exec(pdf2zhPath, args);
}

async function attachTranslatedPDF(parentItemID, dstPDFPath) {
  const pane = Zotero.getActiveZoteroPane();
  const added = await pane.addAttachmentFromDialog(true, parentItemID, [dstPDFPath]);
  Zotero.debug(`[pdf2zh] 已回附: ${added[0].getField("title")}`);
}

async function updateTags(regularItem) {
  if (!regularItem || !regularItem.isRegularItem()) return;
  if (requireTag) regularItem.removeTag(requireTag);
  if (doneTag) regularItem.addTag(doneTag);
  await regularItem.saveTx();
}

async function translateOne(item) {
  if (!item) return "[pdf2zh] 空条目,跳过";
  if (!item.isRegularItem() && !item.isPDFAttachment()) {
    return "[pdf2zh] 非条目/非 PDF,跳过";
  }

  // 标签过滤:找到承载标签的父条目
  const regularItem = item.isRegularItem()
    ? item
    : Zotero.Items.get(item.parentItemID);
  if (requireTag && regularItem && regularItem.isRegularItem()) {
    const tags = regularItem.getTags().map((t) => t.tag);
    if (!tags.includes(requireTag)) {
      return `[pdf2zh] 无 ${requireTag} 标签,跳过: ${regularItem.getField("title")}`;
    }
  }

  try {
    if (!(await IOUtils.exists(pdf2zhPath))) {
      throw new Error(`pdf2zh 不存在: ${pdf2zhPath}`);
    }
    if (downloadWaitMs > 0) await sleep(downloadWaitMs);

    const pdf = await getPDFAttachment(item);
    const srcPDFPath = await pdf.getFilePathAsync();
    const { mono, dual, dir } = buildOutputPaths(srcPDFPath);

    await runPDF2zh(srcPDFPath, dir);

    if (!(await IOUtils.exists(mono))) throw new Error("未生成 mono(纯中文)PDF");
    await attachTranslatedPDF(pdf.parentItemID, mono);
    if (await IOUtils.exists(dual)) {
      await attachTranslatedPDF(pdf.parentItemID, dual);
    }

    await updateTags(regularItem);
    return `[pdf2zh] 完成: ${regularItem ? regularItem.getField("title") : srcPDFPath}`;
  } catch (err) {
    Zotero.debug(err);
    return `[pdf2zh] 错误: ${err.message}`;
  }
}

// 支持菜单批量(items 数组)与单条(item)两种触发
const targets = typeof items !== "undefined" && items && items.length ? items : [item];
const results = [];
for (const it of targets) {
  results.push(await translateOne(it));
}
return results.join("\n");
