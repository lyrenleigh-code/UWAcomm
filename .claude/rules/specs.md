---
paths:
  - projects/**
---

# 任务管理规则

- 每个任务一个文件，包含 Spec / Plan / Log / Result 四个部分
- 任务文件放在 `projects/{项目名}/active/`
- 完成后移到 `projects/{项目名}/archive/`
- Spec 必须包含：目标、原因、范围、非目标、验收标准
- Plan 在 spec 确认后填写，包含：影响文件、步骤、测试策略、风险
- Result 完成后 promote 关键结论到 wiki
