---
name: ingest-source
description: 读取 raw/ 下的原始资料，更新 wiki 知识层。
---

# 目的

将原始资料转化为结构化的 wiki 知识。

# 步骤

1. 读取 `raw/` 下的目标文件
2. 在 `wiki/source-summaries/` 创建或更新摘要页
3. 更新最相关的知识页：
   - `wiki/concepts/` — 概念和方法
   - `wiki/entities/` — 人物、工具、项目
   - `wiki/architecture/` — 系统架构（如果涉及）
   - `wiki/modules/` — 模块设计（如果涉及）
   - `wiki/decisions/` — 设计决策（如果涉及）
   - `wiki/comparisons/` — 对比分析（如果涉及）
4. 更新 `wiki/index.md`（页面总数 + 对应分类）
5. 在 `wiki/log.md` 追加操作记录

# 约束

- 不修改 raw/ 下的原始文件
- 优先链接到已有页面，而非创建重复页面
- 所有 wiki 内容用中文撰写
- 完成后报告创建/更新了哪些 wiki 页面
