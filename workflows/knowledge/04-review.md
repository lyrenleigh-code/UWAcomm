# Wiki Review 工作流

定期对 wiki 进行健康检查和维护，确保知识库质量持续提升。

## 执行频率

| 类型 | 频率 | 触发方式 |
|------|------|---------|
| 快速检查 | 每周 | 手动或 `/lint-wiki` |
| 完整 Review | 每月 | 手动执行本流程 |
| 深度审计 | 每季度 | 结合研究方向回顾 |

## 步骤

### 1. 运行自动化检查

```bash
cd H:/ohmybrain
python3 scripts/lint_wiki.py
```

检查项：
- [ ] 孤儿页（wiki/ 下有文件但 index.md 中未注册）
- [ ] 断链（`[[wikilink]]` 指向不存在的页面）
- [ ] log.md 存在且格式正确

### 2. 检查数据完整性

| 检查项 | 方法 | 处理 |
|--------|------|------|
| index 页面计数 | 对比 index.md 的 `页面总数` 与实际文件数 | 修正计数 |
| log 连续性 | 检查 log.md 是否有遗漏的操作记录 | 补充记录 |
| frontmatter 完整性 | 抽查页面的 type/created/updated/tags | 补全缺失字段 |
| raw/ 只读性 | `git log --diff-filter=M -- raw/` 检查 raw 是否被修改 | 恢复原始文件 |

### 3. 内容质量审查

#### 3.1 过时信息标记

找出超过 3 个月未更新的页面：

```bash
# 检查 frontmatter 中 updated 字段距今超过 90 天的页面
grep -rl "updated:" wiki/ | xargs grep "updated: 202[0-5]"
```

对过时页面：
- 信息仍然正确 → 更新 `updated` 日期
- 信息可能过时 → 添加 `> [!warning] 待验证` 标注
- 信息明确过时 → 更新内容并注明变更原因

#### 3.2 高引用页面审查

找出被 `[[wikilink]]` 引用最多的页面：

```bash
# 统计每个页面被引用的次数
grep -roh '\[\[[a-z-]*\]\]' wiki/ | sort | uniq -c | sort -rn | head -20
```

高引用页面（>5 次引用）需重点审查：
- 内容是否足够全面？是否需要拆分？
- 是否存在矛盾或含糊表述？
- 是否缺少交叉引用？

#### 3.3 低质量页面识别

| 信号 | 判断标准 | 处理 |
|------|---------|------|
| 内容过短 | 正文少于 5 行 | 补充或合并到其他页面 |
| 无交叉引用 | 没有 `[[wikilink]]` | 添加相关链接 |
| 无来源 | 没有标注信息来源 | 补充来源或标记待验证 |
| 标签缺失 | frontmatter tags 为空 | 补充标签 |

### 4. 知识缺口分析

#### 4.1 概念页覆盖度

对照 Zotero 文件夹和论文标签，检查：
- Zotero 中有大量论文但 wiki 无对应概念页的方向 → 建议创建
- wiki 概念页存在但内容空洞的方向 → 建议 ingest 相关论文补充

#### 4.2 未 Promote 的结论

回顾近期对话记录（如有），检查是否有重要结论未写入 wiki。

#### 4.3 研究地图更新

对照 [[research-map]]：
- 是否有新的研究方向需要添加？
- 各方向的论文数量是否需要更新？
- 方向间的关系是否有新发现？

### 5. 生成 Review 报告

在 `wiki/explorations/` 下创建 review 报告：

```markdown
---
type: exploration
created: YYYY-MM-DD
updated: YYYY-MM-DD
tags: [review, 维护]
---

# Wiki Review — YYYY-MM-DD

## 基本指标

| 指标 | 数值 | 变化 |
|------|------|------|
| 页面总数 | N | +M |
| 概念页 | N | |
| 实体页 | N | |
| 摘要页 | N | |
| 孤儿页 | N | |
| 断链数 | N | |

## 本月变更摘要

（从 log.md 中提取）

## 发现的问题

1. ...

## 执行的修复

1. ...

## 知识缺口

1. ...

## 下月计划

1. ...
```

### 6. 更新 log

```
## [YYYY-MM-DD] review | 月度 Review

执行月度 wiki review：
- 页面总数：N
- 修复问题：N 个
- 发现缺口：N 个
- 报告：explorations/YYYY-MM-DD-review.md
```

## 自动化支持

### lint 脚本增强建议

当前 `scripts/lint_wiki.py` 只检查孤儿页和 log 存在。可逐步扩展：

| 检查项 | 优先级 | 状态 |
|--------|--------|------|
| 孤儿页 | P1 | ✅ 已实现 |
| log.md 存在 | P1 | ✅ 已实现 |
| 断链检测 | P1 | 待实现 |
| frontmatter 完整性 | P2 | 待实现 |
| 过时页面标记 | P2 | 待实现 |
| 引用计数统计 | P3 | 待实现 |
| 内容长度检查 | P3 | 待实现 |
