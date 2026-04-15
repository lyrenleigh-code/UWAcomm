#!/usr/bin/env python3
"""
PostToolUse hook: Bash 命令涉及 raw/ 且含引入类动词时，提醒走 /ingest。

动机：raw/ 的 Edit/Write 已被 check_raw_write.py 拦，但 Bash（git clone / curl / cp / mv 等）
可合法扩充 raw/——此时应自动提醒走 /ingest，避免"raw/ 已新增但 wiki/source-summaries/ 漏写"。

实现方式：轻量命令模式匹配。
- raw/ 通常在 .gitignore（含 raw/repos/），git ls-files 检测不到——改用命令字符串模式
- 允许少量误报（如 `cp raw/x.md ./tmp/` 会触发），用户可忽略
- 优先避免漏报（代价高：知识漂移）

非阻断（exit 0），仅 stdout 提示。
"""
import io
import json
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)

if data.get("tool_name") != "Bash":
    sys.exit(0)

command = data.get("tool_input", {}).get("command", "")

# 必须同时：命令里提到 raw/ + 含引入类动词
if "raw/" not in command:
    sys.exit(0)

VERBS = r"\b(git\s+clone|curl|wget|scp|rsync|cp|mv|tar|unzip)\b"
if not re.search(VERBS, command):
    sys.exit(0)

# 提取疑似 raw/ 目标路径用于提示（raw/ 后面第一个路径 token）
m = re.search(r"(raw/[\w\-./]+)", command)
target_hint = f"（疑似目标: {m.group(1)}）" if m else ""

print(f"[reminder] Bash 命令可能向 raw/ 引入新资料 {target_hint}")
print("  → 如果是新资料，考虑运行 `/ingest <路径>` 沉淀到 wiki/source-summaries/")
sys.exit(0)
