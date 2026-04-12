# Ingest 工作流

每次新增一份原始资料时，按以下步骤执行。

## 步骤

### 1. 放入 raw/

将文件放入对应子目录：

| 资料类型 | 目标目录 | 来源工具 |
|----------|----------|---------|
| 学术论文、技术报告 | `raw/papers/` | Zotero |
| 网页文章、博客 | `raw/articles/` | Readwise Reader / Firecrawl |
| YouTube / 本地视频转录 | `raw/videos/` | Firecrawl / Whisper / VOMO AI |
| 播客 / 音频转录 | `raw/podcasts/` | Whisper / VOMO AI |
| 书籍笔记 | `raw/books/` | Readwise / 手动 |
| 课程讲义 | `raw/courses/` | 手动 |
| 对话记录、会议笔记、个人思考 | `raw/notes/` | 手动 |
| 社交媒体长帖 | `raw/threads/` | Firecrawl / 手动 |
| 代码仓库、项目资料 | `raw/repos/` | GitHub / 本地 |
| 图片、图表、附件 | `raw/assets/` | 手动 |

命名规范：`YYYY-MM-DD-简短标题.md`

### 2. 生成 source-summary 页

在 `wiki/source-summaries/` 下新建一个 markdown 文件，包含：

```markdown
# [资料标题]

- **来源**：[URL 或文件路径]
- **日期**：YYYY-MM-DD
- **类型**：论文 / 文章 / 视频 / 播客 / 书籍 / 课程 / 笔记 / 帖子
- **原始文件**：raw/{type}/{filename}

## 核心观点

1. [观点一]
2. [观点二]

## 相关概念

- [概念名](../concepts/概念文件名.md)

## 相关实体

- [实体名](../entities/实体文件名.md)

## 引用摘录

> [重要原文片段]
```

### 3. 更新或新建相关概念页

检查 `wiki/index.md`，判断是否需要：

- 新建概念页（`wiki/concepts/`）
- 新建实体页（`wiki/entities/`）— 人物、工具、项目、组织
- 更新已有页面（追加新信息，注明来源）

### 4. 更新 wiki/index.md

在对应分类下追加新页面条目。更新页面总数和最后更新日期。

### 5. 更新 wiki/log.md

在最新条目下方追加：

```
- YYYY-MM-DD: ingest [资料标题]，新增/更新了 N 个页面
```

### 6. 运行 lint 验证

```bash
python3 scripts/lint_wiki.py
```

确保无孤儿页、无缺失 index 条目。

## 各类型 ingest 要点

### 论文 (papers)
- 提取：标题、作者、年份、DOI、核心贡献、方法论、实验结论
- 概念页重点：方法论和核心概念

### 文章 (articles)
- 提取：作者观点、论据、实践建议
- 如有 Readwise 高亮，优先使用高亮内容

### 视频 (videos)
- 转录文本可能较长，需要先结构化（加标题、段落）再提取
- 提取：演讲者核心论点、关键时间点对应的观点

### 播客 (podcasts)
- 类似视频，但通常是对话体，需区分不同发言人的观点
- 提取：嘉宾的独特见解、与已有知识的关联

### 书籍 (books)
- 可能需要多次 ingest（按章节）
- 提取：核心论点、框架模型、可操作的建议

### 课程 (courses)
- 关注知识体系结构，概念之间的依赖关系
- 提取：核心概念定义、先决条件、练习中的关键发现

### 笔记 (notes)
- 个人思考类内容，关注原创见解和决策记录
- 设计文档类内容，关注架构决策和取舍分析

### 帖子 (threads)
- 通常信息密度高，每条推文可能包含独立观点
- 提取：核心论点、链接的外部资源

### 代码仓库 (repos)
- 关注项目架构、技术选型、核心模块职责
- 提取：项目目标、技术栈、目录结构、关键设计决策
- 实体页重点：项目本身、使用的框架和工具

## 示例

输入命令：
> `/ingest-source raw/notes/toolchain.md`

预期输出：
- `wiki/source-summaries/toolchain.md`
- `wiki/concepts/harness-engineering.md`（新建或更新）
- `wiki/entities/zotero.md`（新建）
- `wiki/entities/readwise-reader.md`（新建）
- `wiki/index.md` 更新
- `wiki/log.md` 更新
