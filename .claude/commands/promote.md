---
description: 将项目 wiki 中有跨项目价值的结论回流到 Ohmybrain Hub。识别、提取、写入、标记。
---

# Promote — 知识回流 Hub

将当前项目 wiki/ 中有**跨项目价值**的结论提升到 Ohmybrain Hub (`D:\Claude\Ohmybrain\wiki/`)。

## 使用方式

```
/promote <wiki页面路径或主题>    # 指定要回流的内容
/promote                         # 扫描 wiki 找出值得回流的候选
```

## 判断标准

**回流**：换一个项目这条知识还有用吗？
- 通用算法理论（如"基线分解适用任意阵型"）→ 回流
- 设备/工具参数对比（如"商用 USBL 设备表"）→ 回流
- 经验证的工程经验（如"校准航迹需对称"）→ 回流

**不回流**：
- 项目特定参数（如"本项目 d/λ=1.33"）→ 留项目 wiki
- 项目执行计划 → 留项目 wiki
- 未验证的猜想 → 留项目 wiki

## 执行流程

### Step 1: 识别候选

从 $ARGUMENTS 解析目标，或扫描项目 `wiki/` 找出含跨项目价值内容的页面。
列出候选内容，请用户确认要回流哪些。

### Step 2: 定位 Hub 目标页面

读取 `D:\Claude\Ohmybrain\wiki\index.md`，确定每条结论应写入 Hub 的哪个页面：
- 已有 concept 页 → 追加到该页的"来源"或对应章节
- 需要新页 → 创建新 concept/source-summary 页

### Step 3: 写入 Hub

对每条回流内容：
1. 在 Hub wiki 目标页面的合适位置追加内容
2. 标注来源项目：`（来自 USBL 项目 [[文件名]]）`
3. 如果是新页面，在 Hub `wiki/index.md` 追加条目

### Step 4: 同步 Hub index + log

更新 `D:\Claude\Ohmybrain\wiki\index.md` 页面计数。
在 `D:\Claude\Ohmybrain\wiki\log.md` 记录回流操作。

### Step 5: 标记项目侧

在项目 wiki 的源页面 frontmatter 中追加：
```yaml
promoted_to_hub: 2026-04-13
promoted_topics: ["目标概念页名"]
```
防止重复回流。

## 注意事项

- Hub wiki 内容用中文
- 回流的是**结论和经验**，不是原始数据的复制
- 保持 Hub 页面的简洁性，不要把项目细节全搬过去
- 回流后运行 Hub 的 `python scripts/lint_wiki.py` 验证
