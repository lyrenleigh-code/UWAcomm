# Validate 工作流

实现完成后的收尾流程：验证、同步、归档、提交。

## 前置条件

03-implement 已产出三件套（代码 + 测试 + 模块 README）。

## 步骤

### 1. 运行验证

```bash
# 运行测试（MATLAB 项目用对应测试脚本）
pytest -q  # 或 MATLAB: run('test_xxx.m')

# Wiki 结构检查
python scripts/lint_wiki.py

# 任务完整性检查
python scripts/validate_task.py
```

全部通过才继续。失败则回到 03-implement 修复。

### 2. 同步 wiki

当以下内容发生变化时，必须更新 wiki：

| 变更类型 | 更新目标 |
|---------|---------|
| 系统架构变更 | `wiki/architecture/` |
| 模块接口变更 | `wiki/modules/` |
| 重要设计决策 | `wiki/decisions/` 新建决策记录 |
| 故障和教训 | `wiki/debug-logs/` 追加记录 |
| 新的技术结论 | `wiki/concepts/` 或 `wiki/topics/` |

wiki 变更后必须同步更新 `wiki/index.md` 和 `wiki/log.md`。

### 3. 归档 spec

1. 将 spec 从 `specs/active/` 移到 `specs/archive/`
2. 在 plan 中标注完成状态和日期

### 4. Git 提交

```bash
git add <涉及的文件>
git commit -m "<type>: <描述>"
```

提交后考虑：
- 有跨项目价值的结论 → `/promote` 回流 Hub
- 更新 `wiki/dashboard.md` 进度状态

## 一键验证命令

```bash
python scripts/validate_task.py && \
python scripts/lint_wiki.py && \
echo "✓ 全部验证通过"
```

## 验证失败处理

| 失败项 | 处理 |
|--------|------|
| 测试不通过 | 回到 03-implement 修复代码或测试 |
| wiki lint 失败 | 补全 index 条目或修复断链 |
| validate 失败 | 检查缺失的必要文件 |
