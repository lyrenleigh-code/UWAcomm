# raw/ — 只读原始资料层

此目录存放所有原始输入资料。**入库后不得修改或删除**（由 PreToolUse hook 强制）。

需要标注或整理时，将提炼后的内容写入 `wiki/` 对应页面。

## 子目录

| 目录 | 内容 | 导入方式 |
|------|------|---------|
| `articles/` | 网页文章 | `python scripts/scrape.py <URL>` |
| `papers/` | 论文 PDF + 元数据 | 手动放入 / Zotero 导入 |
| `videos/` | 视频转录文本 | `python scripts/transcribe.py <文件>` |
| `podcasts/` | 播客转录文本 | `python scripts/transcribe.py <文件> --type podcast` |
| `books/` | 书籍摘要 | 手动创建 |
| `courses/` | 课程笔记 | 手动创建 |
| `notes/` | 个人笔记、灵感 | 手动创建 |
| `threads/` | 论坛/社交帖子 | `python scripts/scrape.py <URL> --type thread` |
| `repos/` | 外部代码仓库参考 | git clone（.gitignore 已排除） |
| `assets/` | 图片、截图等媒体 | 手动放入 / Obsidian 粘贴 |
