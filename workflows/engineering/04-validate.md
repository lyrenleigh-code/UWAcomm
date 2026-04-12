# Validate 工作流

任务完成前的最终验证，确保交付物完整。

## 检查清单

### 代码质量

- [ ] `pytest -q` 测试全部通过
- [ ] 无未处理的 lint 警告
- [ ] 代码符合 `.claude/rules/engineering.md` 规范

### Wiki 同步

- [ ] `python3 scripts/lint_wiki.py` 通过（无孤儿页、无断链）
- [ ] `python3 scripts/sync_index.py` 页面计数正确
- [ ] 架构/模块变更已反映到 wiki

### 任务闭合

- [ ] `python3 scripts/validate_task.py` 通过
- [ ] spec 已从 `specs/active/` 移到 `specs/archive/`
- [ ] plan 中标注完成状态
- [ ] git 变更已提交

### 自动化验证命令

```bash
# 一键验证
python3 scripts/validate_task.py && \
python3 scripts/lint_wiki.py && \
python3 scripts/sync_index.py && \
echo "✓ 全部验证通过"
```

## 验证失败处理

| 失败项 | 处理 |
|--------|------|
| 测试不通过 | 修复代码或测试，重新运行 |
| wiki lint 失败 | 补全 index 条目或修复断链 |
| validate 失败 | 检查缺失的必要文件 |
| spec 未归档 | 确认任务确实完成，移入 archive |
