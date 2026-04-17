---
name: plan-task
description: 从 spec 创建实现计划。Phase 0 先做 Documentation Discovery（子代理取 API 签名/示例/反模式），主代理做 synthesis。动手前充分理解需求和影响范围。
---

# 目的

将 spec 转化为**证据驱动、可执行**的工程计划。关键原则：**COPY from docs, don't invent**——实现步骤应该基于文档中真实存在的 API，而非假设或凭空构造。

借鉴自 claude-mem `make-plan` skill（see Hub `wiki/source-summaries/thedotmack-claude-mem.md`）。

# 步骤

## Phase 0：Documentation Discovery（必做，先于任何实现思考）

在起笔 plan **之前**，部署子代理（`general-purpose` 或项目专用）采集事实：

1. 搜索 + 读取相关文档：模块 README / 函数索引 / 架构页 / 官方 API
2. 识别**真实存在的** API、方法、签名（不要假设）
3. 整理"**允许使用的 API 清单**"，每项标注文档来源位置（`modules/07/README.md:L45` 类）
4. 识别**反模式清单**：已知不存在的方法 / 已弃用参数 / 文档明确禁止的做法

主代理**仅做 synthesis**——把子代理的发现整合为 Phase 0 产出。

## Subagent Reporting Contract（强制）

每个子代理响应必须包含（任一缺失则**拒绝重派**，不要接受无证据的结论）：

1. **Sources consulted**：文件/URL + 读了哪些段
2. **Concrete findings**：精确 API 名/签名 + 精确文件路径和行号
3. **Copy-ready snippet locations**：可直接拷贝的示例文件/段位置
4. **Confidence + known gaps**：置信度注记 + 可能未覆盖的缺口

## Phase 1+：实现阶段拆解

1. 读取 `specs/active/` 下的目标 spec
2. 识别范围、约束、依赖和影响文件
3. 检查 `wiki/` 中相关架构或模块文档
4. 在 `plans/` 下创建计划文件：`YYYY-MM-DD-任务名.md`

计划**每个实现阶段**必须包含：

- **What to implement**：任务措辞要"COPY from docs"而非"transform existing code"
  - ✅ Good："Copy the V2 session pattern from `modules/07/README.md:L45-60`"
  - ❌ Bad："Migrate the existing code to V2"
- **Allowed APIs**：引用 Phase 0 产出 + 标注文档位置
- **Anti-patterns to avoid**：本阶段特有的反模式（如果 Phase 0 识别出）
- **验证清单**：本阶段完成后如何证明正确

## 全局计划结构

- 目标和非目标
- 影响的文件/模块
- Phase 0 产出（允许 APIs + 反模式清单）
- 分阶段实现步骤（每阶段用上述结构）
- 测试策略
- 风险和回退方案

# 约束

- 不在计划阶段修改 `src/` 或 `tests/`
- **子代理无证据则拒绝**——宁可 Phase 0 多跑一轮，不要写进未经证实的 API
- 计划完成后等待用户确认再进入实现
