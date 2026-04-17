---
name: implement-task
description: 按照 spec + plan 执行实现。Orchestrator 模式：每阶段部署 Implementation + Verification + Anti-pattern + Commit 子代理，带证据验证。COPY from docs, don't invent。
---

# 目的

安全地执行 spec + plan，产出代码、测试和文档。主代理作为 **Orchestrator**，不亲自写主力代码——部署子代理执行并验证。

借鉴自 claude-mem `do` skill（see Hub `wiki/source-summaries/thedotmack-claude-mem.md`）。

# Orchestrator 协议

## 规则

- 每个阶段使用**新鲜子代理**（除非上下文小且明确）
- 每个子代理**一个清晰目标** + 要求**证据**（命令/输出/改动的文件）
- 子代理报告完成且主代理确认与 plan 一致**之前**，不推进到下一步

## 每个阶段的三步部署

### 1. Implementation 子代理

目标：执行本阶段实现。
要求：

1. 按 spec 执行，不扩展
2. **COPY from docs, don't invent**——若 API 似乎缺失，**停下并验证**，不要假设其存在
3. 在代码注释中引用文档来源（遇陌生 API 时）
4. 返回：修改的文件 + 运行的命令 + 输出

### 2. Verification 子代理（阶段完成后）

目标：**证明本阶段按 plan 的验证清单通过**。
要求：

1. 按 plan 的验证清单逐条执行
2. 返回：每条检查的命令 + 实际输出 + pass/fail 判定
3. 任一项失败 → 回到 Implementation

### 3. Anti-pattern 子代理（阶段完成后）

目标：grep 扫描 plan Phase 0 识别的**反模式清单**。
要求：

1. 对每个反模式，在本阶段改动的文件中 grep
2. 返回：命中的文件/行 + 上下文片段
3. 任一命中 → 回到 Implementation 修复

### 4. Commit 子代理（**仅当 Verification 和 Anti-pattern 双双通过时**）

目标：创建 commit。
要求：

1. 检查 `git status` + `git diff --stat`
2. 组装 commit message（引用 spec 名 + 阶段编号 + 核心改动）
3. 提交
4. 返回：commit hash + message

## 阶段之间

- 推进到下个阶段前，**整理 handoff**：本阶段产出 + 遗留问题 + 下阶段子代理需要的上下文
- 新阶段子代理从新鲜上下文启动，但**带上 plan + handoff**

# 失败模式防范

- ❌ 子代理"已完成"但未提供命令输出 → **拒收**，重派并要求证据
- ❌ 测试失败但 commit 子代理仍被部署 → **违反协议**，退回 Verification
- ❌ 主代理亲自写主力代码 → **违反 orchestrator 模式**，拆出实际子代理

# 完成标准

- 所有阶段 Verification + Anti-pattern 双通过
- wiki 已同步更新（如架构/模块接口/设计决策变化）
- spec 从 `specs/active/` 移到 `specs/archive/`
- 最终回复明确说明：改动内容 + 每阶段验证证据链

# 与 wiki 的同步

若架构、行为或接口发生变化，更新：

- `wiki/architecture/` — 架构变更
- `wiki/modules/` — 模块接口变更
- `wiki/decisions/` — 重要设计决策（若项目有 `wiki/decisions/`）
- `wiki/conclusions.md` — 技术结论累积（若项目有）

**Stop hook 会校验 wiki/index.md + log.md 同步**——不做会被阻断。
