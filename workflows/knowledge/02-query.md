# Query 工作流

当用户提出关于 wiki 知识的问题时，按以下流程执行。

## 步骤

### 1. 检索相关页面

按优先级检索：

| 优先级 | 来源 | 操作 |
|--------|------|------|
| **P1** | `wiki/index.md` | 先读索引，定位相关概念页、实体页、专题页 |
| **P2** | `wiki/` 全文搜索 | 索引中未命中时，搜索 wiki/ 下所有 .md 文件 |
| **P3** | `raw/` 原始资料 | wiki 信息不足时，回到 raw/ 找原始证据补充 |
| **P4** | 外部搜索 | wiki 和 raw 都无法覆盖时，使用 web 搜索或 MCP 工具 |

### 2. 综合回答

- 回答中必须用 `[[wikilink]]` 引用涉及的 wiki 页面
- 涉及多个来源时，明确标注哪个结论来自哪个页面
- 如果 wiki 中存在矛盾信息，使用 `> [!warning] Contradiction` 标注并呈现两方观点

### 3. 判断是否需要 Promote

回答完成后，评估本次回答是否产生了值得沉淀的新结论：

| 条件 | 需要 Promote |
|------|-------------|
| 结论 wiki 里已有 | 否 |
| 结论是单一来源的简单复述 | 否 |
| 结论综合了多个来源，有独立价值 | **是** |
| 结论将来很可能被反复用到 | **是** |
| 结论纠正了 wiki 中的错误或过时信息 | **是** |
| 结论建立了之前未记录的概念间关联 | **是** |

如需 Promote，执行 Promote 工作流（`workflows/promote.md`）。

### 4. 判断是否需要保存为 Exploration

如果本次查询涉及深度分析（跨多个概念页、包含推导过程、或形成了系统性结论），询问用户是否保存为探索页：

- 保存位置：`wiki/explorations/`
- 命名规范：`YYYY-MM-DD-查询主题.md`
- 必须包含 frontmatter（type: exploration）和 `[[wikilink]]` 交叉引用

### 5. 更新 log

在 `wiki/log.md` 追加记录：

```
## [YYYY-MM-DD] query | 查询主题

简要描述查询内容和结论。涉及页面：[[page1]], [[page2]]。
是否 promote：是/否。是否保存 exploration：是/否。
```

## 回答质量标准

- **有出处**：每个事实性断言都可追溯到具体的 wiki 页面或 raw 资料
- **不编造**：wiki 中没有的信息不凭记忆补充，明确告知"wiki 中暂无此信息"
- **标注信心**：对于推断性结论，标注是"wiki 明确记载"还是"基于多页面推断"
- **暴露缺口**：如果发现知识缺口（该有但 wiki 中没有的信息），主动提出建议 ingest 或创建新页面

## 示例

用户问：
> OTFS 和 OFDM 在时变信道下的性能差异？

执行步骤：
1. 读取 `wiki/index.md` → 找到 [[ofdm-and-otfs]]、[[time-varying-channel]]、[[uwacomm]]
2. 读取这三个页面，提取 OTFS vs OFDM 的信道处理方式差异
3. 如果 wiki 不够，去 `raw/papers/2026-04-12-zotero-library-catalog.md` 找相关论文
4. 综合回答，引用 wiki 页面
5. 如果产生了新的对比结论 → Promote 到 [[ofdm-and-otfs]] 或新建 comparison 页
6. 记录到 log
