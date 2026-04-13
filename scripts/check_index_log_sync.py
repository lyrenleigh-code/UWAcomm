#!/usr/bin/env python3
"""
Stop hook：检查如果 wiki/ 有变更，index.md 和 log.md 是否也被更新。
通过 git diff 判断。
"""
import subprocess
import sys
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")


def get_changed_files():
    result = subprocess.run(
        ["git", "diff", "--name-only", "HEAD"],
        capture_output=True, text=True
    )
    return result.stdout.strip().split("\n")


changed = get_changed_files()
wiki_changed = any(f.startswith("wiki/") and f not in ("wiki/index.md", "wiki/log.md")
                   for f in changed)

if wiki_changed:
    index_updated = "wiki/index.md" in changed
    log_updated = "wiki/log.md" in changed

    missing = []
    if not index_updated:
        missing.append("wiki/index.md")
    if not log_updated:
        missing.append("wiki/log.md")

    if missing:
        print(f"[HOOK BLOCKED] wiki/ 有变更，但以下文件未更新：{', '.join(missing)}")
        print("请先更新这些文件再结束任务。")
        sys.exit(1)

print("✓ index/log 同步检查通过")
sys.exit(0)
