---
name: lint-wiki
description: 检查 wiki 结构完整性，修复断链和孤儿页。
---

# 步骤

1. 运行 `python3 scripts/lint_wiki.py`
2. 修复断链（`[[wikilink]]` 指向不存在的页面）
3. 修复孤儿页（wiki/ 下有文件但 index.md 中未注册）
4. 刷新 `wiki/index.md`（页面总数、分类）
5. 如有实质性修复，在 `wiki/log.md` 追加记录
