---
description: 摄入论文/资料到项目 wiki。读取 raw/ 中的原始资料，创建结构化 wiki 页面，更新索引和日志。
---

# Ingest — 知识摄入工作流

将 raw/ 中的原始资料（论文、文章、笔记等）摄入到 wiki/ 知识体系中。

## 使用方式

```
/ingest <文件名或描述>
/ingest                    # 无参数时，扫描 raw/ 中未摄入的资料
```

## 执行流程

按以下步骤严格执行，不可跳步：

### Step 0: 查询 Hub 已有知识

在开始摄入前，先检查 Ohmybrain Hub 是否已有相关知识：

1. 读取 `D:\Claude\Ohmybrain\wiki\index.md`
2. 搜索 Hub wiki 中与待摄入资料相关的 concept/source-summary 页面
3. 如果 Hub 已有相关内容，在后续步骤中建立交叉引用

### Step 1: 识别待摄入资料

从 $ARGUMENTS 解析目标文件。如果无参数：
1. 扫描 `raw/` 目录下所有文件
2. 对比 `wiki/index.md` 中已有的 source-summary 页面
3. 列出未摄入的资料，请用户确认

### Step 2: 提取资料内容

根据文件类型：
- **PDF 论文**：用 PyMuPDF 提取文本，或读取图片页面做 OCR
- **Markdown 笔记**：直接读取
- **其他**：根据文件类型选择合适的提取方法

提取关键信息：标题、作者、年份、核心方法、关键参数、主要结论。

### Step 3: 创建 wiki 页面

根据资料类型，使用 `.obsidian/templates/` 中的模板：

**论文** → 使用 `paper-note.md` 模板，创建到 `wiki/source-summaries/{slug}.md`

必填字段：
- frontmatter: type, source_type, authors, year, status, created, updated
- 核心贡献（一句话）
- 研究问题
- 方法/算法
- 实验结果
- 与项目的关联

**其他资料** → 使用 `source-summary.md` 模板

### Step 4: 更新相关 concept 页面

1. 检查 `wiki/concepts/` 下是否有与论文相关的概念页
2. 如果有，在概念页的"来源"部分追加对新 source-summary 的引用
3. 如果论文引入了新概念且值得单独建页，创建新的 concept 页面

### Step 5: 同步 index.md

在 `wiki/index.md` 的 `Source Summaries` 部分追加新条目：
```
- [slug](source-summaries/slug.md) — 一句话描述
```

更新页面总数。

### Step 6: 更新 log.md

在 `wiki/log.md` 当天日期下追加：
```
- 摄入论文：{标题}（{作者}, {年份}）→ wiki/source-summaries/{slug}.md
```

### Step 7: 验证

1. 运行 `python scripts/lint_wiki.py` 检查无孤儿页、无断链
2. 确认 index.md 中新条目链接有效
3. 报告摄入结果

## 批量摄入

当有多篇论文需要摄入时：
1. 先全部执行 Step 2 提取内容
2. 再依次执行 Step 3-6 创建页面
3. 最后统一执行 Step 7 验证

## 注意事项

- **不修改 raw/**：raw/ 是只读区，所有产出写入 wiki/
- **slug 命名规则**：`{作者姓拼音}-{年份}-{关键词}`，如 `yumin-2006-lr-usbl`
- **中文撰写**：所有 wiki 内容用中文
- **交叉引用**：使用 `[[slug]]` wikilink 格式建立页面间引用
- **不重复摄入**：如果 wiki 中已有该资料的页面，提示用户并跳过
