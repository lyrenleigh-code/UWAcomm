---
paths:
  - wiki/**
---

# Wiki 规则

- 所有 wiki 内容用中文撰写
- 每个新页面必须包含完整 frontmatter（type、created、updated、tags）
- 每个新页面至少链接回一个父页面（通过 `[[wikilink]]`）
- 来源派生的结论必须引用对应的 source-summary 页
- 不要把 raw/ 的原文搬入 wiki/，要提炼和结构化
- 修改 wiki/ 下任何文件后，必须同步更新 `wiki/index.md` 和 `wiki/log.md`
- 存在矛盾信息时，使用 `> [!warning] Contradiction` 标注，不要静默覆盖
