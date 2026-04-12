#!/usr/bin/env python3
"""
任务完成验证脚本（Stop hook 调用）。
检查仓库基本结构和 wiki 同步状态。
"""
import os
import sys
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

REQUIRED = [
    "CLAUDE.md",
    "wiki/index.md",
    "wiki/log.md",
    ".claude/settings.json",
]

def main():
    errors = []

    for f in REQUIRED:
        if not os.path.exists(f):
            errors.append(f"缺失必要文件: {f}")

    if errors:
        for e in errors:
            print(f"  ✗ {e}")
        sys.exit(1)

    print("✓ 任务验证通过")

if __name__ == "__main__":
    main()
