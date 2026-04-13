#!/usr/bin/env python3
"""
PreToolUse hook：禁止 Claude 修改 raw/ 目录下的任何文件。
被 .claude/settings.json 的 PreToolUse hook 调用。
"""
import sys
import os
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

path = sys.argv[1] if len(sys.argv) > 1 else ""

if path.startswith("raw/") or "/raw/" in path:
    print(f"[HOOK BLOCKED] 禁止修改 raw/ 目录：{path}")
    print("raw/ 是只读原始资料层，请将内容整理后写入 wiki/ 目录。")
    sys.exit(1)

sys.exit(0)
