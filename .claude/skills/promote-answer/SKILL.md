---
name: promote-answer
description: 将对话中的高价值结论写回 wiki，防止知识流失。
---

# 步骤

1. 识别本次对话中值得沉淀的结论
2. 判断结论的归属：
   - 概念/方法 → `wiki/concepts/`
   - 架构/系统设计 → `wiki/architecture/`
   - 模块/接口 → `wiki/modules/`
   - 设计决策 → `wiki/decisions/`
   - 故障/教训 → `wiki/incidents/`
   - 对比分析 → `wiki/comparisons/`
   - 深度探索 → `wiki/explorations/`
3. 创建或更新目标 wiki 页面
4. 添加反向链接到 `wiki/index.md`
5. 在 `wiki/log.md` 追加记录

# 约束

- 不 promote 纯调试过程、临时上下文、可从代码直接获取的信息
- 每条结论写入一个最相关的页面，不在多处重复
- 标注来源（对话日期 + 简述）
