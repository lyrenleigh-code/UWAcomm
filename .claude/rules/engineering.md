---
paths:
  - src/**
  - tests/**
  - evals/**
---

# 工程代码规则

- 每个代码任务必须先有 `specs/active/` 下的 spec
- 非平凡实现必须先有 `plans/` 下的计划
- 代码变更必须附带测试，或说明为何不需要测试
- 函数保持小而可测试
- 变量和函数命名清晰，避免过度缩写
- 当模块边界、架构或接口发生变化时，同步更新 `wiki/architecture/` 或 `wiki/modules/`
