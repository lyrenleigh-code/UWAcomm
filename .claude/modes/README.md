# UWAcomm Modes（模式配置）

> 借鉴自 claude-mem 的 `code--{lang}.json` mode 系统（see Hub `wiki/source-summaries/thedotmack-claude-mem.md` §3）。
> **当前状态**：P3 试点——结构化抽取 + 版本化，**尚未接入运行时切换**（CLAUDE.md 仍内联当前规范，mode 文件作为可追溯的单一事实源）。

## 模式清单

| 模式 | 场景 | 文件 |
|------|------|------|
| **matlab-zh** | 仿真原型阶段（主用） | [`matlab-zh.json`](matlab-zh.json) |
| _cpp-en_ | 产品化阶段（C/C++，待建） | 预留 |
| _matlab-en_ | 外部协作（英文注释对外审阅） | 预留 |

## 为什么要 mode 化

当前 CLAUDE.md `## Language & Conventions` 段内联 7 条规范。问题：

- 未来若产品化 C++，规范会分叉——CLAUDE.md 会膨胀 / 两套规则混用
- 规范变更无版本历史（只能靠 git）
- 跨项目迁移（如 USBL 移植 C++）时难以复用

mode 化：**规范 = 数据 + 版本 + 场景标签**，CLAUDE.md 只引用"当前 mode = matlab-zh"。

## 现状 vs 最终形态

**现状（P3 试点）**：
- `matlab-zh.json` 作为当前规范的结构化镜像
- CLAUDE.md `## Language & Conventions` 段仍是主事实源（避免两处分叉）
- 任何规范变更**两处同步**

**最终形态（后续推进）**：
- CLAUDE.md 指向 `.claude/modes/${UWACOMM_MODE:-matlab-zh}.json`
- settings.json `env.UWACOMM_MODE` 设置默认 mode
- 运行时脚本在 SessionStart hook 中读 mode → 注入对应规范到上下文
- CLAUDE.md 仅保留"mode 选择逻辑"，规范细节全部在 modes/ 下

## 新建 mode 流程

1. 复制 `matlab-zh.json` → 命名新 mode（如 `cpp-en.json`）
2. 调整 `language` / `conventions` / `testing` / `git` 字段
3. 在本 README 清单表追加一行
4. 如启用运行时切换：更新 settings.json 的 `env.UWACOMM_MODE` 或 SessionStart hook 脚本

## 兼容性注记

Claude Code 原生 harness **无** env-var 驱动的 prompt 切换机制（claude-mem 靠自己的 runtime wrapper 实现）。若未来需要真正的运行时切换：

- **方案 A**：SessionStart hook 读 `$UWACOMM_MODE` → 写一段临时上下文文件 → CLAUDE.md 引用该文件
- **方案 B**：用 `.claude/settings.local.json` per-workspace 覆盖 `env.UWACOMM_MODE`，配合 `paths: **/*.{m,cpp}` skill 按文件类型自动激活

具体方案待首个 mode 分叉场景出现时再定（YAGNI）。
