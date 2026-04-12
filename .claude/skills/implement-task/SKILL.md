---
name: implement-task
description: 按照 spec + plan 执行实现，含测试和 wiki 更新。
---

# 目的

安全地执行 spec + plan，产出代码、测试和文档。

# 步骤

1. 读取对应的 spec 和 plan
2. 检查影响的文件当前状态
3. 在 `src/` 中实现变更
4. 在 `tests/` 中添加或更新测试
5. 运行测试验证
6. 如果架构、行为或接口发生变化，更新 `wiki/`：
   - `wiki/architecture/` — 架构变更
   - `wiki/modules/` — 模块接口变更
   - `wiki/decisions/` — 重要设计决策
7. 总结变更内容和验证结果

# 完成标准

- 代码变更已完成
- 测试通过
- wiki 已同步更新（如需要）
- spec 从 `specs/active/` 移到 `specs/archive/`
