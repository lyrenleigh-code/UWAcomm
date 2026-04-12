# Implement 工作流

按照 spec + plan 执行实现，产出代码、测试和文档。

## 步骤

### 1. 确认输入

- 读取 `specs/active/` 中的 spec
- 读取 `plans/` 中的对应计划
- 确认计划已获用户确认

### 2. 实现代码

按计划中的步骤逐步实现：
- 在 `src/` 中创建或修改代码文件
- 遵循 `.claude/rules/engineering.md` 中的代码规范
- 保持函数小而可测试

### 3. 编写测试

- 在 `tests/` 中添加或更新测试
- 覆盖正常路径和边界条件
- 如果不需要测试，在 plan 中说明原因

### 4. 运行验证

```bash
# 运行测试
pytest -q

# Wiki lint（如果修改了 wiki/）
python3 scripts/lint_wiki.py

# 任务完成验证
python3 scripts/validate_task.py
```

### 5. 同步 wiki（如需要）

当以下内容发生变化时，必须更新 wiki：

| 变更类型 | 更新目标 |
|---------|---------|
| 系统架构变更 | `wiki/architecture/` |
| 模块接口变更 | `wiki/modules/` |
| 重要设计决策 | `wiki/decisions/` 新建决策记录 |
| 故障和教训 | `wiki/incidents/` 新建事件记录 |

### 6. 归档 spec

任务完成后：
1. 将 spec 从 `specs/active/` 移到 `specs/archive/`
2. 在 plan 中标注完成状态

## 完成标准

- [ ] 代码变更已完成
- [ ] 测试通过
- [ ] wiki 已同步更新（如需要）
- [ ] spec 已归档
- [ ] 最终回复明确说明了变更内容
